## scripts/Enemy.gd
## Skrypt wroga — CharacterBody2D
## Tworzony dynamicznie przez World.gd (scene_name: "Enemy")
## Węzeł: CharacterBody2D + CollisionShape2D (CapsuleShape2D 12×20)

extends CharacterBody2D

# ── Sygnały ─────────────────────────────────────
signal float_text_requested(text: String, color: Color, x: float, y: float)
signal enemy_killed(x: float, y: float)

# ── Konfiguracja (ustawiana przy spawn) ────────
var hp           : int   = 40
var max_hp       : int   = 40
var speed        : float = Constants.ENEMY_SPEED
var biome        : String = "kingdom"
var dmg_mult     : float = 1.0
var speed_mult   : float = 1.0
var origin_portal_x : float = 2800.0
var is_cave      : bool  = false  # true = enemy z dungeonu

# ── AI ─────────────────────────────────────────
var current_target     = null   # {type, node_or_dict, x}
var target_timer       : float = 0.0
var attack_timer       : float = 0.0
var hit_flash          : float = 0.0
var dead               : bool  = false

const GRAVITY          := Constants.GRAVITY
const ATTACK_RANGE     := 45.0
const MELEE_DMG_BASE   := 20

func _ready() -> void:
	add_to_group("enemies")

func _physics_process(delta: float) -> void:
	if dead: return

	# Grawitacja
	if not is_on_floor():
		velocity.y += GRAVITY * delta
		velocity.y  = min(velocity.y, 1200.0)

	# Odliczanie hit flash i timera
	if hit_flash > 0.0: hit_flash = max(0.0, hit_flash - delta * 60.0)
	attack_timer = max(0.0, attack_timer - delta)

	# Znajdź cel
	target_timer -= delta
	if target_timer <= 0.0 or _is_target_dead():
		_find_target()
		target_timer = 1.0 + randf() * 2.0

	# Porusz się / zaatakuj
	if current_target:
		var tx : float = _get_target_x()
		var dist: float = abs(position.x - tx)
		var dir: float = sign(tx - position.x)

		if dist <= ATTACK_RANGE:
			velocity.x = 0.0
			if attack_timer <= 0.0:
				_perform_attack()
		else:
			velocity.x = dir * speed * speed_mult
			# Mały "hop" gdy ugrzęzną
			if randf() < 0.005 and abs(velocity.y) < 5.0:
				velocity.y = -160.0

	# Zabezpieczenie przed wypadnięciem
	if position.y > Constants.GROUND_Y + 400:
		position = Vector2(origin_portal_x, Constants.GROUND_Y - Constants.ENEMY_H * 0.5)
		velocity  = Vector2.ZERO

	move_and_slide()
	queue_redraw()

# ── Znajdź najbliższy cel ──────────────────────
func _find_target() -> void:
	var best_dist: float = INF
	current_target = null

	var world := get_parent().get_parent() if get_parent() else null
	if not world: return

	# Bohater
	var hero: Node2D = world.get_node_or_null("Hero") as Node2D
	if hero and not HeroData.dead:
		var d: float = abs(position.x - hero.position.x)
		if d < best_dist:
			best_dist = d
			current_target = {"type": "hero", "ref": hero}

	# Łucznicy
	var allies: Node = world.get_node_or_null("Allies")
	if allies:
		for a in allies.get_children():
			if a.is_in_group("archers") and a.hp > 0:
				var d: float = abs(position.x - (a as Node2D).position.x)
				if d < best_dist:
					best_dist = d
					current_target = {"type": "archer", "ref": a}
			elif a.is_in_group("warriors") and a.hp > 0:
				var d: float = abs(position.x - (a as Node2D).position.x)
				if d < best_dist:
					best_dist = d
					current_target = {"type": "warrior", "ref": a}

	# Mury
	for b in GameManager.buildings:
		if b["type"] == "wall" and b.get("built", false) and b.get("stage", 0) > 0:
			var d: float = abs(position.x - (b["x"] as float))
			if d < best_dist:
				best_dist = d
				current_target = {"type": "wall", "data": b}

	# Town Center (ostatnia deska)
	var tc := GameManager.get_building("town_center")
	if not tc.is_empty():
		var d: float = abs(position.x - (tc["x"] as float))
		if d < best_dist:
			current_target = {"type": "tc", "data": tc}

