## scripts/DungeonScene.gd
## Loch — rendering jaskini i zarządzanie jej encjami
## Attach do węzła DungeonScene (Node2D) w scenie Main.tscn

extends Node2D

# ── Stan lochu ─────────────────────────────────
var enemies  : Array = []
var coins    : Array = []
var chests   : Array = []
var archers  : Array = []   # sojusznicy, którzy weszli do lochu
var warriors : Array = []

var spawn_timer    : float = 0.0
const SPAWN_INTERVAL := 5.0   # sekundy
const ENEMY_CAP      := 25
const EXIT_X         := 1200.0

# Stalaktyty i klejnoty — generowane raz
var _stalactites : Array = []
var _gems        : Array = []

# Referencje
var _hero : Node = null

# ── Assety graficzne ──────────────────────────
var _tex_rune_active : Texture2D = null   # RuneStoneAcive.png (nieotwarty)
var _tex_rune_open   : Texture2D = null   # RuneStone.png (użyty/otwarty)

func _ready_assets() -> void:
	if ResourceLoader.exists("res://assets/RuneStoneAcive.png"):
		_tex_rune_active = load("res://assets/RuneStoneAcive.png")
	if ResourceLoader.exists("res://assets/RuneStone.png"):
		_tex_rune_open = load("res://assets/RuneStone.png")

func _ready() -> void:
	visible = false
	_build_cave_decorations()
	_ready_assets()

# ── Generuj dekoracje jaskini ─────────────────
func _build_cave_decorations() -> void:
	for i in range(60):
		_stalactites.append({
			"x": fmod(i * 383.0, 3000.0) - 1500.0,
			"len": 40.0 + fmod(i * 57.0, 80.0),
			"w":   8.0  + fmod(i * 13.0, 18.0),
		})
	var gem_colors := [Color(0.51, 0.55, 0.97), Color(0.66, 0.33, 0.97), Color(0.13, 0.83, 0.93), Color(0.29, 0.87, 0.50)]
	for i in range(30):
		_gems.append({
			"x": fmod(i * 271.0, 3000.0) - 1500.0,
			"y": 50.0 + fmod(i * 43.0, 150.0),
			"r": 3.0  + fmod(i * 7.0,  5.0),
			"color": gem_colors[i % 4],
		})

# ── Wejście do lochu ──────────────────────────
func enter(hero: Node) -> void:
	_hero = hero
	visible = true
	generate()
	hero.position = Vector2(0.0, Constants.GROUND_Y - 30.0)
	hero.velocity = Vector2.ZERO
	GameManager.notify("🌀 Entering the Underworld...", Color(0.51, 0.55, 0.97))

func exit() -> void:
	visible = false
	clear()

# ── Generuj zawartość lochu ──────────────────
func generate() -> void:
	clear()

	# Monety (20 sztuk)
	for i in range(20):
		coins.append({
			"x":         (randf() - 0.5) * 2400.0,
			"y":         Constants.GROUND_Y - 15.0,
			"r":         7.0,
			"collected": false,
			"pulse":     randf() * TAU,
		})

	# Skrzynie (8–12)
	var chest_count := 8 + randi() % 5
	var chest_variants := [
		{"color": Color(0.29, 0.13, 0.0), "glow": Color(0.96, 0.62, 0.04), "name": "Bone Chest"},
		{"color": Color(0.10, 0.23, 0.0), "glow": Color(0.29, 0.87, 0.50), "name": "Mossy Chest"},
		{"color": Color(0.05, 0.0,  0.13),"glow": Color(0.66, 0.33, 0.97), "name": "Void Chest"},
	]
	for i in range(chest_count):
		var v: Dictionary = chest_variants[randi() % 3]
		chests.append({
			"x":      (randf() - 0.5) * 2600.0,
			"w":      40.0, "h": 30.0,
			"color":  v["color"],
			"glow":   v["glow"],
			"name":   v["name"],
			"opened": false,
		})

	# Wrogowie startowi (10–15)
	var init_count := 10 + randi() % 6
	for i in range(init_count):
		_spawn_cave_enemy()

	spawn_timer = 0.0

