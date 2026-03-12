## scripts/World.gd
## Główna scena gry — zarządzanie overworld, spawning, budynki, rendering
## Attach do węzła Main (Node2D) w scenie Main.tscn

extends Node2D

# ── Węzły (wypełniane przez @onready) ─────────
@onready var hero_node      : CharacterBody2D = $Hero
@onready var enemies_node   : Node2D          = $Enemies
@onready var allies_node    : Node2D          = $Allies
@onready var coins_node     : Node2D          = $Coins
@onready var dungeon_node                     = $DungeonScene
@onready var hud_node                         = $HUD

# ── Neon / atmospheric nodes (statyczne w Main.tscn) ──
@onready var canvas_modulate : CanvasModulate = $CanvasModulate
@onready var player_light    : PointLight2D   = $Hero/PlayerLight
@onready var water_rect      : ColorRect      = $WaterRect

# ── Klasy scen dynamicznych ───────────────────
const EnemyScene  = preload("res://scripts/Enemy.gd")
const ArcherScene = preload("res://scripts/Archer.gd")
const WarriorScene= preload("res://scripts/Warrior.gd")

# ── Assety graficzne (ładowane dynamicznie z res://assets/) ──
var _tex_smith  : Texture2D = null
var _tex_wall   : Texture2D = null
var _tex_moon   : Texture2D = null

# ── Stan overworld ────────────────────────────
var coins        : Array = []        # {x, y, r, pulse, collected}
var projectiles  : Array = []        # {x, y, vx, vy, life, is_hero}
var float_texts  : Array = []        # {x, y, text, color, life, max_life}
var fishermen    : Array = []        # farm workers
var wall_bodies  : Dictionary = {}   # wall_id → StaticBody2D

# ── Particle System (debris + fire) ──────────────────────────
var _debris : Array = []   # {x,y,vx,vy,rot,rot_spd,size,color,life,max_life}
var _fire   : Array = []   # {x,y,vx,vy,size,life,max_life}

# ── ArcaneSpire — cząsteczki przy Town Center (jak JS ArcaneSpire.particles) ──
var _spire_particles : Array = []  # {x,y,vx,vy,vy_g,size,color,life,max_life}
var _spire_timer     : float = 0.0
var _apex_angle      : float = 0.0  # obrót diamentowego kryształu (Stage 3)

# ── Windmill per-farm data ─────────────────────
var _windmill : Dictionary = {}  # farm_id → {blade_angle, grain_timer}
var _grain    : Array = []       # {x,y,vx,vy,life,max_life,size}

var enemy_spawn_timer : float = -8.0  # grace period
const SPAWN_INTERVAL  := 12.0
var pending_waste_spawns : int = 0

# ── Sterowanie ────────────────────────────────
var _is_dungeon : bool = false
var _return_portal_x : float = Constants.DUNGEON_PORTAL_RIGHT

func _ready() -> void:
	# Załaduj assety graficzne jeśli istnieją
	_load_assets()
	# Sygnały
	DayNight.night_started.connect(_on_night_started)
	DayNight.day_started.connect(_on_day_started)
	GameManager.notification.connect(_on_notification)
	HeroData.died.connect(_on_hero_died)
	HeroData.leveled_up.connect(_on_hero_leveled)

	hero_node.attacked.connect(_on_hero_attacked)
	hero_node.shot_arrow.connect(_on_hero_shot)
	hero_node.interacted.connect(_on_hero_interacted)
	hero_node.bow_needed.connect(func(): GameManager.notify("🏹 Find a bow first! (check Chests)", Color(0.99, 0.83, 0.30)))

	# Startowe monety i farmerzy
	_spawn_coin(150, Constants.GROUND_Y - 20)
	_spawn_fisherman(-600, 1)

	# Przebuduj fizykę murów z GameManager.buildings
	for b in GameManager.buildings:
		if b["type"] == "wall" and b.get("built", false):
			_create_wall_body(b)

	# ── Neonowa oprawa wizualna ──────────────────
	_setup_neon_env()

	# Gra startuje od razu (menu to osobna scena MainMenu.tscn)
	GameManager.is_running = true
	# Wczytaj save jeśli pending_load ustawiony przez MainMenu
	if GameManager.pending_load:
		GameManager.pending_load = false
		SaveSystem.load_game(self)

# ── Główna pętla ──────────────────────────────
func _load_assets() -> void:
	# Kuznia.png — grafika kuźni/smithy
	if ResourceLoader.exists("res://assets/Kuznia.png"):
		_tex_smith = load("res://assets/Kuznia.png")
	# mur.png — grafika muru Lv1
	if ResourceLoader.exists("res://assets/mur.png"):
		_tex_wall = load("res://assets/mur.png")
	# game_moon.png — księżyc w nocy
	if ResourceLoader.exists("res://assets/game_moon.png"):
		_tex_moon = load("res://assets/game_moon.png")

func _physics_process(delta: float) -> void:
	if not GameManager.is_running: return

	HeroData.tick_iframes(delta)

	if _is_dungeon:
		dungeon_node.update(delta)
		queue_redraw()
		return

	# Dzień/noc
	DayNight.tick(delta)
	# Aktualizuj oświetlenie co klatkę (płynne przejścia)
	_update_canvas_modulate(DayNight.is_night)
	# Poświata bohatera tylko nocą
	if player_light:
		if DayNight.is_night:
			var nf : float = clamp((float(DayNight.elapsed) - float(Constants.DAY_S)) / 8.0, 0.0, 1.0)
			player_light.energy = nf * 0.70
			player_light.enabled = true
		else:
			var df : float = clamp((float(Constants.DAY_S) - float(DayNight.elapsed)) / 6.0, 0.0, 1.0)
			player_light.energy = df * 0.15
			if player_light.energy < 0.01:
				player_light.enabled = false

	# Spawnowanie wrogów
	_tick_enemy_spawning(delta)

	# Aktualizacje sojuszników
	for child in allies_node.get_children():
		pass  # _process działa automatycznie w Node2D

	# Pociski
	_update_projectiles(delta)

	# Monety
	_update_coins()

	# Farmerzy (generują złoto)
	_update_fishermen(delta)
	_update_windmill(delta)

	# Float texts
	_update_float_texts(delta)

	# Interakcja z budynkami (proximity prompt)
	_check_building_proximity()

	# Ogień na zniszczonych budynkach
	_tick_building_fire()

	# ArcaneSpire — cząsteczki Town Center
	_update_spire_particles(delta)

	# Wejście do dungeonu
	if not _is_dungeon:
		_check_dungeon_portals()

	# Przesuń WaterRect razem z kamerą
	if water_rect:
		water_rect.position.x = hero_node.position.x - get_viewport_rect().size.x * 0.5
		water_rect.size.x = get_viewport_rect().size.x
	queue_redraw()

# ── Rendering ─────────────────────────────────
func _draw() -> void:
	if _is_dungeon: return

	var t   := Time.get_ticks_msec() * 0.001
	var vp  := get_viewport_rect()
	var W   := vp.size.x
	var H   := vp.size.y
	# Pobierz rzeczywistą pozycję kamery (uwzględnia drag smoothing)
	var cam_node := hero_node.get_node_or_null("Camera2D") if hero_node else null
	var cam_x : float
	if cam_node and cam_node is Camera2D:
		# get_screen_center_position() zwraca środek widoku w przestrzeni świata
		cam_x = cam_node.get_screen_center_position().x
	else:
		cam_x = hero_node.position.x if hero_node else 0.0
	var _cam_y := H * 0.5
	var top   := 0.0

	# 1. Niebo (gradient ekranowy)
	_draw_sky(cam_x, top, W, H, t)

	# 2. Gwiazdy (nocą)
	if DayNight.is_night:
		_draw_stars(cam_x, top, W, H, t)

	# 3. Słońce / Księżyc
	_draw_sun_moon(cam_x, top, W, H, t)

	# 4. Chmury (w dzień)
	_draw_clouds(cam_x, top, W, H, t)

	# 5. Góry (fBm paralaksa)
	_draw_mountains(cam_x, W, t)

	# 6. Wzgórza (rolling hills jak w oryginale)
	_draw_hills(cam_x, W)

	# 7. Drzewa tła
	_draw_background_trees(cam_x, W)
	_draw_forest_trees(cam_x, W)     # dense forest biome trees
	_draw_wasteland_trees(cam_x, W)  # bare dead wasteland trees

	# 8. Głębokie tło gruntu (ciemny pas za drzewami)
	_draw_deep_ground(cam_x, W)

	# 9. Ziemia + trawa
	_draw_ground(cam_x, W)

	# 10. Refleksje (pod poziomem gruntu)
	_draw_reflections(cam_x, W, t)

	# 11. Budynki
	_draw_buildings(cam_x, W, t)

	# 11b. Punkty budowy (niepostawione budynki — świecące orby z ceną)
	_draw_constr_points(cam_x, W, t)

	# 12. Portale
	_draw_portals(cam_x, W, t)

	# 13. Monety
	_draw_coins_gfx(t)

	# 14. Float texts
	_draw_float_texts()

	# 15. Pociski
	_draw_projectiles()

	# 16. Rally flag
	_draw_rally_flag(cam_x, t)
	# 17. Grain particles (windmill)
	_draw_grain_particles(cam_x)
	# 18. Particles (debris + fire)
	_update_draw_particles(get_process_delta_time())
	# 19. ArcaneSpire cząsteczki (nad budynkami, pod HUD)
	_draw_spire_particles(cam_x)

# ── Niebo ───────────────────────────────────────────────────────────────────
func _draw_sky(cam_x: float, top: float, W: float, _H: float, _t: float) -> void:
	# Keyframe gradient nieba — 1:1 z oryginałem JS (SKY_KEYFRAMES)
	# Dzień: 0-100s | Noc: 100-240s
	var e := DayNight.elapsed
	var kf: Array = [
		# Cykl 180s: dzień 0-80s, noc 80-180s
		[0.0,   Color(0.353, 0.784, 0.980), Color(0.659, 0.847, 0.941)],  # Świt
		[16.0,  Color(0.290, 0.639, 0.863), Color(0.529, 0.808, 0.922)],  # Ranek
		[40.0,  Color(0.180, 0.525, 0.757), Color(0.365, 0.678, 0.886)],  # Południe
		[64.0,  Color(0.831, 0.502, 0.306), Color(0.910, 0.659, 0.439)],  # Popołudnie
		[80.0,  Color(0.110, 0.039, 0.212), Color(0.176, 0.071, 0.282)],  # Zmierzch (start nocy)
		[130.0, Color(0.031, 0.000, 0.078), Color(0.071, 0.000, 0.157)],  # Głęboka noc
		[155.0, Color(0.051, 0.000, 0.125), Color(0.102, 0.000, 0.220)],  # Przed świtem
		[180.0, Color(0.353, 0.784, 0.980), Color(0.659, 0.847, 0.941)],  # Nowy świt
	]
	var top_col := kf[0][1] as Color
	var bot_col := kf[0][2] as Color
	for i in range(kf.size() - 1):
		var t0 := kf[i][0] as float
		var t1 := kf[i+1][0] as float
		if e >= t0 and e < t1:
			var prog := (e - t0) / (t1 - t0)
			top_col = (kf[i][1] as Color).lerp(kf[i+1][1] as Color, prog)
			bot_col = (kf[i][2] as Color).lerp(kf[i+1][2] as Color, prog)
			break
	# Gradient pixel-perfect — jedna linia na rząd pikseli (pełna paleta kolorów)
	var sky_h : float = Constants.GROUND_Y - top
	# cam_x jest centrum ekranu — rysujemy od lewej do prawej krawędzi viewportu
	var lx    : float = cam_x - W * 0.5 - 2.0
	var rx    : float = cam_x + W * 0.5 + 2.0
	var rows  : int   = int(sky_h) + 2
	for s in range(rows):
		var frac : float = float(s) / float(rows)
		var col  : Color = top_col.lerp(bot_col, pow(frac, 0.72))
		var sy   : float = top + float(s)
		draw_line(Vector2(lx, sy), Vector2(rx, sy), col, 1.5)

# ── Gwiazdy ─────────────────────────────────────────────────────────────────
func _draw_stars(cam_x: float, top: float, W: float, _H: float, t: float) -> void:
	# Intensywność gwiazd zależy od pory (fade in/out przy zmierzchu/świcie)
	var e := DayNight.elapsed
	var star_alpha := 1.0
	if e < 95.0:     star_alpha = clamp((e - 80.0) / 15.0, 0.0, 1.0)   # fade in przy zmierzchu
	elif e > 165.0:  star_alpha = clamp(1.0 - (e - 165.0) / 15.0, 0.0, 1.0)  # fade out przed świtem

	var rng := RandomNumberGenerator.new()
	# Duże gwiazdy (20 szt.) — świecące punkty z poświatą
	for i in range(20):
		rng.seed = i * 2311 + 42
		var sx := cam_x - W * 0.5 + rng.randf() * W * 1.0
		var sy := top + rng.randf() * (Constants.GROUND_Y - top) * 0.65
		var twinkle := 0.55 + 0.45 * sin(t * 1.8 + float(i) * 1.3)
		var r       := 1.2 + rng.randf() * 1.8
		draw_circle(Vector2(sx, sy), r * 3.5, Color(1, 1, 0.9, twinkle * 0.07 * star_alpha))
		draw_circle(Vector2(sx, sy), r * 1.5, Color(1, 1, 0.95, twinkle * 0.55 * star_alpha))
		draw_circle(Vector2(sx, sy), r,       Color(1, 1, 1,    twinkle * star_alpha))
	# Małe gwiazdy (180 szt.)
	for i in range(180):
		rng.seed = i * 1337 + 7
		var sx := cam_x - W * 0.8 + rng.randf() * W * 1.6
		var sy := top + rng.randf() * (Constants.GROUND_Y - top) * 0.78
		var twinkle := 0.45 + 0.55 * sin(t * 1.3 + float(i) * 0.9)
		var r       := 0.4 + rng.randf() * 0.9
		draw_circle(Vector2(sx, sy), r * 2.0, Color(1, 1, 1, twinkle * 0.05 * star_alpha))
		draw_circle(Vector2(sx, sy), r,       Color(1, 1, 1, twinkle * 0.75 * star_alpha))

