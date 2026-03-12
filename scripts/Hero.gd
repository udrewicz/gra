## scripts/Hero.gd
## Skrypt gracza — CharacterBody2D
## Attach do węzła Hero (CharacterBody2D) w scenie Main.tscn

extends CharacterBody2D

# ── Stałe ──────────────────────────────────────
const SPEED           := Constants.PLAYER_SPEED
const JUMP_VEL        := Constants.JUMP_VEL
const GRAVITY         := Constants.GRAVITY
const ATTACK_DURATION := 0.25   # s
const ATTACK_RANGE_W  := 60.0
const ATTACK_RANGE_H  := 50.0

# ── Stan ───────────────────────────────────────
var facing_dir    : float = 1.0
var is_attacking  : bool  = false
var attack_timer  : float = 0.0
var attack_landed : bool  = false
var is_rolling    : bool  = false
var roll_timer    : float = 0.0
var walk_cycle    : float = 0.0
var _shake_timer  : float = 0.0
var _shake_mag    : float = 0.0

# ── Mobile input (ustawiany przez MobileControls.gd) ──
var mobile_move_x     : float = 0.0
var mobile_jump       : bool  = false
var mobile_attack     : bool  = false
var mobile_interact   : bool  = false
var mobile_shoot      : bool  = false

# ── Referencje ─────────────────────────────────
@onready var camera : Camera2D = $Camera2D

# ── Sygnały ────────────────────────────────────
signal attacked(hit_rect: Rect2, direction: float)
signal interacted
signal shot_arrow
signal bow_needed

func _ready() -> void:
	add_to_group("hero")
	# Ustaw limity kamery na świat
	camera.limit_left   = -int(Constants.HALF_W)
	camera.limit_right  =  int(Constants.HALF_W)
	# Zablokuj pionową kamerę — side-scroller jak w oryginale JS
	# limit_top=0, limit_bottom=720 → kamera zawsze pokazuje y=0..720
	camera.limit_top    = 0
	camera.limit_bottom = 720
	# Podłącz sygnały HeroData
	HeroData.died.connect(_on_died)
	HeroData.hit_taken.connect(func(): camera_shake(6.0, 0.22))

func _physics_process(delta: float) -> void:
	if HeroData.dead: return

	HeroData.tick_iframes(delta)

	# ── Grawitacja ─────────────────────────────
	if not is_on_floor():
		velocity.y += GRAVITY * delta
		velocity.y  = min(velocity.y, 1200.0)  # terminal velocity

	# ── Poruszanie się ─────────────────────────
	var move_x := Input.get_axis("move_left", "move_right")
	if move_x == 0.0: move_x = mobile_move_x

	if move_x != 0.0:
		facing_dir   = sign(move_x)
		velocity.x   = move_x * SPEED
		if is_on_floor(): walk_cycle += delta * 8.0
	else:
		velocity.x   = move_toward(velocity.x, 0.0, SPEED * 2.0 * delta)
		walk_cycle    = 0.0

	# ── Skok wyłączony (oryginał JS nie ma skakania) ───────────────
	mobile_jump = false

	# ── Atak / Strzał ───────────────────────────
	var atk_pressed := Input.is_action_just_pressed("attack") or mobile_attack
	mobile_attack = false
	var weap = HeroData.equipment.get("weapon", null)
	var is_ranged : bool = weap != null and weap.get("range_type", "") == "ranged"
	var has_bow : bool = _player_has_bow()
	if atk_pressed and not is_attacking:
		if is_ranged and has_bow:
			shot_arrow.emit()
		elif not is_ranged:
			_start_attack(weap)

	if is_attacking:
		attack_timer -= delta
		if attack_timer <= 0.0:
			is_attacking  = false
			attack_landed = false

	# ── Strzał (osobny klawisz Q) — tylko gdy ma łuk ───────────────
	var shoot_pressed := Input.is_action_just_pressed("shoot") or mobile_shoot
	mobile_shoot = false
	if shoot_pressed:
		if has_bow:
			shot_arrow.emit()
		else:
			# Brak łuku — wyświetl podpowiedź (sygnał do World)
			bow_needed.emit()

	# ── Interakcja ─────────────────────────────
	var interact_pressed := Input.is_action_just_pressed("interact") or mobile_interact
	mobile_interact = false
	if interact_pressed:
		interacted.emit()

	# ── Stamina ────────────────────────────────
	var is_sprinting := Input.is_action_pressed("sprint") and move_x != 0.0
	if is_sprinting and HeroData.stamina > 0:
		velocity.x *= 1.6
		HeroData.stamina = max(0.0, HeroData.stamina - 0.25 * HeroData.stamina_drain * delta * 60.0)
	else:
		HeroData.stamina = min(HeroData.max_stamina, HeroData.stamina + 0.1 * delta * 60.0)

	# ── Rally point ────────────────────────────
	if Input.is_action_just_pressed("rally"):
		if GameManager.rally_point.is_empty():
			GameManager.rally_point = {"x": position.x, "in_dungeon": GameManager.is_in_dungeon()}
			GameManager.notify("🚩 Rally flag placed!", Color(0.93, 0.27, 0.27))
		else:
			GameManager.rally_point = {}
			GameManager.notify("🚩 Rally flag removed.", Color(0.63, 0.63, 0.63))

	# ── Teleport ───────────────────────────────
	if Input.is_action_just_pressed("teleport"):
		var tp := GameManager.get_building("teleport")
		if not tp.is_empty() and tp["built"]:
			position.x = tp["x"]
			GameManager.notify("🌀 Teleported!", Color(0.51, 0.55, 0.97))

	# ── Zapisz ─────────────────────────────────
	if Input.is_action_just_pressed("save_game"):
		var world := get_parent()
		if world: SaveSystem.save_game(world)

	move_and_slide()
	queue_redraw()
	# Camera shake
	if _shake_timer > 0.0:
		_shake_timer -= delta
		var s := randf_range(-_shake_mag, _shake_mag)
		camera.offset = Vector2(s, s * 0.6)
	else:
		camera.offset = Vector2.ZERO