func _is_target_dead() -> bool:
	if current_target == null: return true
	match current_target["type"]:
		"hero":    return HeroData.dead
		"archer":  return current_target["ref"].hp <= 0
		"warrior": return current_target["ref"].hp <= 0
		"wall":    return not current_target["data"].get("built", false)
		"tc":      return current_target["data"].get("hp", 1) <= 0
	return false

func _get_target_x() -> float:
	if current_target == null: return 0.0
	match current_target["type"]:
		"hero":    return current_target["ref"].position.x
		"archer":  return current_target["ref"].position.x
		"warrior": return current_target["ref"].position.x
		"wall":    return current_target["data"]["x"]
		"tc":      return current_target["data"]["x"]
	return 0.0

func _perform_attack() -> void:
	var dmg: int = int(MELEE_DMG_BASE * dmg_mult)
	match current_target["type"]:
		"hero":
			attack_timer = 0.75
			HeroData.take_damage(dmg)
			var actual_dmg: int = max(1, dmg - HeroData.defense)
			float_text_requested.emit("-%d HP" % actual_dmg, Color(1.0, 0.13, 0.13), position.x, position.y - 30.0)
		"archer":
			attack_timer = 0.65
			current_target["ref"].take_damage(dmg)
			float_text_requested.emit("-%d" % dmg, Color(1.0, 0.13, 0.13), current_target["ref"].position.x, current_target["ref"].position.y - 30.0)
		"warrior":
			attack_timer = 0.65
			current_target["ref"].take_damage(dmg)
			float_text_requested.emit("-%d" % dmg, Color(1.0, 0.13, 0.13), current_target["ref"].position.x, current_target["ref"].position.y - 30.0)
		"wall":
			attack_timer = 1.0
			var wall_side := "West" if current_target["data"].get("id","") == "left_wall" else "East"
			GameManager.notify("🛡️ %s Wall is under attack!" % wall_side, Color(0.93, 0.27, 0.27))
			float_text_requested.emit("-%d" % dmg, Color(1.0, 0.13, 0.13), current_target["data"]["x"], Constants.GROUND_Y - 100.0)
			_damage_wall(current_target["data"], dmg)
		"tc":
			attack_timer = 1.0
			float_text_requested.emit("-%d" % dmg, Color(1.0, 0.13, 0.13), current_target["data"]["x"], Constants.GROUND_Y - 180.0)
			_damage_tc(current_target["data"], int(dmg))

func _damage_wall(b: Dictionary, dmg: int) -> void:
	b["hp"] -= dmg
	if b["hp"] <= 0:
		if b.get("stage", 1) > 1:
			b["stage"] -= 1
			b["hp"]     = [0, 100, 200, 300][b["stage"]]
			b["max_hp"] = b["hp"]
			GameManager.notify("⚠️ %s downgraded!" % b["name"], Color(0.98, 0.57, 0.09))
			_free_excess_archers_from_wall(b)
		else:
			b["built"] = false
			b["stage"] = 0
			current_target = null
			GameManager.notify("💥 %s destroyed!" % b["name"], Color.RED)
			_free_excess_archers_from_wall(b)
		# ── Debris particles ─────────────────────
		var world_node := get_parent().get_parent() if get_parent() else null
		if world_node and world_node.has_method("_spawn_debris"):
			var bc : Color = b.get("color", Color(0.3,0.3,0.3))
			var bww : float = b.get("w", 40.0)
			for _di in range(5):
				var dx : float = float(b["x"]) + (randf() - 0.5) * bww
				var dy : float = Constants.GROUND_Y - float(b.get("h", 60.0)) * randf()
				world_node._spawn_debris(dx, dy, bc)
		# Sygnał do World żeby przebudował fizykę muru
		var world := get_parent().get_parent() if get_parent() else null
		if world and world.has_method("rebuild_wall_physics"):
			world.rebuild_wall_physics(b)

func _damage_tc(b: Dictionary, dmg: int) -> void:
	b["hp"] -= dmg
	if b["hp"] <= 0:
		if b.get("stage", 1) > 1:
			b["stage"]  -= 1
			b["max_hp"]  = [0, 1000, 2000, 3000][b["stage"]]
			b["hp"]      = min(b["hp"] + b["max_hp"], b["max_hp"])
			GameManager.notify("⚠️ Town Center downgraded!", Color(0.98, 0.57, 0.09))
		else:
			HeroData.dead = true
			HeroData.died.emit()

# ── Trafienie przez gracza ─────────────────────
func receive_hit(dmg: int, knockback: Vector2) -> void:
	if dead: return
	hp -= dmg
	hit_flash = 12.0
	velocity  += knockback
	if hp <= 0:
		die()