# ── Słońce i Księżyc ─────────────────────────────────────────────────────────
func _draw_sun_moon(cam_x: float, _top: float, W: float, H: float, t: float) -> void:
	var e       := DayNight.elapsed
	var is_day  := not DayNight.is_night
	var frac    := e / Constants.DAY_S if is_day else (e - Constants.DAY_S) / (Constants.CYCLE_S - Constants.DAY_S)
	frac = clamp(frac, 0.0, 1.0)

	# Łuk paraboliczny: od lewej do prawej, szczyt w połowie
	var cx := cam_x - W * 0.5 + frac * W
	var cy := H * 0.08 + (1.0 - sin(frac * PI)) * (H * 0.38)

	if is_day:
		# Kolor słońca — 1:1 z HTML: white→yellow (0-70%), yellow→red (70-100%)
		var sun_col: Color
		if frac <= 0.7:
			var p : float = frac / 0.7
			sun_col = Color(1.0, 1.0, 1.0).lerp(Color(1.0, 1.0, 0.0), p)
		else:
			var p : float = (frac - 0.7) / 0.3
			sun_col = Color(1.0, 1.0, 0.0).lerp(Color(0.918, 0.294, 0.114), p)  # #FFFF00 → #EA4B1D

		# Halo słoneczne — symulacja radialGradient przez 16 warstw (smooth bez banding)
		var sc : Color = sun_col
		var sr : float = 22.0 + 4.0 * sin(t * 0.3)
		var sv : Vector2 = Vector2(cx, cy)
		# 16 kroków od zewnątrz do środka = płynny gradient jak w HTML
		var steps := 16
		for i in range(steps, 0, -1):
			var frac_i : float = float(i) / float(steps)        # 1.0 → 0.0625
			var radius  : float = sr * 2.5 * frac_i             # od max do małego
			# Alpha rośnie w stronę centrum (jak radialGradient)
			var alpha   : float = pow(1.0 - frac_i, 1.5) * 0.75 + 0.02
			draw_circle(sv, radius, Color(sc.r, sc.g * 0.9, sc.b * 0.2, alpha))
		# Rdzeń (pełny, nieprzezroczysty)
		draw_circle(sv, sr, sc)
		# Biały środek
		draw_circle(sv, sr * 0.5, Color(1.0, 1.0, 0.98, 0.95))

	else:
		# Księżyc — animowany
		var moon_pulse := 1.0 + 0.03 * sin(t * 0.8)
		var mr := 28.0 * moon_pulse

		if _tex_moon:
			var ms := mr * 2.0
			draw_texture_rect(_tex_moon, Rect2(cx - ms*0.5, cy - ms*0.5, ms, ms), false)
		else:
			# Poświata księżyca — smooth 12-step jak HTML shadowBlur=40
			var mv : Vector2 = Vector2(cx, cy)
			var moon_base := Color(0.929, 0.914, 0.996)  # #ede9fe jak HTML
			for mi in range(12, 0, -1):
				var mf : float = float(mi) / 12.0
				var mr2 : float = mr * 3.5 * mf
				var ma  : float = pow(1.0 - mf, 1.8) * 0.55 + 0.01
				draw_circle(mv, mr2, Color(moon_base.r, moon_base.g, moon_base.b, ma))
			# Tarcza księżyca
			draw_circle(mv, mr, moon_base)
			# Sierp — przyciemnienie jak w HTML: nadpisujemy kolorem nieba
			var sky_col := DayNight.get_sky_color(); sky_col.a = 1.0
			draw_circle(Vector2(cx + 10.0, cy - 5.0), mr * 0.85, sky_col)
			# Detaliczne kratery (subtelne)
			draw_circle(Vector2(cx - 8.0, cy + 6.0), 4.0,  Color(0.80, 0.78, 0.90, 0.25))
			draw_circle(Vector2(cx + 4.0, cy - 10.0), 2.5, Color(0.80, 0.78, 0.90, 0.20))

# ── Chmury ───────────────────────────────────────────────────────────────────
func _draw_clouds(cam_x: float, _top: float, W: float, H: float, t: float) -> void:
	# Chmury widoczne w dzień i przy zmierzchu (fade out w nocy)
	var e := DayNight.elapsed
	var cloud_alpha := 1.0
	if e > 65.0 and e < 80.0:    cloud_alpha = clamp(1.0 - (e - 65.0) / 15.0, 0.0, 1.0)
	elif e > 165.0 and e < 180.0: cloud_alpha = clamp((e - 165.0) / 15.0, 0.0, 1.0)
	elif DayNight.is_night:        cloud_alpha = 0.0
	if cloud_alpha <= 0.01: return

	var rng := RandomNumberGenerator.new()
	for i in range(7):
		rng.seed = i * 773 + 1
		var speed    := 18.0 + rng.randf() * 14.0
		var layer    := rng.randi() % 3       # 0=daleko, 1=środek, 2=blisko
		var parallax := 0.15 + layer * 0.12
		var size_mul := 0.6 + layer * 0.2
		var base_y   := H * (0.05 + layer * 0.06)
		var cy       := base_y + rng.randf_range(-20.0, 15.0)
		# Pozycja: porusza się z czasem + paralaksa
		var world_offset : float = fmod(t * speed + float(i) * 800.0, W * 4.0)
		var cx : float = cam_x - W * 1.8 + world_offset - cam_x * parallax
		cx = fmod(cx - cam_x + W * 2.0, W * 4.0) + cam_x - W * 2.0
		if cx < cam_x - W * 1.6 or cx > cam_x + W * 1.6: continue

		var alpha  := cloud_alpha * (0.50 + layer * 0.18)
		var rs     := [38.0 * size_mul, 28.0 * size_mul, 30.0 * size_mul, 22.0 * size_mul]
		# Cień pod chmurą
		var shadow_w: float = rs[0] * 3.2
		draw_rect(Rect2(cx - shadow_w * 0.5, cy + rs[0] * 0.6, shadow_w, rs[0] * 0.3),
			Color(0.55, 0.72, 0.87, alpha * 0.22))
		# 4 koła tworzące kształt chmury
		var offsets_x := [0.0, rs[0]*0.75, -rs[0]*0.6, rs[0]*0.4]
		var offsets_y := [0.0, rs[1]*0.45, rs[2]*0.35, -rs[3]*0.1]
		for h in range(4):
			var hcx: float = cx + (offsets_x[h] as float)
			var hcy: float = cy + (offsets_y[h] as float)
			var hr:  float = rs[h] as float
			# Cień dolnych kulek
			draw_circle(Vector2(hcx, hcy), hr * 1.15, Color(0.68, 0.84, 0.95, alpha * 0.35))
			# Miękka poświata zewnętrzna
			draw_circle(Vector2(hcx, hcy), hr * 1.05, Color(0.88, 0.94, 0.99, alpha * 0.65))
			# Rdzeń kulki (jasny biały)
			draw_circle(Vector2(hcx, hcy), hr, Color(0.97, 0.98, 1.00, alpha))
			# Podświetlony góry (blask od słońca)
			draw_circle(Vector2(hcx - hr*0.2, hcy - hr*0.25), hr * 0.55, Color(1.0, 1.0, 1.0, alpha * 0.55))
		# Podstawa (płaski prostokąt spinający chmurę)
		var bw: float = rs[0] * 2.8
		draw_rect(Rect2(cx - bw * 0.5, cy, bw, rs[0] * 0.52),
			Color(0.91, 0.96, 0.99, alpha * 0.92))

# ── Góry (fBm) ───────────────────────────────────────────────────────────────
func _hill_y(world_x: float, amp1: float, amp2: float) -> float:
	var h := amp1 * sin(world_x * 0.0007 + 0.5) 		+ amp2 * cos(world_x * 0.0011 + 1.2)
	return Constants.GROUND_Y - 40.0 - h

func _draw_mountains(cam_x: float, W: float, _t: float) -> void:
	# Góry — trzy warstwy paralaksy jak w oryginale JS
	# Tylna warstwa: dalekie góry (ciemniejsze, mniejsza paralaksa)
	_draw_mountain_layer(cam_x, W, 0.08, Color(0.05, 0.055, 0.10), 280.0, 120.0)
	# Środkowa warstwa: główne góry (charakterystyczne z screenshota)
	_draw_mountain_layer(cam_x, W, 0.15, Color(0.045, 0.048, 0.085), 380.0, 160.0)
	# Przednia warstwa: mniejsze pagórki (szybsza paralaksa)
	_draw_mountain_layer(cam_x, W, 0.22, Color(0.038, 0.042, 0.072), 200.0, 90.0)

func _draw_mountain_layer(cam_x: float, W: float, parallax: float,
		col: Color, amp_main: float, amp_detail: float) -> void:
	var step     := 16.0
	var shift    := cam_x * parallax
	var pts      := PackedVector2Array()
	var sx       := cam_x - W * 0.55
	var ex       := cam_x + W * 0.55
	var x        := sx
	while x <= ex + step:
		var wx  := x + shift
		# fBm z 4 oktaw — gładkie faliste profile jak w oryginale
		var n := 0.0
		n += 0.500 * (sin(wx * 0.0006 + 5000.0) * 0.5 + 0.5)
		n += 0.250 * (sin(wx * 0.0012 + 1234.0) * 0.5 + 0.5)
		n += 0.125 * (sin(wx * 0.0024 + 8765.0) * 0.5 + 0.5)
		n += 0.063 * (sin(wx * 0.0048 + 2345.0) * 0.5 + 0.5)
		n /= 0.938
		n = pow(n, 1.5)
		pts.append(Vector2(x, Constants.GROUND_Y - 30.0 - n * amp_main
				- amp_detail * 0.3 * sin(wx * 0.002 + 1.7)))
		x += step
	pts.append(Vector2(ex + step, Constants.GROUND_Y))
	pts.append(Vector2(sx,        Constants.GROUND_Y))
	draw_colored_polygon(pts, col)

# ── Wzgórza (rolling hills) ──────────────────────────────────────────────────
func _draw_hills(cam_x: float, W: float) -> void:
	var abs_x: float = absf(cam_x)
	var bg_col: Color
	var bg_col2: Color  # jaśniejsza warstwa przednia
	if abs_x > 5000:
		bg_col  = Color(0.16, 0.030, 0.000, 0.95)
		bg_col2 = Color(0.22, 0.055, 0.010, 0.90)
	elif abs_x > 2000:
		bg_col  = Color(0.025, 0.100, 0.040, 0.95)
		bg_col2 = Color(0.040, 0.160, 0.060, 0.90)
	else:
		bg_col  = Color(0.030, 0.110, 0.050, 0.95)
		bg_col2 = Color(0.055, 0.170, 0.075, 0.90)

	var GY : float = Constants.GROUND_Y
	# Tylna warstwa wzgórz (wolniejsza paralaksa, krok 8px)
	_draw_hill_layer(cam_x, W, GY, bg_col, 0.0007, 0.0011, 0.5, 1.2, 110.0, 60.0, 25.0, 8.0)
	# Przednia warstwa wzgórz (szybsza paralaksa, krok 6px, niższe)
	_draw_hill_layer(cam_x, W, GY, bg_col2, 0.0013, 0.0019, 1.1, 2.5, 70.0, 40.0, 10.0, 6.0)

func _draw_hill_layer(cam_x: float, W: float, GY: float, col: Color,
		freq1: float, freq2: float, phase1: float, phase2: float,
		amp1: float, amp2: float, base_off: float, step: float) -> void:
	var sx : float = cam_x - step * 2.0
	var ex : float = cam_x + W + step * 2.0

	# Zbierz punkty profilu wzgórz
	var pts : PackedVector2Array = PackedVector2Array()
	var x   : float = sx
	while x <= ex:
		var amp : float = amp1 * clamp(absf(x) / 3000.0, 0.35, 1.0)
		var hy  : float = GY - base_off - (amp * sin(x * freq1 + phase1) + amp2 * cos(x * freq2 + phase2))
		# Clamp żeby nigdy nie wyszło poza ekran
		hy = clamp(hy, 10.0, GY - 2.0)
		pts.append(Vector2(x, hy))
		x += step

	# Domknij polygon na dole ekranu
	if pts.size() < 2:
		return
	var close_pts : PackedVector2Array = PackedVector2Array()
	close_pts.append_array(pts)
	close_pts.append(Vector2(ex + step, GY + 10.0))
	close_pts.append(Vector2(sx - step, GY + 10.0))

	# Walidacja — muszą być co najmniej 3 różne punkty
	if close_pts.size() < 3:
		return
	draw_colored_polygon(close_pts, col)


# ── Drzewa tła ───────────────────────────────────────────────────────────────
# ── FOREST dense trees (abs_x 2000-5000) — JS: drawBiomeOverlay forest block ──
func _draw_forest_trees(cam_x: float, W: float) -> void:
	var GY := Constants.GROUND_Y
	# 3-layer canopy colours from JS
	var cols := [Color(0.039, 0.227, 0.094), Color(0.051, 0.322, 0.157), Color(0.067, 0.388, 0.220)]
	var lifts : Array[float] = [0.0, 0.22, 0.42]
	# Deterministic positions (same formula as JS _forestTrees)
	for i in range(300):
		var side : float = 1.0 if (i % 2 == 0) else -1.0
		var base : float = 2000.0 + float(i * 53 % 3000)
		var wx   : float = side * base
		if absf(wx) < 2000.0 or absf(wx) > 5000.0: continue
		if wx < cam_x - W * 0.5 - 60.0 or wx > cam_x + W * 0.5 + 60.0: continue
		var th : float = 70.0 + float(i * 37 % 60)
		var tw : float = 18.0 + float(i * 13 % 14)
		# Trunk
		draw_rect(Rect2(wx - tw * 0.2, GY - th * 0.45, tw * 0.4, th * 0.45), Color(0.176, 0.106, 0.0))
		# 3-layer canopy triangles (JS path winding)
		for ci in range(3):
			var lift := lifts[ci]
			var base_y := GY - th * (0.45 + lift)
			var tip_y  := base_y - th * (0.35 - lift * 0.1)
			var hw := tw * (1.0 - lift * 0.5)
			draw_colored_polygon(PackedVector2Array([
				Vector2(wx - hw, base_y),
				Vector2(wx,      tip_y),
				Vector2(wx + hw, base_y),
			]), cols[ci])

# ── WASTELAND dead trees (abs_x 5000-10000) — JS: _wasteTreePositions ──
func _draw_wasteland_trees(cam_x: float, W: float) -> void:
	var GY := Constants.GROUND_Y
	var trunk_col := Color(0.227, 0.082, 0.0)
	var glow_col  := Color(1.0, 0.267, 0.0, 0.5)
	for i in range(100):
		var side : float = 1.0 if (i % 2 == 0) else -1.0
		var wx   : float = side * (5000.0 + float(i * 97 % 5000))
		if absf(wx) < 5000.0: continue
		if wx < cam_x - W * 0.5 - 60.0 or wx > cam_x + W * 0.5 + 60.0: continue
		# Bare trunk with ember glow
		draw_line(Vector2(wx, GY), Vector2(wx, GY - 80.0), trunk_col, 4.0)
		draw_line(Vector2(wx, GY), Vector2(wx, GY - 80.0), glow_col, 6.0)
		# Bare branches
		draw_line(Vector2(wx, GY - 55.0), Vector2(wx - 25.0, GY - 80.0), trunk_col, 2.0)
		draw_line(Vector2(wx, GY - 65.0), Vector2(wx + 20.0, GY - 85.0), trunk_col, 2.0)
		draw_line(Vector2(wx, GY - 55.0), Vector2(wx - 25.0, GY - 80.0), glow_col, 3.0)
		draw_line(Vector2(wx, GY - 65.0), Vector2(wx + 20.0, GY - 85.0), glow_col, 3.0)