func _spawn_cave_enemy() -> void:
	if enemies.filter(func(e): return not e["dead"]).size() >= ENEMY_CAP: return
	var side  := 1 if randf() > 0.5 else -1
	var sx    := side * (300.0 + randf() * 900.0)
	var hp: int = int((60.0 + HeroData.level * 15.0) * (1.5 + randf()))
	enemies.append({
		"x": sx, "y": Constants.GROUND_Y - 20.0,
		"vx": 0.0, "vy": 0.0,
		"hp": hp, "max_hp": hp,
		"dead": false,
		"hit_flash": 0.0, "attack_timer": 0.0,
		"speed_mult": 0.8 + randf() * 0.4,
	})

# ── Update — wywoływane z World.gd _physics_process ─
func update(delta: float) -> void:
	if not visible: return

	spawn_timer += delta
	if spawn_timer >= SPAWN_INTERVAL:
		spawn_timer = 0.0
		_spawn_cave_enemy()
		_spawn_cave_enemy()

	if not _hero: return
	var px: float = (_hero as Node2D).position.x

	# Ruch wrogów
	for e in enemies:
		if e["dead"]: continue
		e["hit_flash"] = max(0.0, e["hit_flash"] - delta * 60.0)
		e["attack_timer"] = max(0.0, e["attack_timer"] - delta)

		var dir: float = sign(px - (e["x"] as float))
		var dist: float = abs((e["x"] as float) - px)

		if dist <= 42.0:
			e["vx"] = 0.0
			if e["attack_timer"] <= 0.0:
				e["attack_timer"] = 0.75
				var dmg: int = max(1, int(25.0 * 1.5 - HeroData.defense))
				HeroData.take_damage(dmg)
		else:
			e["vx"] = dir * Constants.ENEMY_SPEED * 1.5 * e["speed_mult"]
			if randf() < 0.005: e["vy"] = -200.0

		# Pseudo-gravitacja
		e["vy"] += Constants.GRAVITY * delta
		e["vy"]  = min(e["vy"], 800.0)
		e["y"]  += e["vy"] * delta
		if e["y"] >= Constants.GROUND_Y - 20.0:
			e["y"]  = Constants.GROUND_Y - 20.0
			e["vy"] = 0.0
		e["x"] += e["vx"] * delta

	# Zbieranie monet
	for i in range(coins.size() - 1, -1, -1):
		var c: Dictionary = coins[i]
		if c["collected"]: continue
		if Vector2(px, _hero.position.y).distance_to(Vector2(c["x"], c["y"])) < 40.0:
			c["collected"] = true
			GameManager.add_gold(10)
			var _wr := get_parent()
			if _wr and _wr.has_method("_spawn_float_text"):
				_wr._spawn_float_text("+10G", Color(1.0, 0.85, 0.0), c["x"], c["y"] - 20.0)

	# Usuń martwe
	enemies = enemies.filter(func(e): return not e["dead"])

	# AI łuczników w jaskini
	for a in archers:
		if a.get("hp", 0) <= 0: continue
		if a.get("cooldown", 0.0) > 0: a["cooldown"] -= delta * 60.0
		if a.get("draw_timer", 0.0) > 0: a["draw_timer"] -= delta * 60.0

		var target = null
		var min_dist := 800.0
		for e in enemies:
			if e["dead"]: continue
			var d: float = abs(float(e["x"]) - a.get("x", 0.0))
			if d < min_dist:
				min_dist = d; target = e

		if target and a.get("cooldown", 0.0) <= 0:
			a["cooldown"] = 70.0
			a["draw_timer"] = 15.0
			var dir: float = sign(float(target["x"]) - float(a["x"]))
			a["dir"] = dir
			var dmg: int = HeroData.damage
			target["hp"] -= dmg
			target["hit_flash"] = 10.0
			if target["hp"] <= 0:
				target["dead"] = true
				HeroData.gain_xp(20)
				coins.append({"x": target["x"], "y": Constants.GROUND_Y - 15.0,
					"r": 8.0, "collected": false, "pulse": 0.0})
		elif target == null:
			if a.get("hp", 0) < a.get("max_hp", 100):
				a["hp"] = min(a.get("max_hp", 100.0), a.get("hp", 0.0) + 0.1)
			var rp := GameManager.rally_point
			var target_x: float = float(rp.get("x", 0.0)) if not rp.is_empty() else 0.0
			var my_idx: int = archers.find(a)
			target_x += float(my_idx * 20 - archers.size() * 10)
			var diff: float = target_x - a.get("x", 0.0)
			if abs(diff) > 10:
				a["dir"] = sign(diff)
				a["x"] = a["x"] + sign(diff) * 1.5
				a["walk_cycle"] = a.get("walk_cycle", 0.0) + 0.15
			else:
				a["walk_cycle"] = 0.0

	# AI wojowników w jaskini
	for w in warriors:
		if w.get("hp", 0) <= 0: continue
		if w.get("attack_timer", 0.0) > 0: w["attack_timer"] -= delta * 60.0

		var target = null
		var min_dist := 300.0
		for e in enemies:
			if e["dead"]: continue
			var d: float = abs(float(e["x"]) - w.get("x", 0.0))
			if d < min_dist:
				min_dist = d; target = e

		if target:
			var dist: float = abs(float(target["x"]) - w.get("x", 0.0))
			var dir: float = sign(float(target["x"]) - float(w["x"]))
			w["dir"] = dir
			if dist <= 40.0:
				w["swinging"] = true
				if w.get("attack_timer", 0.0) <= 0:
					w["attack_timer"] = 50.0
					var dmg: int = HeroData.damage
					target["hp"] -= dmg
					target["hit_flash"] = 10.0
					if target["hp"] <= 0:
						target["dead"] = true
						HeroData.gain_xp(20)
						coins.append({"x": target["x"], "y": Constants.GROUND_Y - 15.0,
							"r": 8.0, "collected": false, "pulse": 0.0})
			else:
				w["swinging"] = false
				w["x"] = w["x"] + dir * 1.8
				w["walk_cycle"] = w.get("walk_cycle", 0.0) + 0.18
		else:
			w["swinging"] = false
			if w.get("hp", 0) < w.get("max_hp", 400):
				w["hp"] = min(w.get("max_hp", 400.0), w.get("hp", 0.0) + 0.08)
			var rp := GameManager.rally_point
			var target_x: float = float(rp.get("x", 0.0)) if not rp.is_empty() else 0.0
			var my_idx: int = warriors.find(w)
			target_x += float(my_idx * 22 - warriors.size() * 11)
			var diff: float = target_x - w.get("x", 0.0)
			if abs(diff) > 10:
				w["dir"] = sign(diff)
				w["x"] = w["x"] + sign(diff) * 1.8
				w["walk_cycle"] = w.get("walk_cycle", 0.0) + 0.18
			else:
				w["walk_cycle"] = 0.0

	# Interakcja ze skrzyniami
	if Input.is_action_just_pressed("interact"):
		# Sprawdź skrzynie
		if try_open_chest():
			pass  # Skrzynia otwarta

	# Wyjście z lochu
	if abs(px - EXIT_X) < 80.0 and Input.is_action_just_pressed("interact"):
		var world := get_parent()
		if world and world.has_method("exit_dungeon"):
			world.exit_dungeon()

	# Prompt dla pobliskich skrzyń / wyjścia
	var world_ref := get_parent()
	var hud := world_ref.get_node_or_null("HUD") if world_ref else null
	if hud and hud.has_method("show_build_prompt_text"):
		var showed_prompt := false
		# Sprawdź wyjście
		if abs(px - EXIT_X) < 100.0:
			hud.show_build_prompt_text("☀ Exit Dungeon", "SPACE to return to surface")
			showed_prompt = true
		else:
			# Sprawdź skrzynie
			for ch in chests:
				if abs(px - ch.get("x", 0.0)) < Constants.BUILD_RADIUS:
					if ch.get("opened", false):
						hud.show_build_prompt_text("📦 " + ch.get("name", "Chest"), "Empty...")
					else:
						hud.show_build_prompt_text("🎁 " + ch.get("name", "Chest"), "SPACE to open")
					showed_prompt = true
					break
		if not showed_prompt and hud.has_method("hide_build_prompt"):
			hud.hide_build_prompt()

	queue_redraw()

