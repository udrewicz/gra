## scripts/Warrior.gd
## Wojownik sojuszniczy — Node2D (ruch manualny)
## Tworzony dynamicznie przez World.gd

extends Node2D

# ── Stan ───────────────────────────────────────
var hp           : int   = 400
var max_hp       : int   = 400
var facing_dir   : int   = -1
var attack_timer : float = 0.0
var walk_cycle   : float = 0.0
var is_swinging  : bool  = false

var world_ref : Node = null

func _ready() -> void:
	add_to_group("warriors")
	position.y = Constants.GROUND_Y - 15.0

func setup(x_pos: float, dir: int, world: Node = null) -> void:
	position.x = x_pos
	facing_dir = dir
	world_ref  = world
	var lm     := GameManager.warrior_level
	max_hp     = int(400.0 * pow(1.1, max(0, lm - 1)))
	hp         = max_hp

func take_damage(dmg: int) -> void:
	hp -= dmg
	if hp <= 0:
		hp = 0
		GameManager.notify("💀 A Warrior has fallen!", Color(0.98, 0.57, 0.09))
		call_deferred("queue_free")

func _process(delta: float) -> void:
	if hp <= 0: return
	attack_timer = max(0.0, attack_timer - delta)

	var target := _find_nearest_enemy()

	if target:
		var dist: float = abs(target.position.x - position.x)
		facing_dir = int(sign(target.position.x - position.x))

		if dist <= 40.0:
			# Atakuj
			is_swinging = true
			walk_cycle  = 0.0
			if attack_timer <= 0.0:
				attack_timer = 0.83  # ~0.83s swing
				var dmg := HeroData.damage
				target.receive_hit(dmg, Vector2(facing_dir * 80, -60))
		else:
			# Idź do wroga
			is_swinging = false
			position.x += facing_dir * 108.0 * delta
			walk_cycle += delta * 8.0
	else:
		# Idle: idź do rally / środka, regeneruj HP
		is_swinging = false
		if hp < max_hp: hp = min(max_hp, hp + int(0.08 * delta * 60.0))
		_move_idle(delta)

	queue_redraw()

func _find_nearest_enemy() -> Node2D:
	if not world_ref: return null
	var enemies_node: Node = world_ref.get_node_or_null("Enemies")
	if not enemies_node: return null

	var best      : Node  = null
	var best_dist : float = 300.0  # zasięg detekcji

	for e in enemies_node.get_children():
		if not e.is_in_group("enemies"): continue
		var d: float = abs((e as Node2D).position.x - position.x)
		if d < best_dist:
			best_dist = d
			best = e
	return best

func _move_idle(delta: float) -> void:
	var target_x := 0.0
	var go_dungeon := false

	if not GameManager.rally_point.is_empty():
		if GameManager.rally_point.get("in_dungeon", false):
			target_x = -Constants.DUNGEON_PORTAL_LEFT if position.x < 0 else Constants.DUNGEON_PORTAL_RIGHT
			go_dungeon = true
		else:
			target_x = float(GameManager.rally_point.get("x", 0.0))

	# Rozsmaruj wojowników by nie stali w kupie
	if not go_dungeon and world_ref:
		var allies: Node = world_ref.get_node_or_null("Allies")
		if allies:
			var my_idx := 0
			var count  := 0
			for w in allies.get_children():
				if not w.is_in_group("warriors"): continue
				if w == self: my_idx = count
				count += 1
			target_x += float(my_idx * 22 - count * 11)

	var diff := target_x - position.x
	if abs(diff) > 10.0:
		facing_dir  = int(sign(diff))
		position.x += facing_dir * 108.0 * delta
		walk_cycle += delta * 8.0
		# Sprawdź wejście do lochu
		if go_dungeon:
			_try_enter_dungeon()
	else:
		walk_cycle = 0.0

func _try_enter_dungeon() -> bool:
	var portal_x := -Constants.DUNGEON_PORTAL_LEFT if position.x < 0 else Constants.DUNGEON_PORTAL_RIGHT
	if abs(position.x - portal_x) > 20.0: return false
	if world_ref and world_ref.has_method("ally_enter_dungeon"):
		world_ref.ally_enter_dungeon(self, "warrior")
		return true
	return false

# ── Rendering ──────────────────────────────────
func _draw() -> void:
	var body_y := -15.0

	# Nogi
	if walk_cycle > 0.0:
		var l1 : float = sin(walk_cycle) * 6.0
		var l2 : float = cos(walk_cycle) * 6.0
		draw_line(Vector2(-4, body_y + 15), Vector2(-4 + l1, body_y + 22), Color(0.27, 0.04, 0.04), 4)
		draw_line(Vector2( 4, body_y + 15), Vector2( 4 + l2, body_y + 22), Color(0.27, 0.04, 0.04), 4)

	# Tułów — zbroja
	draw_rect(Rect2(-12, body_y - 18, 24, 33), Color(0.27, 0.04, 0.04))
	draw_rect(Rect2(-11, body_y - 17, 22, 31), Color(0.45, 0.10, 0.10))

	# Głowa z hełmem
	draw_circle(Vector2(0, body_y - 21), 10, Color(0.94, 0.80, 0.40))
	draw_rect(Rect2(-11, body_y - 32, 22, 12), Color(0.50, 0.40, 0.20))

	# HP bar
	if hp < max_hp:
		var pct : float = float(hp) / float(max_hp)
		draw_rect(Rect2(-14, body_y - 36, 28, 4), Color(0, 0, 0, 0.6))
		var hc := Color(0.29, 0.87, 0.50) if pct > 0.5 else Color(0.93, 0.27, 0.27)
		draw_rect(Rect2(-14, body_y - 36, 28.0 * pct, 4), hc)

	# Miecz
	if is_swinging:
		var sx := facing_dir * 20.0
		draw_line(Vector2(sx, body_y - 5), Vector2(sx + facing_dir * 30.0, body_y - 25), Color(0.80, 0.80, 1.0), 4)
	else:
		var sx := facing_dir * 14.0
		draw_line(Vector2(sx, body_y), Vector2(sx, body_y - 22), Color(0.70, 0.70, 0.90), 3)
