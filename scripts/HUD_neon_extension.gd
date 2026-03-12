## scripts/HUD.gd (fragment — uzupełnienie istniejącego HUD.gd)
## ══════════════════════════════════════════════════════════════════
##  Rozszerzenie HUD.gd o styl neonowy.
##  WKLEJ te metody do istniejącego HUD.gd lub używaj jako odniesienie.
##
##  Wymaga: UITheme.gd jako Autoload "UITheme"
##           NeonEnvironment.gd jako Autoload "NeonEnv"
## ══════════════════════════════════════════════════════════════════

extends CanvasLayer

# Istniejące węzły HUD (już są w Twojej scenie)
@onready var build_prompt   : Panel   = $BuildPrompt
@onready var shop_menu      : Panel   = $ShopMenu
@onready var barracks_menu  : Panel   = $BarracksMenu
@onready var forge_menu     : Panel   = $ForgeMenu
@onready var wall_menu      : Panel   = $WallMenu
@onready var notif_label    : Label   = $Notification
@onready var gameover_panel : Panel   = $GameOver
@onready var top_bar        : Panel   = $TopBar    # pasek u góry z HP/XP/Gold

func _ready() -> void:
	_apply_neon_styles()

func _apply_neon_styles() -> void:
	## Nakłada neonowe style na wszystkie panele HUD
	if not Engine.has_singleton("UITheme"):
		push_warning("HUD: brak autoloadu UITheme")
		return
	
	# Build prompt (Town Center / Wall itd.) → złoty
	if build_prompt:
		UITheme.apply_to_panel(build_prompt, "gold", 12)
	
	# Shop menu → pomarańczowy
	if shop_menu:
		UITheme.apply_to_panel(shop_menu, "orange", 10)
		_style_buttons_in(shop_menu, "orange")
	
	# Barracks → czerwony
	if barracks_menu:
		UITheme.apply_to_panel(barracks_menu, "red", 10)
		_style_buttons_in(barracks_menu, "red")
	
	# Forge → fioletowy
	if forge_menu:
		UITheme.apply_to_panel(forge_menu, "purple", 10)
		_style_buttons_in(forge_menu, "purple")
	
	# Wall menu → niebieski
	if wall_menu:
		UITheme.apply_to_panel(wall_menu, "blue", 10)
		_style_buttons_in(wall_menu, "blue")
	
	# Pasek górny → subtelny fiolet
	if top_bar:
		UITheme.apply_to_panel(top_bar, "purple", 0)
	
	# Game over panel → czerwony duży
	if gameover_panel:
		UITheme.apply_to_panel(gameover_panel, "red", 16)

func _style_buttons_in(parent: Control, style: String) -> void:
	## Stylizuje wszystkie przyciski w danym panelu
	for child in parent.get_children():
		if child is Button:
			UITheme.apply_to_button(child as Button, style)
		elif child is Container:
			for sub in child.get_children():
				if sub is Button:
					UITheme.apply_to_button(sub as Button, style)

# ══════════════════════════════════════════════════════════════════
#  Istniejące metody HUD — tutaj tylko przykładowe sygnatury
#  (uzupełnij na podstawie swojego aktualnego HUD.gd)
# ══════════════════════════════════════════════════════════════════

func show_build_prompt(building: Dictionary) -> void:
	if not build_prompt: return
	build_prompt.visible = true
	# Ustaw tekst (dostosuj do swoich węzłów Label wewnątrz panelu)
	var lbl := build_prompt.get_node_or_null("Label")
	if lbl and lbl is Label:
		var name_str : String = building.get("name", "?")
		var cost_int : int    = building.get("cost", 0)
		var stage    : int    = building.get("stage", 0)
		if building.get("built", false):
			(lbl as Label).text = "⭐ %s Lv%d\nUpgrade: %dG — SPACE" % [name_str, stage, cost_int]
		else:
			(lbl as Label).text = "🔨 Build: %s\nCost: %dG — SPACE" % [name_str, cost_int]

func hide_build_prompt() -> void:
	if build_prompt: build_prompt.visible = false

func show_notification(msg: String, color: Color) -> void:
	if not notif_label: return
	notif_label.text             = msg
	notif_label.add_theme_color_override("font_color", color)
	notif_label.visible          = true
	# Auto-ukryj po 2.5s
	var tween := create_tween()
	tween.tween_interval(2.5)
	tween.tween_callback(notif_label.hide)

func show_wall_menu(b: Dictionary) -> void:
	if wall_menu: wall_menu.visible = true
	# Przekaż dane budynku do menu (dostosuj do swoich węzłów)

func show_barracks_menu() -> void:
	if barracks_menu: barracks_menu.visible = true

func show_forge_menu() -> void:
	if forge_menu: forge_menu.visible = true

func show_smith_menu() -> void:
	pass  # dodaj smith panel jeśli masz

func show_game_over() -> void:
	if gameover_panel: gameover_panel.visible = true