# ── Trafienie wroga przez gracza w lochu ───────
func hero_attack(hit_rect: Rect2, direction: float) -> void:
	for e in enemies:
		if e["dead"]: continue
		var e_rect := Rect2(e["x"] - 12, e["y"] - 20, 24, 40)
		if hit_rect.intersects(e_rect):
			e["hp"] -= HeroData.damage
			e["hit_flash"] = 12.0
			e["vx"] = direction * 180.0
			if e["hp"] <= 0:
				e["dead"] = true
				HeroData.gain_xp(35)
				coins.append({"x": e["x"], "y": Constants.GROUND_Y - 15.0,
					"r": 8.0, "collected": false, "pulse": 0.0})
			break  # tylko jeden wróg na atak

# ── Otwórz skrzynię ───────────────────────────
func try_open_chest() -> bool:
	if not _hero: return false
	var px: float = (_hero as Node2D).position.x
	for ch in chests:
		if ch["opened"]: continue
		if abs(px - ch["x"]) < Constants.BUILD_RADIUS:
			ch["opened"] = true
			ch["color"]  = Color(0.10, 0.06, 0.0)
			var gold := 20 + randi() % 31
			GameManager.add_gold(gold)
			var loot: Dictionary = Constants.LOOT_POOL[randi() % Constants.LOOT_POOL.size()].duplicate()
			HeroData.equipment[loot["slot"]] = loot
			HeroData.recalc_stats()
			GameManager.notify("💰 +%dG & 🎁 %s!" % [gold, loot["name"]], Color(0.99, 0.83, 0.30))
			_spawn_cave_enemy(); _spawn_cave_enemy()
			return true
	return false