func _draw_background_trees(cam_x: float, W: float) -> void:
	var abs_x : float = absf(cam_x)
	# Kolor drzew zależny od biomu (jak w oryginale JS)
	var tree_col: Color
	var _trunk_col: Color
	if abs_x > 5000:
		tree_col  = Color(0.180, 0.025, 0.000, 0.96)  # wasteland: głęboka czerwień
		_trunk_col = Color(0.18, 0.04, 0.00)
	elif abs_x > 2000:
		tree_col  = Color(0.020, 0.130, 0.050, 0.96)  # forest: głęboka zieleń
		_trunk_col = Color(0.06, 0.12, 0.04)
	else:
		tree_col  = Color(0.055, 0.010, 0.160, 0.96)  # kingdom: neonowy fiolet
		_trunk_col = Color(0.06, 0.01, 0.14)

	var base_y  := Constants.GROUND_Y - 38.0
	var spacing := 180.0
	var offset  : float = fmod(-cam_x, spacing)

	# Warstwa tylna (mniejsze drzewa, wolniejsza paralaksa)
	var shift_back := -cam_x * 0.08
	var x_back : float = fmod(shift_back, spacing) - spacing
	while x_back < W + spacing:
		var wx := x_back + cam_x
		var h_var : float = 0.70 + 0.20 * sin(wx * 0.003 + 1.5)
		var tw := 17.0 * h_var; var th := 88.0 * h_var
		var tx_col := Color(tree_col.r * 0.65, tree_col.g * 0.65, tree_col.b * 0.65, tree_col.a * 0.7)
		# Pień
		draw_rect(Rect2(x_back - 3, base_y - th * 0.42, 6, th * 0.42), tx_col)
		# Dolny trójkąt
		draw_colored_polygon([
			Vector2(x_back - tw, base_y - th * 0.42),
			Vector2(x_back,      base_y - th * 0.78),
			Vector2(x_back + tw, base_y - th * 0.42),
		], tx_col)
		# Górny trójkąt
		draw_colored_polygon([
			Vector2(x_back - tw * 0.7, base_y - th * 0.58),
			Vector2(x_back,            base_y - th),
			Vector2(x_back + tw * 0.7, base_y - th * 0.58),
		], tx_col)
		x_back += spacing * 0.65

	# Warstwa przednia (główne drzewa — identyczne z oryginałem JS)
	var x := offset - spacing
	while x < W + spacing:
		var wx := x + cam_x
		var h_var : float = 0.80 + 0.25 * sin(wx * 0.002 + 0.7)
		var tw := 22.0 * h_var; var th := 110.0 * h_var
		# Pień
		draw_rect(Rect2(x - 4, base_y - th * 0.50, 8, th * 0.50), tree_col)
		# Dolny trójkąt
		draw_colored_polygon([
			Vector2(x - tw,      base_y - th * 0.50),
			Vector2(x,           base_y - th * 0.95),
			Vector2(x + tw,      base_y - th * 0.50),
		], tree_col)
		# Środkowy trójkąt
		draw_colored_polygon([
			Vector2(x - tw * 0.78, base_y - th * 0.66),
			Vector2(x,             base_y - th * 1.08),
			Vector2(x + tw * 0.78, base_y - th * 0.66),
		], tree_col)
		# Wierzchni trójkąt (ostry czubek)
		draw_colored_polygon([
			Vector2(x - tw * 0.48, base_y - th * 0.82),
			Vector2(x,             base_y - th * 1.18),
			Vector2(x + tw * 0.48, base_y - th * 0.82),
		], tree_col)
		x += spacing

# ── Odbicia pod poziomem gruntu ──────────────────────────────────────────────
func _draw_reflections(cam_x: float, W: float, t: float) -> void:
	var GY   : float = Constants.GROUND_Y
	var refl_h : float = 40.0   # głębokość pasa odbić

	# Kolor tła odbić — przezroczysta wersja trawy
	var abs_x : float = absf(cam_x)
	var refl_tint : Color
	if abs_x > 5000:
		refl_tint = Color(0.15, 0.03, 0.00, 0.55)
	elif abs_x > 2000:
		refl_tint = Color(0.02, 0.12, 0.04, 0.55)
	else:
		refl_tint = Color(0.05, 0.02, 0.16, 0.55)

	# Pas odbić pod gruntem
	draw_rect(Rect2(cam_x - W, GY, W * 3, refl_h), refl_tint)

	# Odbicia budynków — lustrzane, przyciemnione, z falowaniem
	for b in GameManager.buildings:
		if not b.get("built", false): continue
		var bx : float = b["x"] - cam_x + W * 0.5
		if bx < -b["w"] or bx > W + b["w"]: continue
		var bw : float = b["w"]
		var bh : float = min(b["h"] * 0.35, refl_h * 0.85)  # tylko górna część odbita

		# Falowanie — offset w osi X
		var wave : float = sin(t * 2.0 + b["x"] * 0.01) * 1.5

		var rc : Color = b["glow"]
		rc.a = 0.22
		rc.r *= 0.6; rc.g *= 0.6; rc.b *= 0.6
		# Lustrzany prostokąt (Y zwiększa się w dół = odbicie)
		draw_rect(Rect2(bx - bw * 0.5 + wave, GY + 2.0, bw, bh), rc)

		# Neonowa linia odbicia (górna krawędź)
		var edge_col : Color = b["glow"]
		edge_col.a = 0.30
		draw_line(
			Vector2(bx - bw * 0.5 + wave, GY + 2.0),
			Vector2(bx + bw * 0.5 + wave, GY + 2.0),
			edge_col, 1.5
		)

	# Odbicie bohatera
	if hero_node:
		var hx : float = hero_node.position.x - cam_x + W * 0.5
		var hw  : float = Constants.PLAYER_W * 0.5
		var hh_r : float = Constants.PLAYER_H * 0.3
		var wave_h : float = sin(t * 2.5) * 1.2
		# Przyciemniona sylwetka bohatera w odbiciu
		draw_rect(Rect2(hx - hw + wave_h, GY + 2.0, Constants.PLAYER_W, hh_r),
			Color(0.60, 0.30, 1.00, 0.25))
		# Głowa odbita
		draw_circle(Vector2(hx + wave_h, GY + hh_r + 6.0),
			5.0, Color(0.60, 0.30, 1.00, 0.18))

	# Linia separacji woda/grunt — neonowa
	var line_col : Color
	if abs_x > 5000: line_col = Color(1.5, 0.3, 0.0)
	elif abs_x > 2000: line_col = Color(0.2, 1.8, 0.5)
	else: line_col = Color(0.8, 0.2, 2.0)
	draw_line(Vector2(cam_x - W, GY), Vector2(cam_x + W * 2, GY), line_col, 2.0)

# ── Głęboki grunt (ciemny pas za drzewami) ───────────────────────────────────
func _draw_deep_ground(cam_x: float, W: float) -> void:
	var abs_x : float = absf(cam_x)
	var deep_col: Color
	if abs_x > 5000:
		deep_col = Color(0.10, 0.01, 0.00)
	elif abs_x > 2000:
		deep_col = Color(0.02, 0.06, 0.02)
	else:
		deep_col = Color(0.039, 0.0, 0.078)
	draw_rect(Rect2(cam_x - W * 2, Constants.GROUND_Y - 42, W * 5, 42), deep_col)
	draw_rect(Rect2(cam_x - W * 2, Constants.GROUND_Y - 42, W * 5, 2),  Color(deep_col.r * 0.5, deep_col.g * 0.5, deep_col.b * 0.5))

# ── Ziemia + trawa ────────────────────────────────────────────────────────────
func _draw_ground(cam_x: float, W: float) -> void:
	var abs_x: float = absf(cam_x)
	var ground_col: Color
	var grass_col:  Color
	var grass_top:  Color
	if abs_x > 5000:
		ground_col = Color(0.165, 0.031, 0.0)      # wasteland
		grass_col  = Color(0.290, 0.063, 0.0)
		grass_top  = Color(0.900, 0.220, 0.000)    # HDR neonowa pomarańcz
	elif abs_x > 2000:
		ground_col = Color(0.039, 0.180, 0.094)    # forest
		grass_col  = Color(0.039, 0.180, 0.094)
		grass_top  = Color(0.100, 0.900, 0.280)    # HDR neonowa zieleń
	else:
		ground_col = Color(0.067, 0.000, 0.133)    # #110022 jak HTML
		grass_col  = Color(0.176, 0.051, 0.322)    # #2d0d52 jak HTML
		grass_top  = Color(0.420, 0.129, 0.659)    # #6b21a8 jak HTML (lekki glow przez Glow system)
	# Wypełnienie
	draw_rect(Rect2(cam_x - W * 2, Constants.GROUND_Y,      W * 5, 200), ground_col)
	# Trawa
	draw_rect(Rect2(cam_x - W * 2, Constants.GROUND_Y,      W * 5, 16),  grass_col)
	# Świecąca krawędź trawy
	draw_rect(Rect2(cam_x - W * 2, Constants.GROUND_Y,      W * 5, 3),   grass_top)

func _draw_buildings(cam_x: float, W: float, t: float) -> void:
	# ── Tło (budynki niespecjalne) ──
	_draw_buildings_background(cam_x, W, t)
	# ── Farmerzy ──
	_draw_fishermen_gfx(t)
	# ── Mieszkańcy przy Town Center ──
	_draw_residents(t)
	# ── Pierwszoplanowe (mury, skrzynie, town center) ──
	_draw_buildings_foreground(cam_x, W, t)
	# Etykiety niewybudowanych budynków obsługuje _draw_constr_points()

func _draw_buildings_background(cam_x: float, W: float, t: float) -> void:
	# JS 2.5D constant: ctx.scale(0.75) centred at (bx, GROUND_Y-40)
	const BG_SCALE := 0.75
	for b in GameManager.buildings:
		if not b.get("built", false): continue
		var btype: String = b["type"]
		if btype == "wall" or btype == "chest" or b["id"] == "town_center": continue
		var bx: float = b["x"]
		if bx < cam_x - W - 200 or bx > cam_x + W + 200: continue
		var bw: float = b["w"]; var bh: float = b["h"]
		var col: Color = b.get("color", Color(0.3,0.3,0.3))
		var glow: Color = b.get("glow", Color.WHITE)

		# ── Apply 2.5D perspective scale (JS equivalent) ──────────────
		var pivot := Vector2(bx, Constants.GROUND_Y - 40.0)
		draw_set_transform(pivot * (1.0 - BG_SCALE), 0.0, Vector2(BG_SCALE, BG_SCALE))
		var by: float = Constants.GROUND_Y - bh   # base coords (scaled by transform)

		if btype == "shop":
			_draw_shop(bx, by, bw, bh, glow, t)
		elif btype == "teleport":
			_draw_teleport(bx, by, bh, glow, t)
		elif btype == "smith":
			var gc2 := glow; gc2.a = 0.25
			draw_rect(Rect2(bx - bw*0.5 - 6, by - 6, bw + 12, bh + 12), gc2)
			if _tex_smith:
				draw_texture_rect(_tex_smith, Rect2(bx - bw*0.5, by, bw, bh), false)
			else:
				draw_rect(Rect2(bx - bw*0.5, by, bw, bh), col)
				var flame_y := by + bh * 0.3 + 5.0 * sin(t * 5.0)
				draw_circle(Vector2(bx, flame_y), 10, Color(0.96, 0.62, 0.04, 0.8))
		elif btype == "barracks":
			_draw_barracks(bx, by, bw, bh, col, glow, t)
		elif btype == "forge":
			_draw_forge(bx, by, bw, bh, col, glow, t)
		elif btype == "farm":
			_draw_farm(bx, by, bw, bh, col, glow, t)
			# Wiatrak dla stage 2+
			if b.get("stage", 1) >= 2:
				_draw_farm_windmill(bx, by, bw, b.get("id", ""))
		else:
			var gc := glow; gc.a = 0.28
			draw_rect(Rect2(bx - bw*0.5 - 6, by - 6, bw + 12, bh + 12), gc)
			draw_rect(Rect2(bx - bw*0.5, by, bw, bh), col)

		# ── Fire effect when hp < 30% ─────────────────────────────────
		var b_max_hp : int = b.get("max_hp", 0)
		if b_max_hp > 0:
			var pct := float(b.get("hp", b_max_hp)) / float(b_max_hp)
			if pct < 0.3 and randf() < 0.20:
				var fx := bx + (randf() - 0.5) * bw
				var fy := Constants.GROUND_Y - bh * 0.6
				_spawn_fire_particle(fx, fy)

		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)  # reset

func _draw_buildings_foreground(cam_x: float, W: float, t: float) -> void:
	for b in GameManager.buildings:
		if not b.get("built", false): continue
		var btype: String = b["type"]
		if btype != "wall" and btype != "chest" and b["id"] != "town_center": continue
		var bx: float = b["x"]
		if bx < cam_x - W - 300 or bx > cam_x + W + 300: continue
		var bw: float = b["w"]; var bh: float = b["h"]
		var by: float = Constants.GROUND_Y - bh
		var glow: Color = b.get("glow", Color.WHITE)

		if b["id"] == "town_center":
			_draw_town_center(bx, by, bw, t, b)
		elif btype == "wall":
			_draw_wall(bx, by, bw, bh, glow, b, t)
		elif btype == "chest":
			_draw_chest(bx, by, bw, bh, glow, b, t)

func _draw_building_labels(cam_x: float, W: float) -> void:
	var font := ThemeDB.fallback_font
	for b in GameManager.buildings:
		if b.get("built", false): continue
		var bx: float = b["x"]
		if bx < cam_x - W - 100 or bx > cam_x + W + 100: continue
		var cost: int = b.get("cost", 0)
		var label_str: String = "%s [%dG]" % [b["name"], cost]
		var label_y: float = Constants.GROUND_Y - (b["h"] as float) - 14
		draw_string(font, Vector2(bx, label_y), label_str,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(0.8, 0.8, 0.8, 0.8))
		# Małe kółko wskaźnik
		var dot_col: Color = b.get("glow", Color.WHITE); dot_col.a = 0.9
		draw_circle(Vector2(bx, Constants.GROUND_Y - 10), 8, dot_col)

