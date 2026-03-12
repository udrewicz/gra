## scripts/MainMenu.gd
## Menu główne — styl "The Crown of The Abyss"
## Animowane tło z kryształami + gwiazdy jak na screenshocie
extends Control

@onready var new_game_btn  : Button            = $Panel/VBox/NewGameBtn
@onready var load_game_btn : Button            = $Panel/VBox/LoadGameBtn
@onready var title_label   : Label             = $Panel/VBox/Title
@onready var subtitle_label: Label             = $Panel/VBox/Subtitle
@onready var video_player  : VideoStreamPlayer = $VideoPlayer

var _t : float = 0.0

func _ready() -> void:
	GameManager.is_running = false
	load_game_btn.disabled = not SaveSystem.has_save()
	new_game_btn.pressed.connect(_on_new_game)
	load_game_btn.pressed.connect(_on_load_game)
	_load_video()
	_animate_title()

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var vp := get_viewport_rect()
	var W  := vp.size.x
	var H  := vp.size.y
	_draw_bg_crystals(W, H)
	_draw_stars_bg(W, H)

func _draw_bg_crystals(W: float, H: float) -> void:
	# Kryształy — identyczne w wyglądzie jak na screenshocie 2
	var crystals := [
		# {cx, cy, size, angle, col_a, col_b}
		{"cx": W*0.08,  "cy": H*0.75, "size": 110.0, "angle": -0.25, "alpha": 0.55},
		{"cx": W*0.14,  "cy": H*0.55, "size":  80.0, "angle":  0.15, "alpha": 0.45},
		{"cx": W*0.05,  "cy": H*0.88, "size":  70.0, "angle": -0.40, "alpha": 0.35},
		{"cx": W*0.92,  "cy": H*0.72, "size": 120.0, "angle":  0.30, "alpha": 0.55},
		{"cx": W*0.85,  "cy": H*0.55, "size":  75.0, "angle": -0.20, "alpha": 0.42},
		{"cx": W*0.97,  "cy": H*0.85, "size":  65.0, "angle":  0.45, "alpha": 0.38},
		{"cx": W*0.50,  "cy": H*0.05, "size":  55.0, "angle":  0.05, "alpha": 0.28},
		{"cx": W*0.25,  "cy": H*0.10, "size":  45.0, "angle": -0.10, "alpha": 0.22},
		{"cx": W*0.75,  "cy": H*0.08, "size":  50.0, "angle":  0.20, "alpha": 0.25},
	]
	for cr in crystals:
		var cx  : float = cr["cx"]
		var cy  : float = cr["cy"]
		var sz  : float = cr["size"]
		var ang : float = cr["angle"] + sin(_t * 0.18 + cx * 0.01) * 0.04
		var a   : float = cr["alpha"]
		# Delikatne pulsowanie
		sz *= 1.0 + 0.03 * sin(_t * 0.7 + cx * 0.02)

		# Kryształowy wielokąt (sześciokąt-diament)
		var crystal_pts := PackedVector2Array([
			Vector2(cx,          cy - sz),
			Vector2(cx + sz*0.3, cy - sz*0.35),
			Vector2(cx + sz*0.45,cy + sz*0.15),
			Vector2(cx + sz*0.18,cy + sz),
			Vector2(cx,          cy + sz*0.75),
			Vector2(cx - sz*0.18,cy + sz),
			Vector2(cx - sz*0.45,cy + sz*0.15),
			Vector2(cx - sz*0.3, cy - sz*0.35),
		])
		# Obróć
		for i in range(crystal_pts.size()):
			var p  := crystal_pts[i] - Vector2(cx, cy)
			var rx := p.x * cos(ang) - p.y * sin(ang)
			var ry := p.x * sin(ang) + p.y * cos(ang)
			crystal_pts[i] = Vector2(cx + rx, cy + ry)

		# Ciemna sylwetka + poświata krawędzi
		draw_colored_polygon(crystal_pts, Color(0.10, 0.04, 0.22, a * 0.85))
		draw_polyline(crystal_pts, Color(0.55, 0.20, 0.95, a * 0.70), 1.5, true)
		# Wewnętrzny highlight (jasna linia w górnej połowie)
		if crystal_pts.size() >= 3:
			draw_line(crystal_pts[0], crystal_pts[1],
				Color(0.75, 0.50, 1.0, a * 0.45), 1.0)
			draw_line(crystal_pts[0], crystal_pts[7],
				Color(0.75, 0.50, 1.0, a * 0.45), 1.0)

func _draw_stars_bg(W: float, H: float) -> void:
	var rng := RandomNumberGenerator.new()
	for i in range(60):
		rng.seed = i * 1777 + 99
		var sx := rng.randf() * W
		var sy := rng.randf() * H * 0.55
		var twinkle := 0.4 + 0.6 * sin(_t * 1.5 + float(i) * 1.1)
		var r  := 0.5 + rng.randf() * 1.2
		draw_circle(Vector2(sx, sy), r * 2.5, Color(1, 1, 1, twinkle * 0.06))
		draw_circle(Vector2(sx, sy), r,       Color(1, 1, 1, twinkle * 0.70))

func _load_video() -> void:
	if not video_player: return
	var stream := load("res://assets/Menu.mp4") if ResourceLoader.exists("res://assets/Menu.mp4") else null
	if stream:
		video_player.stream = stream
		video_player.play()
	else:
		video_player.visible = false

func _animate_title() -> void:
	var tween := create_tween().set_loops()
	tween.tween_property(title_label, "modulate", Color(1.0, 1.0, 1.0, 1.0), 1.8)
	tween.tween_property(title_label, "modulate", Color(0.88, 0.82, 1.0, 1.0), 1.8)
	var tween2 := create_tween().set_loops()
	tween2.tween_property(subtitle_label, "modulate", Color(1.0, 0.92, 0.20, 1.0), 2.2)
	tween2.tween_property(subtitle_label, "modulate", Color(0.98, 0.75, 0.05, 1.0), 2.2)

func _on_new_game() -> void:
	HeroData.reset()
	GameManager.reset()
	DayNight.reset()
	GameManager.pending_load = false
	GameManager.is_running   = true
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _on_load_game() -> void:
	if not SaveSystem.has_save(): return
	GameManager.pending_load = true
	GameManager.is_running   = true
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