func clear() -> void:
	enemies.clear(); coins.clear(); chests.clear()
	archers.clear(); warriors.clear()

# ── Rendering ──────────────────────────────────
func _draw() -> void:
	if not visible: return
	var t := Time.get_ticks_msec() * 0.001
	var cam_offset := 0.0
	if _hero: cam_offset = _hero.position.x

	_draw_cave_bg(t, cam_offset)
	_draw_coins(t)
	_draw_chests(t)
	_draw_cave_enemies()
	_draw_cave_archers(t)
	_draw_rally_flag(t)
	_draw_exit_portal(t)

func _draw_cave_bg(t: float, cam_x: float) -> void:
	var vp := get_viewport_rect()
	var W := vp.size.x; var H := vp.size.y

	# Tło
	draw_rect(Rect2(cam_x - W, 0, W * 3, H), Color(0.02, 0.0, 0.06))

	# Sufit jaskini (fale)
	var pts := PackedVector2Array()
	pts.append(Vector2(cam_x - W, 0))
	var step := 40.0
	var off   := cam_x * -0.3
	var x     := cam_x - W
	while x <= cam_x + W + 40:
		var y := 60.0 + 30.0 * sin(x * 0.006 + off * 0.006) + 20.0 * cos(x * 0.013)
		pts.append(Vector2(x, y))
		x += step
	pts.append(Vector2(cam_x + W, 0))
	draw_colored_polygon(pts, Color(0.04, 0.0, 0.09))

	# Stalaktyty
	for s in _stalactites:
		var sx: float = s["x"]  # world coords — kamera przesuwa widok
		if sx < cam_x - W - 40 or sx > cam_x + W + 40: continue
		var tip := 58.0 + 30.0 * sin(s["x"] * 0.006) + 20.0 * cos(s["x"] * 0.013)
		draw_colored_polygon([
			Vector2(sx - s["w"] * 0.5, tip),
			Vector2(sx, tip + s["len"]),
			Vector2(sx + s["w"] * 0.5, tip),
		], Color(0.10, 0.02, 0.21))

	# Klejnoty
	for g in _gems:
		var sx: float = g["x"]
		if sx < cam_x - W - 20 or sx > cam_x + W + 20: continue
		var pulse := 0.6 + 0.4 * sin(t * 1.0 + g["x"])
		var col := (g["color"] as Color)
		col.a    = pulse
		draw_circle(Vector2(sx, g["y"]), g["r"], col)

	# Podłoga
	draw_rect(Rect2(cam_x - W, Constants.GROUND_Y, W * 3, H), Color(0.03, 0.0, 0.06))
	draw_rect(Rect2(cam_x - W, Constants.GROUND_Y, W * 3, 12), Color(0.12, 0.0, 0.25))