func die() -> void:
	dead = true
	remove_from_group("enemies")
	HeroData.gain_xp(35)
	GameManager.add_gold(5)
	enemy_killed.emit(position.x, position.y)
	# ── Kill float texts (+5G, +35 XP) ─────────────
	float_text_requested.emit("+5G", Color(1.0, 0.85, 0.0), position.x, position.y - 40.0)
	float_text_requested.emit("+35 XP", Color(0.49, 0.98, 0.32), position.x + 20.0, position.y - 55.0)
	# Usuń węzeł w następnej klatce
	call_deferred("queue_free")

# ── Zwolnij łuczników gdy mur zniszczony/degradowany ──────────
func _free_excess_archers_from_wall(b: Dictionary) -> void:
	var wall_id: String = b.get("id", "")
	if wall_id.is_empty(): return
	var stage: int = b.get("stage", 0)
	# Max archers per stage: 0=0, 1=2, 2=4, 3=8
	var max_archers: int = 0 if stage == 0 else (2 if stage == 1 else (4 if stage == 2 else 8))
	var world_node := get_parent().get_parent() if get_parent() else null
	if not world_node: return
	var allies: Node = world_node.get_node_or_null("Allies")
	if not allies: return
	var on_wall: Array = []
	for c in allies.get_children():
		if c.is_in_group("archers") and c.get("assigned_wall_id") == wall_id:
			on_wall.append(c)
	# Free excess archers (those beyond new max)
	for i in range(max_archers, on_wall.size()):
		on_wall[i].assigned_wall_id = ""

func _draw() -> void:
	var flash    := hit_flash > 0.0
	var body_col := Color.WHITE if flash else (Color(0.13, 0.0, 0.07) if not is_cave else Color(0.08, 0.0, 0.12))
	var eye_col  := Color(1.0, 0.13, 0.40) if not flash else Color.WHITE
	var half_w   := Constants.ENEMY_W * 0.5
	var half_h   := Constants.ENEMY_H * 0.5
	var t        := Time.get_ticks_msec() * 0.001

	# Aura (fake glow — większa i bardziej widoczna)
	var aura_col := Color(0.80, 0.0, 0.33, 0.18 + 0.08 * sin(t * 4.0 + position.x * 0.01))
	draw_circle(Vector2(0, 0), 22.0, aura_col)
	draw_rect(Rect2(-half_w - 3, -half_h - 3, Constants.ENEMY_W + 6, Constants.ENEMY_H + 6), aura_col)

	# Ciało
	draw_rect(Rect2(-half_w, -half_h, Constants.ENEMY_W, Constants.ENEMY_H), body_col)
	# Kontur (czerwona obwódka)
	if not flash:
		draw_polyline(PackedVector2Array([
			Vector2(-half_w, -half_h), Vector2(half_w, -half_h),
			Vector2(half_w, half_h),   Vector2(-half_w, half_h),
			Vector2(-half_w, -half_h)
		]), Color(1.0, 0.13, 0.40, 0.5), 1.0)

	# Oczy z poświatą
	var eye_glow := Color(eye_col.r, eye_col.g, eye_col.b, 0.35)
	draw_circle(Vector2(-5, -half_h + 10), 5.0, eye_glow)
	draw_circle(Vector2(5,  -half_h + 10), 5.0, eye_glow)
	draw_circle(Vector2(-5, -half_h + 10), 3, eye_col)
	draw_circle(Vector2(5,  -half_h + 10), 3, eye_col)

	# ── HP bar (zawsze widoczny) ───────────────
	var pct   : float = clamp(float(hp) / float(max_hp), 0.0, 1.0)
	var bar_w := 28.0
	# Tło
	draw_rect(Rect2(-14, -half_h - 10, bar_w, 5), Color(0, 0, 0, 0.75))
	# Wypełnienie
	var bar_color := Color(1.0, 0.13, 0.40) if pct > 0.5 else Color(1.0, 0.40, 0.0)
	draw_rect(Rect2(-14, -half_h - 10, bar_w * pct, 5), bar_color)
	# Obramowanie
	draw_polyline(PackedVector2Array([
		Vector2(-14, -half_h - 10), Vector2(14, -half_h - 10),
		Vector2(14, -half_h - 5),   Vector2(-14, -half_h - 5),
		Vector2(-14, -half_h - 10)
	]), Color(1, 1, 1, 0.15), 1.0)