# ── Town Center — identyczny z JS buildings_fx.js ─────────────────────────
func _draw_town_center(sx: float, _by: float, _bw: float, t: float, b: Dictionary) -> void:
	var stage: int = b.get("stage", 1)
	var GY := Constants.GROUND_Y

	if stage == 1:
		_draw_tc_tent(sx, GY)
		_draw_campfire(sx + 60.0, 1.0, GY, t)
		_draw_well(sx - 60.0, GY)
	elif stage == 2:
		_draw_tc_outpost(sx, GY)
		_draw_campfire(sx + 60.0, 1.2, GY, t)
		_draw_fountain(sx - 60.0, 2, GY)
	else:
		_draw_tc_citadel(sx, GY, t)
		_draw_eternal_flame(sx + 60.0, t, GY)
		_draw_fountain(sx - 60.0, 3, GY)
		_draw_apex_crystal(sx, t, GY)

	# HP bar Town Center
	var hp_max: int = b.get("max_hp", 1)
	if hp_max > 0:
		var pct: float = clamp(float(b.get("hp",0)) / float(hp_max), 0.0, 1.0)
		var bar_w := 70.0
		var bar_y := GY - 115.0 if stage == 1 else (GY - 185.0 if stage == 2 else GY - 225.0)
		draw_rect(Rect2(sx - bar_w*0.5, bar_y, bar_w, 5), Color(0,0,0,0.7))
		var hp_col := Color(0.29,0.87,0.50) if pct > 0.5 else Color(0.93,0.27,0.27)
		draw_rect(Rect2(sx - bar_w*0.5, bar_y, bar_w * pct, 5), hp_col)

func _draw_tc_tent(sx: float, GY: float) -> void:
	# Namiot (fioletowy trójkąt) — jak w JS drawTent
	var gc := Color(0.58, 0.20, 0.82, 0.3)
	draw_colored_polygon(PackedVector2Array([
		Vector2(sx - 44, GY + 4), Vector2(sx + 44, GY + 4), Vector2(sx, GY - 62)
	]), gc)
	draw_colored_polygon(PackedVector2Array([
		Vector2(sx - 40, GY), Vector2(sx + 40, GY), Vector2(sx, GY - 60)
	]), Color(0.18, 0.06, 0.40))
	# Obramowanie
	draw_polyline(PackedVector2Array([
		Vector2(sx - 40, GY), Vector2(sx, GY - 60), Vector2(sx + 40, GY)
	]), Color(0.75, 0.52, 0.99), 2.0)
	# Wewnętrzna ciemna część (wejście)
	draw_colored_polygon(PackedVector2Array([
		Vector2(sx - 10, GY), Vector2(sx + 10, GY), Vector2(sx, GY - 40)
	]), Color(0.06, 0.02, 0.10))

func _draw_tc_outpost(sx: float, GY: float) -> void:
	# Outpost (prostokąt z parapetami)
	draw_rect(Rect2(sx - 45, GY - 110, 90, 110), Color(0.06, 0.09, 0.16))
	draw_rect(Rect2(sx - 45, GY - 110, 90, 110), Color(0.23, 0.51, 0.96, 0.0))  # border via polyline
	draw_polyline(PackedVector2Array([
		Vector2(sx-45,GY-110), Vector2(sx+45,GY-110),
		Vector2(sx+45,GY), Vector2(sx-45,GY), Vector2(sx-45,GY-110)
	]), Color(0.23, 0.51, 0.96), 2.0)
	# Drzwi
	draw_colored_polygon(PackedVector2Array([
		Vector2(sx-15,GY), Vector2(sx+15,GY), Vector2(sx+15,GY-30), Vector2(sx,GY-45), Vector2(sx-15,GY-30)
	]), Color(0.12, 0.23, 0.54))
	draw_polyline(PackedVector2Array([
		Vector2(sx-15,GY), Vector2(sx-15,GY-30), Vector2(sx,GY-45),
		Vector2(sx+15,GY-30), Vector2(sx+15,GY)
	]), Color(0.38, 0.64, 0.98), 1.5)
	# Parapety
	for i in range(-45, 36, 20):
		draw_rect(Rect2(sx + i, GY - 120, 10, 10), Color(0.23, 0.51, 0.96))

func _draw_tc_citadel(sx: float, GY: float, t: float) -> void:
	# Wieże z tyłu
	draw_colored_polygon(PackedVector2Array([
		Vector2(sx-90,GY), Vector2(sx-60,GY), Vector2(sx-75,GY-180)
	]), Color(0.06,0.09,0.16))
	draw_colored_polygon(PackedVector2Array([
		Vector2(sx+60,GY), Vector2(sx+90,GY), Vector2(sx+75,GY-180)
	]), Color(0.06,0.09,0.16))
	draw_polyline(PackedVector2Array([Vector2(sx-90,GY),Vector2(sx-75,GY-180),Vector2(sx-60,GY)]),
		Color(0.23,0.51,0.96),2.0)
	draw_polyline(PackedVector2Array([Vector2(sx+60,GY),Vector2(sx+75,GY-180),Vector2(sx+90,GY)]),
		Color(0.23,0.51,0.96),2.0)
	# Dachy wież
	draw_colored_polygon(PackedVector2Array([
		Vector2(sx-95,GY-180), Vector2(sx-55,GY-180), Vector2(sx-75,GY-210)
	]), Color(0.12,0.23,0.54))
	draw_colored_polygon(PackedVector2Array([
		Vector2(sx+55,GY-180), Vector2(sx+95,GY-180), Vector2(sx+75,GY-210)
	]), Color(0.12,0.23,0.54))
	# Główny budynek
	draw_rect(Rect2(sx-55,GY-140,110,140), Color(0.06,0.09,0.16))
	draw_polyline(PackedVector2Array([
		Vector2(sx-55,GY-140), Vector2(sx+55,GY-140),
		Vector2(sx+55,GY), Vector2(sx-55,GY), Vector2(sx-55,GY-140)
	]), Color(0.23,0.51,0.96), 2.0)
	# Główny dach
	draw_colored_polygon(PackedVector2Array([
		Vector2(sx-65,GY-140), Vector2(sx+65,GY-140), Vector2(sx,GY-200)
	]), Color(0.12,0.23,0.54))
	draw_polyline(PackedVector2Array([
		Vector2(sx-65,GY-140), Vector2(sx,GY-200), Vector2(sx+65,GY-140)
	]), Color(0.38,0.64,0.98), 3.0)
	# Drzwi z łukiem (jak w JS: arc + złota dekoracja)
	var door_pts := PackedVector2Array()
	door_pts.append(Vector2(sx-20, GY))
	door_pts.append(Vector2(sx+20, GY))
	door_pts.append(Vector2(sx+20, GY-40))
	for ai in range(17):  # półokrąg od 0 do PI
		var a2 := float(ai) / 16.0 * PI
		door_pts.append(Vector2(sx + cos(a2) * 20.0, GY - 40 - sin(a2) * 20.0))
	door_pts.append(Vector2(sx-20, GY-40))
	draw_colored_polygon(door_pts, Color(0.12,0.23,0.54))
	draw_polyline(door_pts, Color(0.38,0.64,0.98), 2.0)
	# Złota dekoracja drzwi — pionowa belka
	draw_rect(Rect2(sx-2, GY-40, 4, 40), Color(0.99, 0.83, 0.30))
	# Półokrąg-dekoracja łuku (jak JS: arc złota)
	for ai in range(9):
		var a2 := float(ai) / 8.0 * PI
		var p1 := Vector2(sx + cos(float(ai)/8.0*PI)*16.0, GY-40-sin(float(ai)/8.0*PI)*16.0)
		var p2 := Vector2(sx + cos(float(ai+1)/8.0*PI)*16.0, GY-40-sin(float(ai+1)/8.0*PI)*16.0)
		draw_line(p1, p2, Color(0.99, 0.83, 0.30), 1.5)
	# Okna
	draw_circle(Vector2(sx-30, GY-80), 8, Color(0.99, 0.94, 0.55))
	draw_circle(Vector2(sx+30, GY-80), 8, Color(0.99, 0.94, 0.55))
	draw_circle(Vector2(sx, GY-110), 12, Color(0.99, 0.94, 0.55))
	# ── Czerwone flagi/banery (jak JS drawCitadelSpires) ──────────────────
	var flag_wave := sin(t * 2.5) * 4.0  # machanie flagą
	# Lewa flaga
	draw_rect(Rect2(sx-45, GY-140, 12, 40), Color(0.94, 0.27, 0.27))
	draw_colored_polygon(PackedVector2Array([
		Vector2(sx-45, GY-100), Vector2(sx-33+flag_wave, GY-110), Vector2(sx-45, GY-120)
	]), Color(0.94, 0.27, 0.27))
	# Prawa flaga
	draw_rect(Rect2(sx+33, GY-140, 12, 40), Color(0.94, 0.27, 0.27))
	draw_colored_polygon(PackedVector2Array([
		Vector2(sx+45, GY-100), Vector2(sx+33-flag_wave, GY-110), Vector2(sx+45, GY-120)
	]), Color(0.94, 0.27, 0.27))

func _draw_campfire(sx: float, _scale: float, GY: float, t: float) -> void:
	# Polana/drewno
	draw_rect(Rect2(sx-10, GY-4, 20, 4), Color(0.36,0.25,0.20))
	# Poświata ognia (animowana)
	var glow_a := 0.18 + 0.12 * sin(t * 7.0 + sx)
	draw_circle(Vector2(sx, GY-10), 20.0 * _scale, Color(0.92, 0.36, 0.04, glow_a))
	draw_circle(Vector2(sx, GY-10), 10.0 * _scale, Color(0.97, 0.62, 0.05, glow_a + 0.15))

# ── Eternal Flame — Stage 3 TC (JS: drawEternalFlame) ───────────────────────
func _draw_eternal_flame(sx: float, t: float, GY: float) -> void:
	# Cokół (jak JS: pedestal #334155)
	draw_rect(Rect2(sx-15, GY-20, 30, 20), Color(0.20, 0.25, 0.33))
	draw_polyline(PackedVector2Array([
		Vector2(sx-15,GY-20), Vector2(sx+15,GY-20),
		Vector2(sx+15,GY), Vector2(sx-15,GY), Vector2(sx-15,GY-20)
	]), Color(0.79, 0.84, 0.88), 1.0)
	# Wielka biała/cyjanowa poświata (pulsująca)
	var pulse := 0.35 + 0.15 * sin(t * 5.0 + 1.2)
	for ri in range(8, 0, -1):
		var rf : float = float(ri) / 8.0
		var ra : float = pulse * pow(1.0 - rf, 1.4)
		var col : Color = Color(1.0, 1.0, 1.0, ra) if randf() > 0.5 else Color(0.40, 0.91, 0.97, ra)
		draw_circle(Vector2(sx, GY-30), 25.0 * rf, col)
	# Białe jądro płomienia
	draw_circle(Vector2(sx, GY-30), 6.0, Color(1.0, 1.0, 1.0, 0.90))

# ── Apex Crystal — obracający się diament na szczycie cytadeli (JS: APEX CRYSTAL) ─
func _draw_apex_crystal(sx: float, t: float, GY: float) -> void:
	var cy   : float = GY - 225.0   # szczyt dachu
	var size : float = 14.0 + 2.0 * sin(t * 1.8)  # lekkie pulsowanie
	var ang  : float = _apex_angle             # obrót (aktualizowany w _update_spire_particles)
	# Poświata kryształu — biały blask (jak JS shadowBlur=40)
	for gi in range(10, 0, -1):
		var gf  : float = float(gi) / 10.0
		var ga  : float = pow(1.0 - gf, 1.6) * 0.55
		draw_circle(Vector2(sx, cy), size * 3.5 * gf, Color(1.0, 1.0, 1.0, ga))
	# Diament (4 punkty obrócone o _apex_angle) — jak JS polygon(4, 18)
	var pts := PackedVector2Array()
	for vi in range(4):
		var a2 : float = ang + float(vi) * PI * 0.5
		pts.append(Vector2(sx + cos(a2) * size, cy + sin(a2) * size))
	draw_colored_polygon(pts, Color(1.0, 1.0, 1.0, 0.95))
	# Cyjanowy kontur dla blasku
	pts.append(pts[0])
	draw_polyline(pts, Color(0.40, 0.91, 0.97, 0.80), 2.0)

func _draw_well(sx: float, GY: float) -> void:
	# Podstawa
	draw_rect(Rect2(sx-15, GY-15, 30, 15), Color(0.28,0.34,0.42))
	draw_rect(Rect2(sx-18, GY-18, 36, 4), Color(0.58,0.64,0.72))
	# Słupki
	draw_line(Vector2(sx-12,GY-15), Vector2(sx-12,GY-40), Color(0.49,0.22,0.07), 2)
	draw_line(Vector2(sx+12,GY-15), Vector2(sx+12,GY-40), Color(0.49,0.22,0.07), 2)
	# Daszek
	draw_colored_polygon(PackedVector2Array([
		Vector2(sx-20,GY-35), Vector2(sx+20,GY-35), Vector2(sx,GY-48)
	]), Color(0.49,0.18,0.07))

func _draw_fountain(sx: float, stage: int, GY: float) -> void:
	var sc := 1.5 if stage == 3 else 1.0
	# Misa
	draw_colored_polygon(PackedVector2Array([
		Vector2(sx-25*sc,GY), Vector2(sx+25*sc,GY),
		Vector2(sx+20*sc,GY-15*sc), Vector2(sx-20*sc,GY-15*sc)
	]), Color(0.12,0.16,0.20))
	draw_polyline(PackedVector2Array([
		Vector2(sx-25*sc,GY), Vector2(sx-20*sc,GY-15*sc),
		Vector2(sx+20*sc,GY-15*sc), Vector2(sx+25*sc,GY)
	]), Color(0.22,0.74,0.98), 2.0)
	# Kolumna
	draw_rect(Rect2(sx-8*sc, GY-35*sc, 16*sc, 20*sc), Color(0.20,0.24,0.32))
	# Woda
	draw_rect(Rect2(sx-18*sc, GY-15*sc, 36*sc, 2*sc), Color(0.22,0.74,0.98, 0.4))