func _draw_coins(_t: float) -> void:
	for c in coins:
		if c["collected"]: continue
		c["pulse"] = c["pulse"] + 0.06
		var sc  := 1.0 + 0.2 * sin(c["pulse"])
		var col := Color(1.0, 0.85, 0.0, 0.3)
		draw_circle(Vector2(c["x"], c["y"]), c["r"] * sc * 2.5, col)
		draw_circle(Vector2(c["x"], c["y"]), c["r"] * sc, Color(1.0, 0.85, 0.0))

func _draw_chests(t: float) -> void:
	for ch in chests:
		var cx: float  = ch["x"]
		var cw: float  = ch["w"]
		var chh: float = ch["h"]
		var sy: float  = Constants.GROUND_Y - chh
		var is_rune: bool = (ch.get("id","") == "chest5" or ch.get("id","") == "chest6")
		var is_open: bool = ch["opened"]

		if is_rune:
			# RuneStone — używaj tekstury jeśli dostępna
			var tex := _tex_rune_open if is_open else _tex_rune_active
			if tex:
				var tw: float = cw * 2.0
				var th: float = chh * 2.0
				if not is_open:
					var gc3 := Color(0.80, 0.0, 0.90, 0.4 + 0.2 * sin(t * 3.0 + cx))
					draw_rect(Rect2(cx - tw*0.5 - 6, sy - 6, tw + 12, th + 12), gc3)
				draw_texture_rect(tex, Rect2(cx - tw*0.5, Constants.GROUND_Y - th, tw, th), false)
				continue
			# Fallback jeśli brak tekstury
		# Zwykła skrzynia
		if not is_open:
			var pulse := 0.7 + 0.3 * sin(t * 3.0 + cx * 0.001)
			var gc4 := (ch["glow"] as Color); gc4.a = pulse
			draw_rect(Rect2(cx - cw*0.5 - 4, sy - 4, cw + 8, chh + 8), gc4)
		draw_rect(Rect2(cx - cw*0.5, sy, cw, chh), ch["color"] as Color)
		var lid_c: Color = ch["glow"] if not is_open else Color(0.06, 0.0, 0.0)
		draw_rect(Rect2(cx - cw*0.5, sy, cw, chh * 0.3), lid_c as Color)
		if not is_open:
			draw_circle(Vector2(cx, sy + chh * 0.6), 4, Color(0.99, 0.83, 0.30))

func _draw_cave_enemies() -> void:
	for e in enemies:
		if e["dead"]: continue
		var flash: bool = (e["hit_flash"] as float) > 0.0
		var body_col := Color.WHITE if flash else Color(0.13, 0.0, 0.07)
		var eye_col  := Color(1.0, 0.13, 0.40) if not flash else Color.WHITE
		var ex: float = e["x"]; var ey: float = e["y"]
		draw_rect(Rect2(ex - 16, ey - 24, 32, 48), Color(0.80, 0.0, 0.33, 0.25))
		draw_rect(Rect2(ex - 12, ey - 20, 24, 40), body_col)
		draw_circle(Vector2(ex - 5, ey - 10), 3, eye_col)
		draw_circle(Vector2(ex + 5, ey - 10), 3, eye_col)
		var pct : float = float(e["hp"]) / float(e["max_hp"])
		draw_rect(Rect2(ex - 14, ey - 28, 28, 5), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(ex - 14, ey - 28, 28.0 * pct, 5),
			Color(1.0, 0.13, 0.40) if pct > 0.5 else Color(1.0, 0.40, 0.0))

func _draw_rally_flag(t: float) -> void:
	if GameManager.rally_point.is_empty(): return
	if not GameManager.rally_point.get("in_dungeon", false): return
	var rx : float = GameManager.rally_point.get("x", 0.0)
	var ry := Constants.GROUND_Y
	draw_line(Vector2(rx - 2, ry), Vector2(rx - 2, ry - 60), Color(0.47, 0.22, 0.06), 4)
	var wave := sin(t * 5.0) * 5.0
	var flag_pts := PackedVector2Array([
		Vector2(rx + 2, ry - 60),
		Vector2(rx + 32 + wave, ry - 50),
		Vector2(rx + 2, ry - 40),
	])
	draw_colored_polygon(flag_pts, Color(0.93, 0.27, 0.27))
	draw_circle(Vector2(rx + 12 + wave * 0.3, ry - 50), 4, Color(0.98, 0.75, 0.15))

