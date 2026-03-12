## scripts/MobileControls.gd
## Wirtualne sterowanie mobilne — joystick + przyciski akcji
## Attach do węzła MobileControls (CanvasLayer) w scenie Main.tscn
## Automatycznie ukrywa się na PC

extends CanvasLayer

# ── Węzły ─────────────────────────────────────
@onready var joystick_base  : Control    = $Joystick/JoystickBase
@onready var joystick_knob  : Control    = $Joystick/JoystickKnob
@onready var joystick_root  : Control    = $Joystick
@onready var jump_btn       : Button     = $JumpBtn
@onready var attack_btn     : Button     = $AttackBtn
@onready var interact_btn   : Button     = $InteractBtn
@onready var shoot_btn      : Button     = $ShootBtn

# ── Stan joysticka ─────────────────────────────
var _joy_touch_idx  : int     = -1
var _joy_origin     : Vector2 = Vector2.ZERO
const JOY_RADIUS    := 60.0

# ── Referencja do Hero ─────────────────────────
var _hero : Node = null

func _ready() -> void:
	# Ukryj na platformach desktop
	if not _is_mobile():
		visible = false
		return

	_setup_layout()

	# Przyciski akcji
	jump_btn.pressed.connect(func(): if _hero: _hero.mobile_jump = true)
	attack_btn.pressed.connect(func(): if _hero: _hero.mobile_attack = true)
	interact_btn.pressed.connect(func(): if _hero: _hero.mobile_interact = true)
	shoot_btn.pressed.connect(func(): if _hero: _hero.mobile_shoot = true)

func set_hero(hero_node: Node) -> void:
	_hero = hero_node

func _is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")

# ── Układ przycisków ──────────────────────────
func _setup_layout() -> void:
	var vp := get_viewport().get_visible_rect().size

	# Joystick — lewy dolny róg
	if joystick_root:
		joystick_root.position = Vector2(60, vp.y - 140)
		joystick_root.size     = Vector2(120, 120)
	if joystick_base:
		joystick_base.position = Vector2(0, 0)
		joystick_base.size     = Vector2(120, 120)
		joystick_base.modulate = Color(1, 1, 1, 0.4)
	if joystick_knob:
		joystick_knob.position = Vector2(30, 30)
		joystick_knob.size     = Vector2(60, 60)
		joystick_knob.modulate = Color(1, 1, 1, 0.6)

	# Przyciski — prawy dolny róg
	var btn_size := Vector2(80, 80)
	var btn_y    := vp.y - 100.0
	if jump_btn:
		jump_btn.position = Vector2(vp.x - 100, btn_y - 90)
		jump_btn.size     = btn_size
		_style_btn(jump_btn, Color(0.29, 0.87, 0.50))
	if attack_btn:
		attack_btn.position = Vector2(vp.x - 190, btn_y)
		attack_btn.size     = btn_size
		_style_btn(attack_btn, Color(0.93, 0.27, 0.27))
	if interact_btn:
		interact_btn.position = Vector2(vp.x - 290, btn_y)
		interact_btn.size     = btn_size
		_style_btn(interact_btn, Color(0.51, 0.55, 0.97))
	if shoot_btn:
		shoot_btn.position = Vector2(vp.x - 100, btn_y)
		shoot_btn.size     = btn_size
		_style_btn(shoot_btn, Color(0.96, 0.62, 0.04))

func _style_btn(btn: Button, color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color        = Color(color.r, color.g, color.b, 0.5)
	style.border_color    = color
	style.border_width_bottom = 2
	style.border_width_top    = 2
	style.border_width_left   = 2
	style.border_width_right  = 2
	style.corner_radius_top_left     = 40
	style.corner_radius_top_right    = 40
	style.corner_radius_bottom_left  = 40
	style.corner_radius_bottom_right = 40
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_font_size_override("font_size", 22)

# ── Obsługa dotyku dla joysticka ──────────────
func _input(event: InputEvent) -> void:
	if not visible: return

	if event is InputEventScreenTouch:
		if event.pressed:
			var joy_global := _get_joystick_global_rect()
			if joy_global.has_point(event.position):
				_joy_touch_idx = event.index
				_joy_origin    = event.position
		elif event.index == _joy_touch_idx:
			_joy_touch_idx = -1
			_joy_origin    = Vector2.ZERO
			if joystick_knob: joystick_knob.position = Vector2(30, 30)
			if _hero: _hero.mobile_move_x = 0.0

	elif event is InputEventScreenDrag:
		if event.index == _joy_touch_idx:
			var drag_event: InputEventScreenDrag = event as InputEventScreenDrag
			var delta: Vector2 = drag_event.position - _joy_origin
			var clamped: Vector2 = delta.limit_length(JOY_RADIUS)
			if joystick_knob:
				joystick_knob.position = Vector2(30, 30) + clamped
			var move_x: float = clamped.x / JOY_RADIUS
			if _hero: _hero.mobile_move_x = move_x

			# Skok przez szybki ruch joysticka w górę
			if delta.y < -JOY_RADIUS * 0.7 and _hero:
				_hero.mobile_jump = true

func _get_joystick_global_rect() -> Rect2:
	if not joystick_root: return Rect2()
	return Rect2(joystick_root.global_position, joystick_root.size * 1.5)
