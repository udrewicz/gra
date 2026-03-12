## scripts/Archer.gd
## Łucznik sojuszniczy — Node2D (bez fizyki, porusza się manualnie)
## Tworzony dynamicznie przez World.gd

extends Node2D

# ── Stan ───────────────────────────────────────
var hp               : int   = 100
var max_hp           : int   = 100
var facing_dir       : int   = -1
var assigned_wall_id : String = ""
var cooldown         : float = 0.0
var draw_timer       : float = 0.0
var walk_cycle       : float = 0.0

# Referencja do World do pobierania wrogów
var world_ref : Node = null

# ── Sygnały ────────────────────────────────────
signal arrow_fired(from_pos: Vector2, vel: Vector2)

func _ready() -> void:
	add_to_group("archers")
	position.y = Constants.GROUND_Y - 15.0

func setup(x_pos: float, dir: int, wall_id: String = "", world: Node = null) -> void:
	position.x    = x_pos
	facing_dir    = dir
	assigned_wall_id = wall_id
	world_ref     = world
	var lm        := GameManager.archer_level
	max_hp        = int(100.0 * pow(1.1, max(0, lm - 1)))
	hp            = max_hp

func take_damage(dmg: int) -> void:
	hp -= dmg
	if hp <= 0:
		hp = 0
		GameManager.notify("💀 An Archer has fallen!", Color.RED)
		call_deferred("queue_free")

func _process(delta: float) -> void:
	if hp <= 0: return
	cooldown  = max(0.0, cooldown  - delta)
	draw_timer = max(0.0, draw_timer - delta)

	# Wyszukaj cel w zasięgu 800px
	var target := _find_enemy_target()

	if target and cooldown <= 0.0:
		_shoot_at(target)
	elif not target:
		# Idle regen
		hp = min(max_hp, hp + int(0.1 * delta * 60.0))
		_move_to_position(delta)

	queue_redraw()

func _find_enemy_target() -> Node2D:
	if not world_ref: return null
	var enemies_node: Node = world_ref.get_node_or_null("Enemies")
	if not enemies_node: return null

	var best     : Node  = null
	var best_dist : float = 800.0

	for e in enemies_node.get_children():
		if not e.is_in_group("enemies"): continue
		var d: float = abs((e as Node2D).position.x - position.x)
		if d < best_dist:
			best_dist = d
			best = e
	return best

func _shoot_at(target: Node2D) -> void:
	cooldown    = 1.15
	draw_timer  = 0.25
	facing_dir  = int(sign(target.position.x - position.x))

	var start    := Vector2(position.x + facing_dir * 10.0, position.y - 15.0)
	var tx: float = target.position.x
	var ty: float = target.position.y
	var dist: float = abs(tx - position.x)

	var vx : float
	var vy : float
	if dist < 60.0:
		vx = facing_dir * 120.0
		vy = 80.0 + (ty - start.y) * 0.15
	else:
		var t_hit: float = max(0.016, dist / 420.0)
		vx = (tx + target.velocity.x * t_hit - start.x) / t_hit
		vy = (ty - start.y - 0.5 * Constants.GRAVITY * t_hit * t_hit) / t_hit
		vy = clamp(vy, -480.0, 360.0)

	arrow_fired.emit(start, Vector2(vx, vy))

func _move_to_position(delta: float) -> void:
	var target_x := _get_idle_target_x()
	var diff     := target_x - position.x

	if abs(diff) > 10.0:
		facing_dir  = int(sign(diff))
		position.x += facing_dir * 90.0 * delta
		walk_cycle += delta * 8.0
		# Sprawdź wejście do lochu gdy zmierzamy do portalu
		if not GameManager.rally_point.is_empty() and GameManager.rally_point.get("in_dungeon", false):
			_try_enter_dungeon()
	else:
		walk_cycle   = 0.0
		facing_dir   = -1 if assigned_wall_id == "left_wall" else 1

func _get_idle_target_x() -> float:
	# 1. Przypisany mur
	if assigned_wall_id != "":
		var wall := GameManager.get_building(assigned_wall_id)
		if not wall.is_empty() and wall.get("built", false):
			var slot_idx := 0
			if world_ref:
				var allies: Node = world_ref.get_node_or_null("Allies")
				if allies:
					var idx := 0
					for a in allies.get_children():
						if a.is_in_group("archers") and a.assigned_wall_id == assigned_wall_id:
							if a == self: slot_idx = idx
							idx += 1
			var side   := 1 if slot_idx % 2 == 0 else -1
			var offset: float = 10.0 + (slot_idx >> 1) * 12.0
			return wall["x"] + (side * offset if assigned_wall_id == "left_wall" else -side * offset)
		else:
			assigned_wall_id = ""  # mur zniszczony

	# 2. Rally point — z obsługą wejścia do lochu
	if not GameManager.rally_point.is_empty():
		if GameManager.rally_point.get("in_dungeon", false):
			# Idź do najbliższego portalu lochu (±8000)
			return -Constants.DUNGEON_PORTAL_LEFT if position.x < 0 else Constants.DUNGEON_PORTAL_RIGHT
		return float(GameManager.rally_point.get("x", 0.0))

	# 3. Środek
	return 0.0

func _try_enter_dungeon() -> bool:
	# Sprawdź czy łucznik dotarł do portalu lochu
	var portal_x := -Constants.DUNGEON_PORTAL_LEFT if position.x < 0 else Constants.DUNGEON_PORTAL_RIGHT
	if abs(position.x - portal_x) > 20.0: return false
	# Przenieś do lochu
	if world_ref and world_ref.has_method("ally_enter_dungeon"):
		world_ref.ally_enter_dungeon(self, "archer")
		return true
	return false

# ── Rendering ──────────────────────────────────
func _draw() -> void:
	var body_y := -15.0   # względem position (stopy na ziemi)

	# Nogi (animacja chodu)
	if walk_cycle > 0.0:
		var l1 : float = sin(walk_cycle) * 6.0
		var l2 : float = cos(walk_cycle) * 6.0
		draw_line(Vector2(-4, body_y + 15), Vector2(-4 + l1, body_y + 22), Color(0.12, 0.11, 0.29), 4)
		draw_line(Vector2( 4, body_y + 15), Vector2( 4 + l2, body_y + 22), Color(0.12, 0.11, 0.29), 4)

	# Tułów
	draw_rect(Rect2(-10, body_y - 15, 20, 30), Color(0.12, 0.11, 0.29))

	# HP bar (tylko gdy ranny)
	if hp < max_hp:
		var pct  : float = float(hp) / float(max_hp)
		var by2  := body_y - 28.0
		draw_rect(Rect2(-12, by2, 24, 4), Color(0, 0, 0, 0.6))
		var hc := Color(0.29, 0.87, 0.50) if pct > 0.5 else Color(0.93, 0.27, 0.27)
		draw_rect(Rect2(-12, by2, 24.0 * pct, 4), hc)

	# Głowa
	draw_circle(Vector2(0, body_y - 18), 10, Color(0.29, 0.87, 0.50))

	# Łuk
	if draw_timer > 0.0:
		draw_arc(Vector2(facing_dir * 4, body_y - 5), 12, -PI / 2.5, PI / 2.5, 12, Color(0.70, 0.33, 0.04), 2)
	else:
		draw_arc(Vector2(facing_dir * 8, body_y - 5), 10, -PI / 2, PI / 2, 12, Color(0.70, 0.33, 0.04), 2)