func _draw_exit_portal(t: float) -> void:
	var r   := 38.0 + 6.0 * sin(t * 3.0)
	var col := Color(0.99, 0.83, 0.30)
	draw_arc(Vector2(EXIT_X, Constants.GROUND_Y - 30.0), r, 0, TAU, 32, col, 3)
	draw_circle(Vector2(EXIT_X, Constants.GROUND_Y - 30.0), r * 0.6, Color(1.0, 0.85, 0.25, 0.10))
	draw_string(ThemeDB.fallback_font, Vector2(EXIT_X, Constants.GROUND_Y - 72),
		"EXIT — SPACE", HORIZONTAL_ALIGNMENT_CENTER, -1, 13, Color(1.0, 0.98, 0.78, 0.95))

func _draw_cave_archers(_t: float) -> void:
	var GY := Constants.GROUND_Y
	for a in archers:
		if a.get("hp", 0) <= 0: continue
		var ax: float = a.get("x", 0.0)
		var adir: int = a.get("dir", 1)
		var walk: float = a.get("walk_cycle", 0.0)
		var draw_t: float = a.get("draw_timer", 0.0)

		# Body
		draw_rect(Rect2(ax - 10, GY - 40, 20, 30), Color(0.12, 0.11, 0.30))
		# Head
		draw_circle(Vector2(ax, GY - 43), 9, Color(0.29, 0.87, 0.50))
		# Bow
		var bow_col := Color(0.71, 0.33, 0.04)
		if draw_t > 0:
			draw_arc(Vector2(ax + adir * 4, GY - 30), 12, -PI * 0.4, PI * 0.4, 12, bow_col, 2)
		else:
			draw_arc(Vector2(ax + adir * 8, GY - 30), 10, -PI * 0.5, PI * 0.5, 12, bow_col, 2)
		# Legs walk animation
		if abs(walk) > 0.01:
			var l1 := Vector2(ax - 4, GY - 10)
			var l2 := Vector2(ax + 4, GY - 10)
			draw_line(l1, l1 + Vector2(sin(walk) * 6, 9), Color(0.12, 0.11, 0.30), 3)
			draw_line(l2, l2 + Vector2(cos(walk) * 6, 9), Color(0.12, 0.11, 0.30), 3)
		# HP bar (only if damaged)
		var hp: float = a.get("hp", 0.0)
		var max_hp: float = a.get("max_hp", 1.0)
		if hp < max_hp:
			var pct := clampf(hp / max_hp, 0.0, 1.0)
			draw_rect(Rect2(ax - 12, GY - 53, 24, 4), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(ax - 12, GY - 53, 24 * pct, 4),
				Color(0.29, 0.87, 0.50) if pct > 0.5 else Color(0.93, 0.27, 0.27))

	for w in warriors:
		if w.get("hp", 0) <= 0: continue
		var wx: float = w.get("x", 0.0)
		var wdir: int = w.get("dir", 1)
		# Body
		draw_rect(Rect2(wx - 11, GY - 38, 22, 33), Color(0.39, 0.27, 0.09))
		# Head
		draw_circle(Vector2(wx, GY - 41), 9, Color(0.98, 0.64, 0.64))
		# Sword
		var sw_x := wx + wdir * 14
		draw_line(Vector2(sw_x, GY - 48), Vector2(sw_x, GY - 20), Color(0.87, 0.87, 0.95), 3)
		# HP bar
		var hp: float = w.get("hp", 0.0)
		var max_hp: float = w.get("max_hp", 1.0)
		if hp < max_hp:
			var pct := clampf(hp / max_hp, 0.0, 1.0)
			draw_rect(Rect2(wx - 12, GY - 53, 24, 4), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(wx - 12, GY - 53, 24 * pct, 4),
				Color(0.96, 0.62, 0.04) if pct > 0.5 else Color(0.93, 0.27, 0.27))