func camera_shake(magnitude: float = 6.0, duration: float = 0.25) -> void:
	_shake_mag   = magnitude
	_shake_timer = duration

func _player_has_bow() -> bool:
	for slot in HeroData.equipment.values():
		if slot != null and slot.get("range_type", "") == "ranged":
			return true
	return false

func _start_attack(weap = null) -> void:
	is_attacking  = true
	attack_timer  = ATTACK_DURATION
	attack_landed = false
	var range_w := ATTACK_RANGE_W
	if weap != null and weap.get("range_type", "") == "medium":
		range_w = 90.0  # spear extends reach
	var hit_rect := Rect2(
		position.x + (facing_dir * 10.0) - range_w * 0.5,
		position.y - ATTACK_RANGE_H,
		range_w,
		ATTACK_RANGE_H
	)
	attacked.emit(hit_rect, facing_dir)

# ── Rendering ──────────────────────────────────
func _draw() -> void:
	var blink := HeroData.invincible_frames > 0 and fmod(HeroData.invincible_frames * 10.0, 1.0) > 0.5
	if blink: return

	# === 1:1 z HTML drawPlayer() ===
	# wColors[0] = #d4a0ff, wGlows[0] = #9933ff (weaponTier 0)
	var wc     := Color(0.831, 0.627, 1.000)   # #d4a0ff — kontur ciała
	var wg     := Color(0.600, 0.200, 1.000)   # #9933ff — glow/oczy
	var body   := Color(0.102, 0.000, 0.208)   # #1a0035 — wypełnienie ciała
	var hw     := Constants.PLAYER_W * 0.5     # = 11
	var hh     := Constants.PLAYER_H * 0.5     # = 22 (body -20 to +20 w HTML)

	# ── Tułów z zaokrąglonym prostokątem (HTML: roundRect(-11,-20,22,40,3)) ──
	draw_rect(Rect2(-hw, -hh, Constants.PLAYER_W, Constants.PLAYER_H), body)
	# Kontur świecący (HTML: strokeStyle=wc, shadowBlur=28)
	draw_polyline(PackedVector2Array([
		Vector2(-hw, -hh), Vector2(hw, -hh),
		Vector2(hw,  hh),  Vector2(-hw, hh),
		Vector2(-hw, -hh)
	]), wc, 1.8)

	# ── Korona (HTML: gold fillStyle, cy=-26) ────────────────────────────
	var gold := Color(0.988, 0.831, 0.302)   # C.gold
	# Uproszczona korona — trójkąt złoty nad głową
	draw_colored_polygon(PackedVector2Array([
		Vector2(-8, -hh - 6), Vector2(0, -hh - 14), Vector2(8, -hh - 6)
	]), gold)

	# ── Oko (HTML: fDir*5, -9, 2.5) ─────────────────────────────────────
	draw_circle(Vector2(facing_dir * 5, -9), 3.0, wg)

	# ── Nogi usunięte — oryginał JS nie ma nóg (canvas drawPlayer()) ────

	# ── Broń (wizualizacja podczas ataku) ────────────────────────
	if is_attacking:
		var sweep : float = 1.0 - attack_timer / ATTACK_DURATION
		var ax    : float = facing_dir * (hw + 10.0)
		var weap_d = HeroData.equipment.get("weapon", null)
		var rtype : String = weap_d.get("range_type", "short") if weap_d else "short"
		if rtype == "medium":
			# Włócznia — dłuższa
			draw_line(Vector2(ax, 14), Vector2(ax, -30 + sweep * 35), wc, 2.0)
			draw_line(Vector2(ax - 3, -30 + sweep*35), Vector2(ax, -38 + sweep*35), Color(0.95,0.85,0.40), 2.0)
		else:
			# Miecz (default)
			draw_line(Vector2(ax, 10), Vector2(ax, -22 + sweep * 30), wc, 2.5)
			draw_line(Vector2(ax - 4, -4 + sweep * 15), Vector2(ax + 4, -4 + sweep * 15), Color(1,1,1,0.5), 1.5)

	# ── HP & Stamina bars (HTML: translate(0,-42)) ───────────────────────
	var bar_top : float = -hh - 22.0   # odpowiednik translate(0,-42) w HTML
	var bw      : float = 40.0         # HTML: fillRect(-20, *, 40, *)
	# HP bar (HTML: #ef4444 czerwony, zawsze czerwony)
	var hp_pct  : float = clamp(float(HeroData.hp) / float(HeroData.max_hp), 0.0, 1.0)
	draw_rect(Rect2(-bw*0.5, bar_top, bw, 5),           Color(0, 0, 0, 0.60))
	draw_rect(Rect2(-bw*0.5, bar_top, bw * hp_pct, 5),  Color(0.937, 0.267, 0.267))  # #ef4444
	# Glass highlight
	draw_rect(Rect2(-bw*0.5, bar_top, bw * hp_pct, 2),  Color(1, 1, 1, 0.15))

	# Stamina bar (HTML: #4ade80 zielony)
	var sta_pct : float = clamp(HeroData.stamina / HeroData.max_stamina, 0.0, 1.0)
	var sta_y   : float = bar_top + 7.0
	draw_rect(Rect2(-bw*0.5, sta_y, bw, 5),             Color(0, 0, 0, 0.60))
	draw_rect(Rect2(-bw*0.5, sta_y, bw * sta_pct, 5),   Color(0.290, 0.871, 0.502))  # #4ade80
	draw_rect(Rect2(-bw*0.5, sta_y, bw * sta_pct, 2),   Color(1, 1, 1, 0.15))

	# ── Hitbox ataku (jak drawAttackHitbox w JS engine.js) ───────────────
	if is_attacking and not HeroData.dead:
		var weap_d2 = HeroData.equipment.get("weapon", null)
		var rtype2 : String = weap_d2.get("range_type", "short") if weap_d2 else "short"
		if rtype2 != "ranged":
			var aw2 : float = 80.0 if rtype2 == "medium" else 52.0
			var ah2 : float = 36.0
			var t_ms2 : float = Time.get_ticks_msec() * 0.001
			var alpha2 : float = 0.35 + 0.2 * sin(t_ms2 * 5.0)
			# hitbox relative to hero position — facing_dir = 1 right, -1 left
			var hx : float = facing_dir * (hw + aw2 * 0.5)
			var rect2 := Rect2(hx - aw2 * 0.5, -ah2 * 0.5, aw2, ah2)
			draw_rect(rect2, Color(0.753, 0.518, 0.988, alpha2 * 0.12))
			draw_rect(rect2, Color(0.753, 0.518, 0.988, alpha2), false, 2.0)

	# ── Ikona braku staminy (JS: Hero.stamina <= 0 → pulsujące serce) ───
	if HeroData.stamina <= 0:
		var t_ms : float = Time.get_ticks_msec() * 0.001
		var pulse : float = 1.0 + 0.15 * sin(t_ms * 12.0)
		var ico_y : float = -hh - 36.0   # nad paskami HP/Stamina
		# Pulsujące czerwone błyskawice (2 elipsy + prostokąt jak w JS)
		var red := Color(0.937, 0.267, 0.267, 1.0)
		draw_set_transform(Vector2(0.0, ico_y), 0.0, Vector2(pulse, pulse))
		# Lewe "serce"
		draw_circle(Vector2(-5, 0), 4.5,  red)
		# Prawe "serce"
		draw_circle(Vector2(5, 0),  4.5,  red)
		# Łącznik górny (prostokąt jak ctx.fillRect(-1.5,-8,3,6) w JS)
		draw_rect(Rect2(-1.5, -8, 3, 6), red)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _on_died() -> void:
	GameManager.notify("💀 You have died!", Color.RED)