# ── Wall — styl z JS ───────────────────────────────────────────────────────
func _draw_wall(bx: float, by: float, bw: float, bh: float, _glow: Color, b: Dictionary, _t: float) -> void:
	var stage: int = b.get("stage", 1)
	var dGlow := Color(0.58,0.20,0.82) if stage >= 2 else Color(0.42,0.13,0.66)
	var dCol  := Color(0.12,0.07,0.25) if stage == 1 else Color(0.14,0.07,0.30)

	# Poświata
	var gc := dGlow; gc.a = 0.35
	draw_rect(Rect2(bx-bw*0.5-8, by-8, bw+16, bh+16), gc)
	# Główne ciało — mur.png dla stage 1 (jak w JS)
	if stage == 1 and _tex_wall:
		draw_texture_rect(_tex_wall, Rect2(bx-bw*0.5, by, bw, bh), false)
	else:
		draw_rect(Rect2(bx-bw*0.5, by, bw, bh), dCol)
		# Kontur
		draw_polyline(PackedVector2Array([
			Vector2(bx-bw*0.5,by), Vector2(bx+bw*0.5,by),
			Vector2(bx+bw*0.5,by+bh), Vector2(bx-bw*0.5,by+bh), Vector2(bx-bw*0.5,by)
		]), dGlow, 1.5)
	# Merlony na szczycie
	var mcount := 2 + stage
	for m in range(mcount):
		var mx: float = bx - bw*0.5 + bw*(float(m)+0.5)/float(mcount)
		draw_rect(Rect2(mx-5, by-12, 10, 12), dGlow)

	# Łucznicy na murze (wizualne)
	var archers_on_wall: int = 0
	if allies_node:
		for ally in allies_node.get_children():
			if "assigned_wall_id" in ally and ally.assigned_wall_id == b["id"]:
				archers_on_wall += 1
	for ai in range(archers_on_wall):
		var ax: float = bx - 15.0 + ai * 30.0
		draw_rect(Rect2(ax-5, by-30, 10, 20), Color(0.13,0.27,0.50))
		draw_circle(Vector2(ax, by-34), 6, Color(0.90,0.75,0.55))

	# HP bar
	var hp_max: int = b.get("max_hp", 1)
	if hp_max > 0:
		var pct: float = clamp(float(b.get("hp",0))/float(hp_max), 0.0, 1.0)
		draw_rect(Rect2(bx-bw*0.5, by-16, bw, 5), Color(0,0,0,0.7))
		var hc := Color(0.29,0.87,0.50) if pct > 0.5 else Color(0.93,0.27,0.27)
		draw_rect(Rect2(bx-bw*0.5, by-16, bw*pct, 5), hc)

# ── Shop — styl z JS ───────────────────────────────────────────────────────
func _draw_shop(sx: float, by: float, bw: float, bh: float, glow: Color, t: float) -> void:
	var gc := glow; gc.a = 0.25
	draw_rect(Rect2(sx-bw*0.5-6, by-6, bw+12, bh+12), gc)
	draw_rect(Rect2(sx-bw*0.5, by, bw, bh), Color(0.06,0.09,0.16))
	draw_polyline(PackedVector2Array([
		Vector2(sx-bw*0.5,by), Vector2(sx+bw*0.5,by),
		Vector2(sx+bw*0.5,by+bh), Vector2(sx-bw*0.5,by+bh), Vector2(sx-bw*0.5,by)
	]), glow, 2.0)
	# Dach trójkątny
	draw_colored_polygon(PackedVector2Array([
		Vector2(sx-bw*0.5-10,by), Vector2(sx+bw*0.5+10,by), Vector2(sx,by-30)
	]), Color(0.12,0.16,0.20))
	draw_polyline(PackedVector2Array([
		Vector2(sx-bw*0.5-10,by), Vector2(sx,by-30), Vector2(sx+bw*0.5+10,by)
	]), Color(0.93,0.27,0.27), 3.0)
	# Latający diament na dachu
	var dY := by - 15.0 + sin(t * 2.0) * 5.0
	draw_colored_polygon(PackedVector2Array([
		Vector2(sx,dY-6), Vector2(sx+6,dY), Vector2(sx,dY+6), Vector2(sx-6,dY)
	]), Color.WHITE)
	# Glowing spheres
	draw_circle(Vector2(sx-bw*0.25, by+15), 6, Color(0.99,0.88,0.18))
	draw_circle(Vector2(sx+bw*0.25, by+15), 6, Color(0.99,0.88,0.18))
	draw_circle(Vector2(sx, by+30), 8, Color(0.99,0.88,0.18))
	# Drzwi łukowe
	draw_polyline(PackedVector2Array([
		Vector2(sx-8,by+bh), Vector2(sx-8,by+bh-20)
	]), Color(0.38,0.64,0.98), 2.0)
	draw_polyline(PackedVector2Array([
		Vector2(sx+8,by+bh), Vector2(sx+8,by+bh-20)
	]), Color(0.38,0.64,0.98), 2.0)
	draw_arc(Vector2(sx,by+bh-20), 8, PI, 0, 12, Color(0.38,0.64,0.98), 2.0)

# ── Teleport — styl z JS ──────────────────────────────────────────────────
func _draw_teleport(sx: float, by: float, bh: float, glow: Color, t: float) -> void:
	var gc := glow; gc.a = 0.3
	# Podstawa słupa
	draw_rect(Rect2(sx-8, by+15, 16, bh-15), Color(0.05,0.00,0.13))
	draw_polyline(PackedVector2Array([
		Vector2(sx-8,by+15), Vector2(sx+8,by+15),
		Vector2(sx+8,by+bh), Vector2(sx-8,by+bh), Vector2(sx-8,by+15)
	]), glow, 1.5)
	# Arch / portal ring (elipsa = seria łuków)
	var pulse := 0.18 + 0.10 * sin(t * 4.0)
	var fill_col := Color(0.51, 0.55, 0.97, pulse)
	# Wypełnienie łuku portalu
	var pts := PackedVector2Array()
	for i in range(13):
		var angle: float = PI + (PI * i / 12.0)
		pts.append(Vector2(sx + 22.0 * cos(angle), by + 20 + 36.0 * sin(angle)))
	draw_colored_polygon(pts, fill_col)
	# Kontur łuku
	var arc_pts := PackedVector2Array()
	for i in range(25):
		var angle: float = PI + (PI * i / 24.0)
		arc_pts.append(Vector2(sx + 22.0 * cos(angle), by + 20 + 36.0 * sin(angle)))
	var glow_bright := glow; glow_bright.a = 1.0
	draw_polyline(arc_pts, glow_bright, 3.0)
	# Podstawa elipsy (płaskie dno)
	draw_line(Vector2(sx-22, by+20), Vector2(sx+22, by+20), glow, 2.0)
	# Gwiazda/runa nad łukiem
	var star_y := by - 8.0 + sin(t * 3.0) * 4.0
	draw_circle(Vector2(sx, star_y), 4, Color.WHITE)
	# Podświetlona platforma u dołu
	draw_arc(Vector2(sx, Constants.GROUND_Y - 2), 22, 0, PI, 16, Color(0.51,0.55,0.97,0.35), 4.0)

# ── Farm — styl z JS ──────────────────────────────────────────────────────
func _draw_farm(sx: float, by: float, bw: float, bh: float, col: Color, glow: Color, _t: float) -> void:
	var gc := glow; gc.a = 0.25
	draw_rect(Rect2(sx-bw*0.5-5, by-5, bw+10, bh+10), gc)
	draw_rect(Rect2(sx-bw*0.5, by, bw, bh), col)
	draw_polyline(PackedVector2Array([
		Vector2(sx-bw*0.5,by), Vector2(sx+bw*0.5,by),
		Vector2(sx+bw*0.5,by+bh), Vector2(sx-bw*0.5,by+bh), Vector2(sx-bw*0.5,by)
	]), glow, 1.5)
	# Dach zielony
	draw_colored_polygon(PackedVector2Array([
		Vector2(sx-bw*0.5-5,by), Vector2(sx+bw*0.5+5,by), Vector2(sx,by-20)
	]), Color(0.10,0.24,0.10))
	draw_polyline(PackedVector2Array([
		Vector2(sx-bw*0.5-5,by), Vector2(sx,by-20), Vector2(sx+bw*0.5+5,by)
	]), glow, 1.5)

func _draw_farm_windmill(sx: float, by: float, _bw: float, bid: String) -> void:
	# Hub
	var hub_y: float = by - 6.0
	draw_circle(Vector2(sx, hub_y), 7.0, Color(0.09, 0.40, 0.09))
	draw_arc(Vector2(sx, hub_y), 7.0, 0, TAU, 16, Color(0.29, 0.87, 0.50), 2.0)
	# Blades
	var angle: float = _windmill.get(bid, {}).get("blade_angle", 0.0)
	var blade_len := 40.0; var blade_w := 7.0
	for i in range(4):
		var a: float = angle + (float(i) / 4.0) * TAU
		var cos_a := cos(a); var sin_a := sin(a)
		var tip := Vector2(sx + cos_a * blade_len, hub_y + sin_a * blade_len)
		var perp := Vector2(-sin_a, cos_a) * blade_w * 0.5
		var pts := PackedVector2Array([
			Vector2(sx, hub_y) + perp,
			tip + perp * 0.3,
			tip - perp * 0.3,
			Vector2(sx, hub_y) - perp
		])
		draw_colored_polygon(pts, Color(0.09, 0.33, 0.08))
		draw_polyline(pts, Color(0.29, 0.87, 0.50), 1.0, true)

func _draw_grain_particles(cam_x: float) -> void:
	for g: Dictionary in _grain:
		var alpha: float = clamp(g["life"] / g["max_life"], 0.0, 1.0)
		var gx: float = g["x"] - cam_x
		var sz: float = g["size"]
		draw_rect(Rect2(gx - sz*0.5, g["y"] - sz*0.5, sz, sz),
			Color(0.99, 0.91, 0.54, alpha))

# ── Barracks ───────────────────────────────────────────────────────────────
func _draw_barracks(sx: float, by: float, bw: float, bh: float, col: Color, glow: Color, _t: float) -> void:
	var gc := glow; gc.a = 0.25
	draw_rect(Rect2(sx-bw*0.5-6, by-6, bw+12, bh+12), gc)
	draw_rect(Rect2(sx-bw*0.5, by, bw, bh), col)
	draw_polyline(PackedVector2Array([
		Vector2(sx-bw*0.5,by), Vector2(sx+bw*0.5,by),
		Vector2(sx+bw*0.5,by+bh), Vector2(sx-bw*0.5,by+bh), Vector2(sx-bw*0.5,by)
	]), glow, 2.0)
	# Bęben wojskowy
	draw_arc(Vector2(sx, by+bh*0.5), 18, 0, TAU, 24, glow, 2.0)
	# Krzyż miecze
	draw_line(Vector2(sx-12, by+bh*0.5-8), Vector2(sx+12, by+bh*0.5+8), Color(0.94,0.27,0.27), 2)
	draw_line(Vector2(sx+12, by+bh*0.5-8), Vector2(sx-12, by+bh*0.5+8), Color(0.94,0.27,0.27), 2)

# ── Forge ─────────────────────────────────────────────────────────────────
func _draw_forge(sx: float, by: float, bw: float, bh: float, col: Color, glow: Color, t: float) -> void:
	var gc := glow; gc.a = 0.25
	draw_rect(Rect2(sx-bw*0.5-6, by-6, bw+12, bh+12), gc)
	draw_rect(Rect2(sx-bw*0.5, by, bw, bh), col)
	draw_polyline(PackedVector2Array([
		Vector2(sx-bw*0.5,by), Vector2(sx+bw*0.5,by),
		Vector2(sx+bw*0.5,by+bh), Vector2(sx-bw*0.5,by+bh), Vector2(sx-bw*0.5,by)
	]), glow, 2.0)
	var flame_y := by + bh * 0.25 + 5.0 * sin(t * 5.0)
	draw_circle(Vector2(sx, flame_y), 12, Color(0.96, 0.62, 0.04, 0.7))
	draw_circle(Vector2(sx, flame_y+6), 7, Color(1.0, 0.85, 0.35, 0.8))

# ── Chest ─────────────────────────────────────────────────────────────────
func _draw_chest(cx: float, cy: float, bw: float, bh: float, glow: Color, b: Dictionary, t: float) -> void:
	var is_open: bool = b.get("opened", false)
	var chest_col: Color = Color(0.17,0.10,0.02) if is_open else (b.get("color", Color(0.55,0.27,0.07)) as Color)
	var gc_a: float = 0.0 if is_open else (0.6 + 0.3 * sin(t * 3.0 + float(b["x"]) * 0.001))
	var border: Color = Color(0.27,0.18,0.04) if is_open else glow

	if not is_open:
		var gc := glow; gc.a = gc_a * 0.5
		draw_rect(Rect2(cx-bw*0.5-4, cy-4, bw+8, bh+8), gc)
	draw_rect(Rect2(cx-bw*0.5, cy, bw, bh), chest_col)
	# Wieko
	var lid_col: Color = (Color(0.10,0.06,0.00,0.4) if is_open else glow)
	lid_col.a = 0.4 if is_open else 0.9
	draw_rect(Rect2(cx-bw*0.5, cy, bw, bh*0.35), lid_col)
	draw_polyline(PackedVector2Array([
		Vector2(cx-bw*0.5,cy), Vector2(cx+bw*0.5,cy),
		Vector2(cx+bw*0.5,cy+bh), Vector2(cx-bw*0.5,cy+bh), Vector2(cx-bw*0.5,cy)
	]), border, 1.5)
	if not is_open:
		draw_circle(Vector2(cx, cy+bh*0.6), 4, Color(0.99,0.83,0.30))

# ── Farmerzy — detaliczny rysunek z JS ────────────────────────────────────
func _draw_fishermen_gfx(_t: float) -> void:
	var GY := Constants.GROUND_Y
	for f in fishermen:
		var sx: float = f["x"]
		var _dir: int = f.get("dir", 1)
		var _walk: float = f.get("walk", 0.0)
		var yBase: float = GY - 40.0

		# Ciało
		draw_rect(Rect2(sx-6, yBase-28, 12, 28), Color(0.08,0.24,0.13))
		draw_polyline(PackedVector2Array([
			Vector2(sx-6,yBase-28), Vector2(sx+6,yBase-28),
			Vector2(sx+6,yBase), Vector2(sx-6,yBase), Vector2(sx-6,yBase-28)
		]), Color(0.29,0.87,0.50), 1.0)
		# Kapelusz (trójkąt)
		draw_colored_polygon(PackedVector2Array([
			Vector2(sx-10,yBase-28), Vector2(sx,yBase-38), Vector2(sx+10,yBase-28)
		]), Color(0.89,0.70,0.08))
		# Głowa
		draw_circle(Vector2(sx, yBase-34), 8, Color(0.90,0.75,0.55))
		# Postęp farmy (wskaźnik zielony łuk)
		var timer_val: float = f.get("timer", 1800.0)
		var prog: float = 1.0 - clamp(timer_val / 1800.0, 0.0, 1.0)
		if prog > 0:
			draw_arc(Vector2(sx, yBase-46), 12, -PI*0.5, -PI*0.5 + prog*TAU, 16,
				Color(0.29,0.87,0.50), 2.0)

# ── Mieszkańcy przy Town Center ───────────────────────────────────────────
func _draw_residents(t: float) -> void:
	var tc: Dictionary = {}
	for b in GameManager.buildings:
		if b["id"] == "town_center" and b.get("built", false):
			tc = b; break
	if tc.is_empty(): return

	var stage: int = tc.get("stage", 1)
	var count: int = 0
	if stage == 1: count = 2
	elif stage == 2: count = 4
	else: count = 7

	var offsets := [-140.0, 160.0, -170.0, 180.0, -120.0, 140.0, 130.0]
	var dirs    := [1, -1, 1, -1, 1, -1, -1]
	var GY := Constants.GROUND_Y
	var _font := ThemeDB.fallback_font

	for i in range(count):
		var rx: float = tc["x"] + offsets[i]
		var bob: float = sin(t * 2.0 + i) * 2.0
		var res_col := Color(0.28,0.35,0.44) if i % 2 == 0 else Color(0.32,0.32,0.36)
		draw_rect(Rect2(rx-8, GY-24+bob, 16, 24), res_col)
		draw_circle(Vector2(rx, GY-28+bob), 6, Color(0.98,0.64,0.64))
		# Oczko
		draw_circle(Vector2(rx + dirs[i]*3, GY-29+bob), 1.5, Color(0.12,0.11,0.30))

func _draw_portals(cam_x: float, W: float, t: float) -> void:
	# Portale lochu (lewy i prawy)
	for wx in [Constants.DUNGEON_PORTAL_LEFT, Constants.DUNGEON_PORTAL_RIGHT]:
		if abs(wx - cam_x) > W + 200: continue
		var r := 40.0 + 8.0 * sin(t * 3.0 + wx * 0.001)
		var center := Vector2(wx, Constants.GROUND_Y - 30)
		draw_arc(center, r, 0, TAU, 32, Color(0.51, 0.55, 0.97), 3)
		draw_arc(center, r * 1.5, 0, TAU, 32, Color(0.51, 0.55, 0.97, 0.35), 2)
		draw_circle(center, r * 0.7, Color(0.51, 0.55, 0.97, 0.08))
		draw_string(ThemeDB.fallback_font, Vector2(wx, Constants.GROUND_Y - 82),
			"Underworld Portal", HORIZONTAL_ALIGNMENT_CENTER, -1, 13, Color(0.78, 0.80, 1.0, 0.95))
		draw_string(ThemeDB.fallback_font, Vector2(wx, Constants.GROUND_Y - 65),
			"SPACE to enter", HORIZONTAL_ALIGNMENT_CENTER, -1, 11, Color(0.70, 0.70, 1.0, 0.65))

	# Portale wrogów (uproszczone)
	for portal in Constants.PORTALS:
		var px : float = portal["x"]
		if abs(px - cam_x) > W + 200: continue
		var biome_col := Color(0.80, 0.0, 0.33) if portal["biome"] == "waste" \
			else (Color(0.13, 0.55, 0.13) if portal["biome"] == "forest" else Color(0.40, 0.20, 0.80))
		var r := 20.0 + 4.0 * sin(t * 2.0 + px * 0.001)
		draw_arc(Vector2(px, Constants.GROUND_Y - 20), r, 0, TAU, 16, biome_col, 2)

func _draw_constr_points(cam_x: float, W: float, t: float) -> void:
	# Świecące orby z ceną nad miejscami niepostawionych budynków (jak drawConstrPoints w JS)
	var font := ThemeDB.fallback_font
	var GY   := Constants.GROUND_Y
	for b in GameManager.buildings:
		if b.get("built", false): continue
		var bx : float = b["x"]
		if abs(bx - cam_x) > W + 120: continue
		var orb_col : Color
		match b.get("type", ""):
			"shop":     orb_col = Color(0.98, 0.57, 0.19)
			"farm":     orb_col = Color(0.27, 0.87, 0.50)
			"teleport": orb_col = Color(0.51, 0.55, 0.97)
			_:          orb_col = Color(0.75, 0.50, 0.99)
		var pulse : float = 1.0 + 0.15 * sin(t * 3.0 + bx)
		var orb_r : float = 10.0 * pulse
		# Pionowa linia od ziemi do orba
		draw_line(Vector2(bx, GY), Vector2(bx, GY - 72), orb_col * Color(1,1,1,0.5), 2.0)
		# Orb
		draw_circle(Vector2(bx, GY - 72), orb_r, Color(orb_col.r, orb_col.g, orb_col.b, 0.25))
		draw_circle(Vector2(bx, GY - 72), orb_r * 0.6, orb_col)
		# Etykieta z ceną
		var lbl : String = b.get("name", "?") + " [" + str(b.get("cost", 0)) + "G]"
		draw_string(font, Vector2(bx, GY - 90), lbl,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 11, Color(1.0, 1.0, 1.0, 0.65))

func _tick_building_fire() -> void:
	# Spawnuj cząsteczki ognia z budynków z <30% HP (jak spawnBuildingFire w JS)
	for b in GameManager.buildings:
		if not b.get("built", false): continue
		var max_hp : int = b.get("max_hp", b.get("maxHp", 0))
		if max_hp <= 0: continue
		var hp : int = b.get("hp", max_hp)
		var pct : float = float(hp) / float(max_hp)
		if pct < 0.3 and randf() < 0.15:  # 0.25 w JS @60fps ≈ 0.15 @30fps
			var bw : float = b.get("w", 40)
			var bh : float = b.get("h", 60)
			var fx : float = b["x"] + (randf() - 0.5) * bw
			var fy : float = Constants.GROUND_Y - bh * 0.6
			_spawn_fire_particle(fx, fy)

func _draw_coins_gfx(_t: float) -> void:
	for c in coins:
		if c["collected"]: continue
		c["pulse"] = c["pulse"] + 0.06
		var sc  := 1.0 + 0.2 * sin(c["pulse"])
		draw_circle(Vector2(c["x"], c["y"]), c["r"] * sc * 2.5, Color(1.0, 0.85, 0.0, 0.3))
		draw_circle(Vector2(c["x"], c["y"]), c["r"] * sc, Color(1.0, 0.85, 0.0))

func _draw_projectiles() -> void:
	for p in projectiles:
		var col: Color = Color(1.0, 0.85, 0.5) if p.get("is_hero", false) else Color(0.66, 0.33, 0.97)
		draw_circle(Vector2(p["x"], p["y"]), 4, col)
		var tail_end := Vector2(p["x"] - p["vx"] * 0.15, p["y"] - p["vy"] * 0.15)
		draw_line(Vector2(p["x"], p["y"]), tail_end, Color(col.r, col.g, col.b, 0.4), 2)

func _draw_float_texts() -> void:
	if not hero_node: return
	var _cam_x := hero_node.position.x
	for f in float_texts:
		var a: float = clamp((f["life"] as float) / (f["max_life"] as float), 0.0, 1.0)
		var col : Color = f["color"]; col.a = a
		# draw_string renders at screen coord relative to Node2D origin (cam_x offset)
		var sx := (f["x"] as float)  # world coords, draw_string uses world coords in Node2D space
		var sy := (f["y"] as float)
		draw_string(
			ThemeDB.fallback_font,
			Vector2(sx, sy),
			f["text"] as String,
			HORIZONTAL_ALIGNMENT_CENTER,
			-1, 14, col
		)

func _draw_rally_flag(_cam_x: float, t: float) -> void:
	if GameManager.rally_point.is_empty(): return
	if GameManager.is_in_dungeon(): return
	var rx : float = GameManager.rally_point.get("x", 0.0)
	var ry := Constants.GROUND_Y
	# Pole flagi
	draw_line(Vector2(rx - 2, ry), Vector2(rx - 2, ry - 60), Color(0.47, 0.22, 0.06), 4)
	# Flaga (trójkąt z animacją falowania)
	var wave : float = sin(t * 5.0) * 5.0
	var flag_pts := PackedVector2Array([
		Vector2(rx + 2, ry - 60),
		Vector2(rx + 32 + wave, ry - 50),
		Vector2(rx + 2,  ry - 40),
	])
	draw_colored_polygon(flag_pts, Color(0.93, 0.27, 0.27))
	# Złota gałka na szczycie
	draw_circle(Vector2(rx + 12 + wave * 0.3, ry - 50), 4, Color(0.98, 0.75, 0.15))

# ── Spawnowanie wrogów ────────────────────────
func _tick_enemy_spawning(delta: float) -> void:
	# Potwory pojawiają się TYLKO w nocy
	if not DayNight.is_night:
		enemy_spawn_timer = -2.0  # reset z grace period na start nocy
		return

	enemy_spawn_timer += delta
	if enemy_spawn_timer >= SPAWN_INTERVAL:
		enemy_spawn_timer = 0.0
		if GameManager.enemies_to_spawn_this_night > 0:
			_spawn_enemy()
			GameManager.enemies_to_spawn_this_night -= 1

	# Wasteland extra spawns (C3 fix z oryginału)
	if pending_waste_spawns > 0:
		pending_waste_spawns -= 1
		_spawn_enemy()

func _spawn_enemy() -> void:
	if enemies_node.get_child_count() >= Constants.ENEMY_CAP: return

	var roll : float = randf()
	var portal : Dictionary
	if roll < 0.1:   portal = Constants.PORTALS[6 + randi() % 2]
	elif roll < 0.3: portal = Constants.PORTALS[4 + randi() % 2]
	elif roll < 0.5: portal = Constants.PORTALS[2 + randi() % 2]
	else:            portal = Constants.PORTALS[randi() % 2]

	var biome_mult := 2.0 if portal["biome"] == "waste" else (1.35 if portal["biome"] == "forest" else 1.0)
	var hp_val: int = int(Constants.ENEMY_HP_BASE * biome_mult)

	var e_node := CharacterBody2D.new()
	e_node.set_script(load("res://scripts/Enemy.gd"))
	e_node.position = Vector2(portal["x"] + randf_range(-20, 20), Constants.GROUND_Y - Constants.ENEMY_H * 0.5)

	var col_shape := CollisionShape2D.new()
	var cap       := CapsuleShape2D.new()
	cap.radius = 12.0; cap.height = 20.0
	col_shape.shape = cap
	e_node.add_child(col_shape)
	# Wróg koliduje tylko z podłożem — nie blokuje gracza, atak przez detekcję odległości
	e_node.collision_layer = 4   # warstwa: enemy (bit 3)
	e_node.collision_mask  = 1   # tylko ground (bit 1)

	enemies_node.add_child(e_node)
	e_node.hp             = hp_val
	e_node.max_hp         = hp_val
	e_node.biome          = portal["biome"]
	e_node.dmg_mult       = biome_mult
	e_node.speed_mult     = 0.8 + randf() * 0.4
	e_node.origin_portal_x = portal["x"]

	# Połącz sygnały float_text i kill
	e_node.float_text_requested.connect(_spawn_float_text)
	e_node.enemy_killed.connect(func(_ex, _ey): pass)  # rozszerzalne

	if portal["biome"] == "waste" and randf() < 0.6:
		pending_waste_spawns += 1

# ── Monety ────────────────────────────────────
func _spawn_coin(x: float, y: float) -> void:
	coins.append({"x": x, "y": y, "r": 7.0, "collected": false, "pulse": randf() * TAU})

func _update_coins() -> void:
	if not hero_node: return
	var px := hero_node.position.x
	var py := hero_node.position.y
	for i in range(coins.size() - 1, -1, -1):
		var c: Dictionary = coins[i]
		if c["collected"]:
			coins.remove_at(i); continue
		if Vector2(px, py).distance_to(Vector2(c["x"], c["y"])) < 40.0:
			c["collected"] = true
			GameManager.add_gold(5)
			_spawn_float_text("+5G", Color(1.0, 0.85, 0.0), c["x"], c["y"] - 15)

# ── Pociski ───────────────────────────────────
func _on_hero_shot() -> void:
	if not hero_node: return
	var facing: int = hero_node.facing_dir as int
	projectiles.append({
		"x": hero_node.position.x + facing * 20,
		"y": hero_node.position.y - 10,
		"vx": facing * 960.0, "vy": -12.0,
		"life": 1.0, "is_hero": true,
	})

func _update_projectiles(delta: float) -> void:
	for i in range(projectiles.size() - 1, -1, -1):
		var p: Dictionary = projectiles[i]
		p["x"]    += p["vx"] * delta
		p["y"]    += p["vy"] * delta
		p["vy"]   += 7.2 * delta * 60.0
		p["life"] -= delta
		if p["y"] >= Constants.GROUND_Y or p["life"] <= 0:
			projectiles.remove_at(i); continue

		# Kolizja z wrogami overworld
		var hit := false
		for e_node in enemies_node.get_children():
			if not e_node.is_in_group("enemies"): continue
			var ex: float = (e_node as Node2D).position.x; var ey: float = (e_node as Node2D).position.y
			if abs(p["x"] - ex) < 14 and abs(p["y"] - ey) < 22:
				var dmg: int = HeroData.damage if p.get("is_hero", false) else 10
				e_node.receive_hit(dmg, Vector2(sign(p["vx"]) * 120, -60))
				hit = true; break

		# Kolizja ze wrogami w lochu (tylko strzały bohatera — jak w JS)
		if not hit and p.get("is_hero", false) and _is_dungeon and dungeon_node and dungeon_node.visible:
			for e in dungeon_node.enemies:
				if e["dead"]: continue
				var ex: float = e["x"]; var ey2: float = e["y"]
				if abs(p["x"] - ex) < 12 and abs(p["y"] - ey2) < 20:
					e["hp"] -= HeroData.damage
					e["hit_flash"] = 12.0
					e["vx"] = sign(p["vx"]) * 180.0
					_spawn_float_text("-%d" % HeroData.damage, Color(1.0, 0.42, 0.42), ex, ey2 - 25.0)
					if e["hp"] <= 0:
						e["dead"] = true
						HeroData.gain_xp(35)
						dungeon_node.coins.append({"x": ex, "y": Constants.GROUND_Y - 15.0,
							"r": 8.0, "collected": false, "pulse": 0.0})
					hit = true; break

		if hit: projectiles.remove_at(i)

# ── Farmerzy ──────────────────────────────────
func _spawn_fisherman(x: float, side: float) -> void:
	fishermen.append({"x": x + side * (30 + randf() * 20), "timer": 1800.0, "walk": 0.0})

func _update_fishermen(delta: float) -> void:
	for f in fishermen:
		f["timer"] -= delta * 60.0
		f["walk"]  += 0.08
		f["x"]     += sin(f["walk"]) * 0.3
		if f["timer"] <= 0.0:
			f["timer"] = 1800.0
			_spawn_coin(f["x"] - 10, Constants.GROUND_Y - 40)
			_spawn_coin(f["x"] + 10, Constants.GROUND_Y - 40)
			GameManager.notify("🌾 Farm generated Gold!", Color(1.0, 0.85, 0.0))

func _update_windmill(delta: float) -> void:
	for b in GameManager.buildings:
		if b.get("type","") != "farm" or not b.get("built", false): continue
		var stage: int = b.get("stage", 1)
		if stage < 2: continue
		var bid: String = b.get("id", "")
		if bid == "": continue
		if not (bid in _windmill):
			_windmill[bid] = {"blade_angle": 0.0, "grain_timer": 0.0}
		var wm: Dictionary = _windmill[bid]
		wm["blade_angle"] = fmod(wm["blade_angle"] + 0.012 * delta * 60.0, TAU)
		wm["grain_timer"] += delta * 60.0
		if wm["grain_timer"] >= 90.0:
			wm["grain_timer"] = 0.0
			for _i in range(6):
				_grain.append({
					"x": float(b["x"]) + (randf()-0.5)*30.0,
					"y": Constants.GROUND_Y - 20.0,
					"vx": (randf()-0.5)*2.0, "vy": 1.0+randf()*1.5,
					"life": 40.0+randf()*20.0, "max_life": 60.0,
					"size": 2.0+randf()*2.0
				})
	# Age grain
	for i in range(_grain.size()-1, -1, -1):
		var g: Dictionary = _grain[i]
		g["x"] += g["vx"]; g["y"] += g["vy"]; g["vy"] *= 0.92; g["life"] -= 1.0
		if g["life"] <= 0.0: _grain.remove_at(i)

# ── Float texts ───────────────────────────────
func _spawn_float_text(text: String, color: Color, x: float, y: float) -> void:
	float_texts.append({"text": text, "color": color, "x": x, "y": y, "life": 1.33, "max_life": 1.33})

func _update_float_texts(delta: float) -> void:
	for i in range(float_texts.size() - 1, -1, -1):
		var f: Dictionary = float_texts[i]
		f["y"]    -= 54.0 * delta
		f["life"] -= delta
		if f["life"] <= 0: float_texts.remove_at(i)

# ── Strzały łuczników ─────────────────────────
func _on_archer_arrow(from_pos: Vector2, vel: Vector2, _archer: Node) -> void:
	projectiles.append({
		"x": from_pos.x, "y": from_pos.y,
		"vx": vel.x, "vy": vel.y,
		"life": 2.5, "is_hero": false,
	})

# ── Interakcja z budynkami ─────────────────────
func _check_building_proximity() -> void:
	if not hero_node: return
	var px := hero_node.position.x
	var nearest : Dictionary = {}
	var nearest_dist := Constants.BUILD_RADIUS * 1.5  # generously sized

	for b in GameManager.buildings:
		# Menu buildings (shop/barracks/forge/smith) get 1.5x radius — same as JS
		var menu_types := ["shop", "barracks", "forge", "smith"]
		var radius: float = Constants.BUILD_RADIUS * 1.5 if b.get("type","") in menu_types else Constants.BUILD_RADIUS
		var d: float = abs(px - (b["x"] as float))
		if d < radius and d < nearest_dist:
			nearest_dist = d
			nearest = b

	if hud_node and hud_node.has_method("show_build_prompt"):
		if nearest.is_empty():
			hud_node.hide_build_prompt()
		else:
			hud_node.show_build_prompt(nearest)

func _on_hero_interacted() -> void:
	if not hero_node: return
	var px := hero_node.position.x

	# Sprawdź portale lochu (priorytet - wejście do jaskini)
	for wx in [Constants.DUNGEON_PORTAL_LEFT, Constants.DUNGEON_PORTAL_RIGHT]:
		if abs(px - wx) < Constants.DUNGEON_PORTAL_RADIUS:
			enter_dungeon(wx)
			return

	# Sprawdź budynki
	for b in GameManager.buildings:
		if abs(px - b["x"]) < Constants.BUILD_RADIUS:
			_interact_building(b)
			return

func _interact_building(b: Dictionary) -> void:
	match b["type"]:
		"chest":     _open_chest(b)
		"wall":
			if b.get("built", false) and b.get("stage", 0) >= 1:
				# Mur wybudowany — otwórz menu konfiguracji
				if hud_node and hud_node.has_method("show_wall_menu"):
					hud_node.show_wall_menu(b)
			else:
				_build_wall(b)
		"town":      _upgrade_town(b)
		"farm":      _upgrade_farm(b)
		"shop":
			if b.get("built", false):
				if hud_node and hud_node.has_method("show_shop_menu"):
					hud_node.show_shop_menu()
			else:
				_build_generic(b)
		"barracks":
			if b.get("built", false):
				if hud_node and hud_node.has_method("show_barracks_menu"):
					hud_node.show_barracks_menu()
			else:
				_build_generic(b)
		"forge":
			if b.get("built", false):
				if hud_node and hud_node.has_method("show_forge_menu"):
					hud_node.show_forge_menu()
			else:
				_build_generic(b)
		"smith":
			if b.get("built", false):
				if hud_node and hud_node.has_method("show_smith_menu"):
					hud_node.show_smith_menu()
			else:
				_build_generic(b)
		"teleport":  _build_generic(b)
		_:           _build_generic(b)

# ── Particle: debris spawn on building destruction ────────────────────────
func _spawn_debris(wx: float, wy: float, col: Color) -> void:
	var count := 3 + randi() % 3
	for _i in range(count):
		var angle := randf() * TAU
		var speed := 60.0 + randf() * 120.0
		_debris.append({
			"x": wx + (randf() - 0.5) * 20.0, "y": wy,
			"vx": cos(angle) * speed, "vy": -abs(sin(angle) * speed) - 60.0,
			"rot": randf() * TAU, "rot_spd": (randf() - 0.5) * 8.0,
			"size": 3.0 + randf() * 5.0,
			"color": col,
			"life": 1.2 + randf() * 0.6, "max_life": 1.8,
		})

# ── Particle: fire emitter for damaged buildings ───────────────────────────
func _spawn_fire_particle(wx: float, wy: float) -> void:
	_fire.append({
		"x": wx + (randf() - 0.5) * 24.0, "y": wy,
		"vx": (randf() - 0.5) * 24.0, "vy": -(36.0 + randf() * 48.0),
		"size": 3.0 + randf() * 5.0,
		"life": 0.5 + randf() * 0.4, "max_life": 0.9,
	})
	if _fire.size() > 200: _fire.pop_front()

# ── Update + draw particles each frame ────────────────────────────────────
func _update_draw_particles(delta: float) -> void:
	# Debris
	for i in range(_debris.size() - 1, -1, -1):
		var p : Dictionary = _debris[i]
		p["x"]   += p["vx"] * delta
		p["y"]   += p["vy"] * delta
		p["vy"]  += 600.0 * delta   # gravity
		p["vx"]  *= 0.98
		p["rot"] += p["rot_spd"] * delta
		p["life"] -= delta
		if p["life"] <= 0:
			_debris.remove_at(i); continue
		var a := clampf(p["life"] / p["max_life"], 0.0, 1.0)
		var col : Color = p["color"]; col.a = a
		var s   : float = p["size"] * a
		# Draw rotated square debris piece
		var c := cos(p["rot"]); var s2 := sin(p["rot"])
		var cx : float = p["x"]; var cy : float = p["y"]
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx + c*s - s2*s, cy + s2*s + c*s),
			Vector2(cx - c*s - s2*s, cy - s2*s + c*s),
			Vector2(cx - c*s + s2*s, cy - s2*s - c*s),
			Vector2(cx + c*s + s2*s, cy + s2*s - c*s),
		]), col)
	# Fire
	for i in range(_fire.size() - 1, -1, -1):
		var p : Dictionary = _fire[i]
		p["x"]   += p["vx"] * delta
		p["y"]   += p["vy"] * delta
		p["vy"]  *= 0.97
		p["life"] -= delta
		if p["life"] <= 0:
			_fire.remove_at(i); continue
		var a    := clampf(p["life"] / p["max_life"], 0.0, 1.0)
		var prog := 1.0 - a
		var g    := int(120 * (1.0 - prog))
		var core := Color(1.0, g / 255.0, 0.0, a)
		var halo := Color(1.0, g / 255.0, 0.0, a * 0.3)
		var r    : float = p["size"] * a
		draw_circle(Vector2(p["x"], p["y"]), r * 2.2, halo)
		draw_circle(Vector2(p["x"], p["y"]), r, core)

func _open_chest(b: Dictionary) -> void:
	if b.get("opened", false):
		GameManager.notify("Chest is empty!", Color(0.55, 0.27, 0.07)); return
	b["opened"] = true
	b["color"]  = Color(0.24, 0.16, 0.09)
	b["glow"]   = Color.TRANSPARENT

	# ── Pick random loot from pool (same table as JS) ─────────────
	var loot: Dictionary = Constants.LOOT_POOL[randi() % Constants.LOOT_POOL.size()].duplicate()
	HeroData.equipment[loot["slot"]] = loot
	HeroData.items_collected += 1
	HeroData.recalc_stats()

	# ── Auto-show inventory on first item (same as JS) ─────────────
	if HeroData.items_collected == 1 and hud_node and hud_node.has_method("show_inventory"):
		hud_node.show_inventory()

	# ── Heal to full if Amulet of Life (JS: if loot.bonusMaxHp Hero.hp = Hero.maxHp) ──
	if loot.get("bonus_max_hp", 0) > 0:
		HeroData.hp = HeroData.max_hp

	# ── Bonus gold 0-20 (same as JS) ─────────────────────────────
	var bonus_gold : int = randi() % 21
	if bonus_gold > 0:
		GameManager.add_gold(bonus_gold)
		_spawn_float_text("+%dG" % bonus_gold, Color(0.99, 0.83, 0.30), b["x"] + 20.0, Constants.GROUND_Y - 55.0)

	# ── Float text showing item stat bonus (JS: spawnFloatText(loot.desc)) ──
	var desc : String = loot.get("desc", "")
	if not desc.is_empty():
		_spawn_float_text(desc, Color(0.99, 0.83, 0.30), b["x"], Constants.GROUND_Y - 40.0)

	GameManager.notify("🎁 Found: %s!" % loot["name"], Color(0.29, 0.87, 0.50))

	# ── Spawn debris particles on chest open ─────────────────────
	var bc : Color = b.get("color", Color(0.55, 0.27, 0.07))
	for _di in range(4):
		_spawn_debris(b["x"] + (randf() - 0.5) * 30.0, Constants.GROUND_Y - 20.0, bc)

func _build_wall(b: Dictionary) -> void:
	if b.get("stage", 0) >= 3:
		GameManager.notify("Wall fully upgraded!", Color(0.49, 0.23, 0.93)); return
	var costs: Array[int] = [5, 10, 20]
	var stage: int = b.get("stage", 0)
	if not GameManager.spend_gold(costs[stage]):
		GameManager.notify("Need %dG!" % costs[stage], Color.RED); return
	b["stage"] += 1
	match b["stage"]:
		1: b["w"] = 90.0; b["h"] = 80.0;  b["hp"] = 100; b["max_hp"] = 100; b["built"] = true
		2: b["w"] = 70.0; b["h"] = 65.0;  b["hp"] = 200; b["max_hp"] = 200
		3: b["w"] = 90.0; b["h"] = 90.0;  b["hp"] = 300; b["max_hp"] = 300
	_create_wall_body(b)
	GameManager.add_upgrade(b["name"])
	GameManager.notify("✨ %s Lv%d built!" % [b["name"], b["stage"]], b.get("glow", Color.WHITE) as Color)

# Public alias dla HUD
func build_wall_from_hud(b: Dictionary) -> void:
	_build_wall(b)

func _upgrade_town(b: Dictionary) -> void:
	if b.get("stage", 1) >= 3:
		GameManager.notify("Citadel is max level!", Color(0.99, 0.94, 0.54)); return
	var cost: int = 50 if b["stage"] == 1 else 100
	if not GameManager.spend_gold(cost):
		GameManager.notify("Need %dG!" % cost, Color.RED); return
	b["stage"] += 1
	b["max_hp"] = [0, 1000, 2000, 3000][b["stage"]]
	b["hp"]     = b["max_hp"]
	GameManager.add_upgrade("Town Center Lv%d" % b["stage"])
	GameManager.notify("✨ Town Center Lv%d!" % b["stage"], b.get("glow", Color.YELLOW) as Color)

func _upgrade_farm(b: Dictionary) -> void:
	if b.get("stage", 1) >= 3:
		GameManager.notify("Farm is max level!", Color(0.29, 0.87, 0.50)); return
	var cost: int = (b["cost"] as int) if not b.get("built", false) else 100
	if not GameManager.spend_gold(cost):
		GameManager.notify("Need %dG!" % cost, Color.RED); return
	if not b.get("built", false):
		b["built"] = true
		GameManager.add_upgrade("Farm Built")
		_spawn_fisherman(b["x"], 1.0)
	else:
		b["stage"] += 1
		match b["stage"]:
			2: b["max_hp"] = 400; b["hp"] = 400; _spawn_fisherman(b["x"], -1.0)
			3:
				b["h"] = 77.0; b["w"] = 98.0; b["max_hp"] = 800; b["hp"] = 800
				_spawn_fisherman(b["x"] + 40, 1.0)
				_spawn_fisherman(b["x"] - 40, -1.0)
		GameManager.add_upgrade("Farm Lv%d" % b["stage"])
	GameManager.notify("✨ Farm upgraded!", b.get("glow", Color.GREEN) as Color)

func _build_generic(b: Dictionary) -> void:
	if b.get("built", false):
		GameManager.notify("Already built!", Color(0.29, 0.87, 0.50)); return
	if not GameManager.spend_gold(b["cost"]):
		GameManager.notify("Need %dG!" % b["cost"], Color.RED); return
	b["built"] = true
	GameManager.add_upgrade(b["name"])
	GameManager.notify("✨ %s built!" % b["name"], b.get("glow", Color.WHITE) as Color)

# ── Rekrutacja ────────────────────────────────
func spawn_archer(x: float, dir: int, wall_id: String = "") -> void:
	var a := Node2D.new()
	a.set_script(load("res://scripts/Archer.gd"))
	allies_node.add_child(a)
	a.setup(x, dir, wall_id, self)
	# Podłącz sygnał strzały
	if a.has_signal("arrow_fired"):
		a.arrow_fired.connect(_on_archer_arrow.bind(a))

func spawn_warrior(x: float, dir: int) -> void:
	var w := Node2D.new()
	w.set_script(load("res://scripts/Warrior.gd"))
	allies_node.add_child(w)
	w.setup(x, dir, self)

func _get_last_ally(group: String) -> Node:
	var last: Node = null
	for c in allies_node.get_children():
		if c.is_in_group(group):
			last = c
	return last

# ── Mury — fizyka ─────────────────────────────
func _create_wall_body(b: Dictionary) -> void:
	var wall_id : String = b["id"]
	if wall_id in wall_bodies:
		wall_bodies[wall_id].queue_free()
		wall_bodies.erase(wall_id)
	if not b.get("built", false) or b.get("stage", 0) == 0: return

	var body  := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect  := RectangleShape2D.new()
	rect.size  = Vector2(b["w"], b["h"])
	shape.shape = rect
	body.add_child(shape)
	body.position = Vector2(b["x"], Constants.GROUND_Y - b["h"] * 0.5)
	body.collision_layer = 8   # layer 4 = building
	body.collision_mask  = 4   # mask layer 3 = enemy
	add_child(body)
	wall_bodies[wall_id] = body

func rebuild_wall_physics(b: Dictionary) -> void:
	_create_wall_body(b)

# ── Dungeon ────────────────────────────────────
func _check_dungeon_portals() -> void:
	# Pokaż prompt gdy gracz jest blisko portalu lochu
	if not hero_node: return
	var px := hero_node.position.x
	for wx in [Constants.DUNGEON_PORTAL_LEFT, Constants.DUNGEON_PORTAL_RIGHT]:
		if abs(px - wx) < Constants.DUNGEON_PORTAL_RADIUS + 40.0:
			if hud_node and hud_node.has_method("show_build_prompt_text"):
				hud_node.show_build_prompt_text("🌀 Underworld Portal", "SPACE to enter")

func enter_dungeon(from_portal_x: float) -> void:
	_return_portal_x = from_portal_x
	_is_dungeon = true
	GameManager.set_scene("dungeon")
	# Wyczyść wrogów overworld
	for e in enemies_node.get_children():
		e.queue_free()
	dungeon_node.enter(hero_node)

func exit_dungeon() -> void:
	_is_dungeon = false
	GameManager.set_scene("overworld")

	# ── Rescue alive archers/warriors from dungeon (JS: SceneManager.exit rescues them) ──
	var i: int = 0
	for a_data in dungeon_node.archers:
		if a_data.get("hp", 0) > 0:
			var spawn_x: float = _return_portal_x + (40.0 if i % 2 == 0 else -40.0) + float(i) * 10.0
			spawn_archer(spawn_x, int(a_data.get("dir", -1)), "")
			var spawned := _get_last_ally("archers")
			if spawned:
				spawned.hp = int(a_data.get("hp", spawned.hp))
		i += 1
	for w_data in dungeon_node.warriors:
		if w_data.get("hp", 0) > 0:
			var spawn_x: float = _return_portal_x + (30.0 if i % 2 == 0 else -30.0) + float(i) * 10.0
			spawn_warrior(spawn_x, int(w_data.get("dir", -1)))
			var spawned := _get_last_ally("warriors")
			if spawned:
				spawned.hp = int(w_data.get("hp", spawned.hp))
		i += 1

	# Return hero to the portal they entered from
	hero_node.position = Vector2(_return_portal_x, Constants.GROUND_Y - 40)
	hero_node.velocity = Vector2.ZERO
	dungeon_node.exit()
	GameManager.notify("☀️ Back in the overworld!", Color(0.99, 0.83, 0.30))

# ── Sojusznik wchodzi do lochu ─────────────────
func ally_enter_dungeon(ally_node: Node2D, ally_type: String) -> void:
	var data := {"x": 200.0 if ally_type == "archer" else 220.0}
	if ally_type == "archer":
		data["hp"]       = ally_node.hp
		data["max_hp"]   = ally_node.max_hp
		data["dir"]      = ally_node.facing_dir
		data["walk_cycle"] = 0.0
		data["draw_timer"] = 0.0
		dungeon_node.archers.append(data)
		GameManager.notify("🚪 Archer entered the Dungeon!", Color(0.66, 0.33, 0.97))
	elif ally_type == "warrior":
		data["hp"]       = ally_node.hp
		data["max_hp"]   = ally_node.max_hp
		data["dir"]      = ally_node.facing_dir
		data["walk_cycle"] = 0.0
		dungeon_node.warriors.append(data)
		GameManager.notify("⚔️ Warrior entered the Dungeon!", Color(0.96, 0.62, 0.04))
	ally_node.queue_free()

# ── Hero attack callback ───────────────────────
func _on_hero_attacked(hit_rect: Rect2, direction: float) -> void:
	if _is_dungeon:
		dungeon_node.hero_attack(hit_rect, direction)
		return
	# Overworld attack
	for e_node in enemies_node.get_children():
		if not e_node.is_in_group("enemies"): continue
		var e_rect := Rect2(e_node.position.x - 12, e_node.position.y - 20, 24, 40)
		if hit_rect.intersects(e_rect):
			_spawn_float_text("-%d" % HeroData.damage, Color(1.0, 0.42, 0.42), e_node.position.x, e_node.position.y - 25.0)
			e_node.receive_hit(HeroData.damage, Vector2(direction * 180, -60))
			break

# ── Sygnały zewnętrzne ────────────────────────
func _on_night_started(night: int, blood: bool) -> void:
	if blood:
		GameManager.notify("🩸 Blood Moon! The Abyss Overflows!", Color(1.0, 0.0, 0.0))
	else:
		GameManager.notify("🌑 Night %d — The Abyss Approaches!" % night, Color(0.87, 0.69, 1.0))
	# Ciemny neon nocny
	_update_canvas_modulate(true)

func _on_day_started(day: int) -> void:
	GameManager.notify("☀️ Dawn %d — The Abyss Recedes" % day, Color(1.0, 0.89, 0.48))
	# Jasna paleta dzienna
	_update_canvas_modulate(false)

func _on_notification(msg: String, color: Color) -> void:
	if hud_node and hud_node.has_method("show_notification"):
		hud_node.show_notification(msg, color)

func _on_hero_died() -> void:
	if hud_node and hud_node.has_method("show_game_over"):
		hud_node.show_game_over()

func _on_hero_leveled(new_level: int) -> void:
	GameManager.notify("⬆️ LEVEL UP! Now Lv.%d — DMG %d" % [new_level, HeroData.damage], Color(0.75, 0.51, 0.99))

# ── Wczytywanie zapisu ────────────────────────
func on_game_loaded(data: Dictionary) -> void:
	# Odbuduj fizykę murów
	for b in GameManager.buildings:
		if b["type"] == "wall" and b.get("built", false):
			_create_wall_body(b)

	# Przywróć sojuszników
	var allies_data : Dictionary = data.get("allies", {})
	for a_data in allies_data.get("archers", []):
		spawn_archer(float(a_data["x"]), int(a_data["dir"]), str(a_data.get("assigned_wall_id", "")))
	for w_data in allies_data.get("warriors", []):
		spawn_warrior(float(w_data["x"]), int(w_data["dir"]))

	# Przywróć pozycję bohatera
	var pos : Dictionary = data.get("hero_pos", {"x": 0.0, "y": Constants.GROUND_Y - 30.0})
	hero_node.position = Vector2(float(pos["x"]), float(pos["y"]))

	# Dodaj farmera do aktywnych farm
	fishermen.clear()
	for b in GameManager.buildings:
		if b["type"] == "farm" and b.get("built", false):
			_spawn_fisherman(b["x"], 1.0)
			if b.get("stage", 1) >= 2: _spawn_fisherman(b["x"], -1.0)

# ══════════════════════════════════════════════════════════════════
#  NEON ENVIRONMENT — inicjalizacja i aktualizacja
# ══════════════════════════════════════════════════════════════════

func _setup_neon_env() -> void:
	# Ustaw początkowy kolor CanvasModulate (dzień)
	_update_canvas_modulate(false)
	# Ustaw WaterRect rozmiar
	if water_rect:
		water_rect.position.y = Constants.GROUND_Y
		water_rect.size = Vector2(get_viewport_rect().size.x, 32.0)
		water_rect.position.x = -get_viewport_rect().size.x * 0.5
	# Wygeneruj teksturę gradientową dla PointLight2D
	if player_light:
		player_light.texture = _make_light_texture(256)
		player_light.energy = 0.55
		player_light.texture_scale = 2.8

func _make_light_texture(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var cx : float = float(size) * 0.5
	var cy : float = float(size) * 0.5
	var rmax : float = float(size) * 0.5
	for y in range(size):
		for x in range(size):
			var dx : float = float(x) - cx
			var dy : float = float(y) - cy
			var dist : float = sqrt(dx * dx + dy * dy) / rmax
			var a : float = clamp(1.0 - dist * dist, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)

func _update_canvas_modulate(is_night: bool) -> void:
	if not canvas_modulate: return
	var e : float = DayNight.elapsed
	var day_s : float = Constants.DAY_S
	if is_night:
		# Nocna progresja: zmierzch → głęboka noc → przed świtem
		var night_frac : float = clamp((e - day_s) / (Constants.CYCLE_S - day_s), 0.0, 1.0)
		if night_frac < 0.15:
			# Wczesna noc: ciemno-fioletowy
			canvas_modulate.color = Color(0.15, 0.06, 0.30).lerp(Color(0.10, 0.04, 0.22), night_frac / 0.15)
		elif night_frac < 0.80:
			# Głęboka noc: bardzo ciemny indygo
			canvas_modulate.color = Color(0.10, 0.04, 0.22)
		else:
			# Przed świtem: delikatny fioletowo-niebieski
			canvas_modulate.color = Color(0.10, 0.04, 0.22).lerp(Color(0.55, 0.38, 0.70), (night_frac - 0.80) / 0.20)
	else:
		# Dzień: świt → południe → zmierzch
		if e < day_s * 0.12:
			# Świt: ciepły pomarańcz
			var p : float = e / (day_s * 0.12)
			canvas_modulate.color = Color(0.55, 0.38, 0.70).lerp(Color(0.95, 0.75, 0.58), p)
		elif e < day_s * 0.30:
			# Ranek: złoty
			var p : float = (e - day_s * 0.12) / (day_s * 0.18)
			canvas_modulate.color = Color(0.95, 0.75, 0.58).lerp(Color(1.00, 0.97, 0.95), p)
		elif e < day_s * 0.75:
			# Dzień: jasny chłodny biały
			canvas_modulate.color = Color(1.00, 0.97, 0.95)
		else:
			# Zmierzch: różowo-fioletowy
			var p : float = (e - day_s * 0.75) / (day_s * 0.25)
			canvas_modulate.color = Color(1.00, 0.97, 0.95).lerp(Color(0.75, 0.45, 0.68), p)
	# Blood moon: nałóż czerwony tint nocą (jak w JS — czerwona mgła podczas blood moon)
	if GameManager.is_blood_moon and is_night:
		var base := canvas_modulate.color
		canvas_modulate.color = base.lerp(Color(0.55, 0.05, 0.05), 0.35)

# ── ArcaneSpire — system cząsteczek (1:1 z JS ArcaneSpire.update/draw) ───────
func _update_spire_particles(delta: float) -> void:
	# Znajdź Town Center
	var tc : Dictionary = {}
	for b in GameManager.buildings:
		if b.get("id","") == "town_center":
			tc = b; break
	if tc.is_empty(): return

	var stage : int   = tc.get("stage", 1)
	var tx    : float = tc.get("x", 0.0)
	var GY    := Constants.GROUND_Y
	var fire_x : float = tx + 60.0   # po prawej (ognisko / eternal flame)
	var water_x: float = tx - 60.0   # po lewej (fontanna)

	# Obróć Apex Crystal
	if stage == 3:
		_apex_angle = fmod(_apex_angle + 0.02 * delta * 60.0, TAU)

	_spire_timer += delta * 60.0  # normalize do 60fps jak w JS

	# ── Spawning cząsteczek wg stage ──────────────────────────────────────
	if stage == 1:
		# Iskry ogniska — pomarańczowe (JS: every 6 frames)
		if fmod(_spire_timer, 6.0) < delta * 60.0:
			_spire_emit(fire_x + (randf()-0.5)*15.0, GY-5.0, Color(0.97,0.60,0.09), 1.0, 0.4, false)

	elif stage == 2:
		# Iskry ogniska (JS: every 5 frames)
		if fmod(_spire_timer, 5.0) < delta * 60.0:
			_spire_emit(fire_x + (randf()-0.5)*18.0, GY-5.0, Color(0.97,0.60,0.09), 1.2, 0.5, false)
		# Krople fontanny — niebieskie (JS: every 4 frames, vy_init=-1 → up)
		if fmod(_spire_timer, 4.0) < delta * 60.0:
			_spire_emit(water_x + (randf()-0.5)*10.0, GY-20.0, Color(0.22,0.74,0.97), 1.5, 0.8, true)

	elif stage == 3:
		# Eternal Flame — biały/cyjanowy (JS: every 2 frames)
		if fmod(_spire_timer, 2.0) < delta * 60.0:
			var col3 := Color(1.0,1.0,1.0) if randf() < 0.5 else Color(0.40,0.91,0.97)
			_spire_emit(fire_x + (randf()-0.5)*25.0, GY-10.0, col3, 2.0, 0.8, false)
		# Wielka fontanna (JS: every 2 frames, vy_init=-1.5)
		if fmod(_spire_timer, 2.0) < delta * 60.0:
			_spire_emit(water_x + (randf()-0.5)*20.0, GY-30.0, Color(0.05,0.65,0.91), 2.0, 1.2, true)
		# Neon dust z podstawy TC (JS: every 4 frames)
		if fmod(_spire_timer, 4.0) < delta * 60.0:
			var dcol := Color(0.22,0.74,0.97) if randf() < 0.5 else Color(0.88,0.95,0.99)
			_spire_emit(tx + (randf()-0.5)*60.0, GY-40.0, dcol, 0.5, 0.8, false)

	# ── Aktualizacja pozycji + starzenie ──────────────────────────────────
	for i in range(_spire_particles.size()-1, -1, -1):
		var p : Dictionary = _spire_particles[i]
		p["x"]    += p["vx"] * delta * 60.0
		p["y"]    += p["vy"] * delta * 60.0
		if p["vy_g"]:  p["vy"] += 0.05 * delta * 60.0  # grawitacja dla wody
		p["life"] -= delta
		if p["life"] <= 0.0:
			_spire_particles.remove_at(i)

# Pomocnicza — tworzy jedną cząsteczkę (1:1 z JS createParticle)
func _spire_emit(x: float, y: float, col: Color, speed: float, size_mult: float, water: bool) -> void:
	var vy_init : float = -0.5 if not water else -1.0
	if water: vy_init = -1.5
	_spire_particles.append({
		"x":     x,
		"y":     y,
		"vx":    (randf()-0.5) * speed,
		"vy":    vy_init - randf() * speed,
		"vy_g":  water,
		"size":  (2.0 + randf()*2.0) * size_mult,
		"color": col,
		"life":  (60.0 + randf()*40.0) / 60.0,  # w sekundach
		"max_life": 100.0 / 60.0,
	})
	# Cap jak JS
	if _spire_particles.size() > 200:
		_spire_particles.pop_front()

# ── Rysowanie cząsteczek Spire ────────────────────────────────────────────────
func _draw_spire_particles(cam_x: float) -> void:
	if _spire_particles.is_empty(): return
	var W   := get_viewport_rect().size.x
	var lx  := cam_x - W * 0.6
	var rx  := cam_x + W * 0.6
	for p in _spire_particles:
		var sx : float = p["x"] - cam_x + get_viewport_rect().size.x * 0.5
		if sx < -20.0 or sx > W + 20.0: continue
		var life_frac : float = clamp(p["life"] / p["max_life"], 0.0, 1.0)
		var alpha     : float = life_frac * 0.9
		var col : Color = p["color"]; col.a = alpha
		draw_circle(Vector2(sx, p["y"]), p["size"] * life_frac, col)
