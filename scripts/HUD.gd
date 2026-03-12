## scripts/HUD.gd
## UI/HUD — paski HP/XP/Stamina, złoto, powiadomienia, menu budowania, ekwipunek
extends CanvasLayer

@onready var gold_label    : Label         = $TopBar/HBox/GoldLabel
@onready var day_label     : Label         = $TopBar/HBox/DayLabel
@onready var biome_label   : Label         = $TopBar/HBox/BiomeLabel
@onready var built_label   : Label         = $TopBar/HBox/BuiltLabel
@onready var level_label_top: Label        = $TopBar/HBox/LevelLabel
@onready var xp_bar_top    : ProgressBar   = $TopBar/HBox/XPBox/XPBar
@onready var lw_bar        : ProgressBar   = $TopBar/HBox/LeftWallBox/LWBar
@onready var lw_text       : Label         = $TopBar/HBox/LeftWallBox/LWText
@onready var tc_bar        : ProgressBar   = $TopBar/HBox/TCBox/TCBar
@onready var tc_text       : Label         = $TopBar/HBox/TCBox/TCText
@onready var rw_bar        : ProgressBar   = $TopBar/HBox/RightWallBox/RWBar
@onready var rw_text       : Label         = $TopBar/HBox/RightWallBox/RWText
@onready var hp_bar        : ProgressBar   = $HeroStats/Inner/HPBar
@onready var xp_bar        : ProgressBar   = $HeroStats/Inner/XPBar
@onready var stamina_bar   : ProgressBar   = $HeroStats/Inner/StaminaBar
@onready var level_label   : Label         = $HeroStats/Inner/LevelLabel
@onready var build_prompt  : Panel         = $BuildPrompt
@onready var prompt_title  : Label         = $BuildPrompt/VBox/PromptTitle
@onready var prompt_desc   : RichTextLabel = $BuildPrompt/VBox/PromptDesc
@onready var notif_label   : Label         = $Notification
@onready var day_banner    : Label         = $DayBanner
@onready var game_over     : Control       = $GameOver
@onready var barracks_menu : Panel         = $BarracksMenu
@onready var forge_menu    : Panel         = $ForgeMenu
@onready var wall_menu     : Panel         = $WallMenu
@onready var smith_menu    : Panel         = $SmithMenu
@onready var shop_menu     : Panel         = $ShopMenu
@onready var inventory_panel: Panel        = $InventoryPanel

var _notif_timer   : float = 0.0
var _banner_timer  : float = 0.0
var _current_wall_id : String = ""
var _teleport_label : Label = null  # wskaźnik stanu budynku Teleport

func _ready() -> void:
	GameManager.gold_changed.connect(_on_gold_changed)
	GameManager.notification.connect(show_notification)
	HeroData.stats_changed.connect(_on_stats_changed)
	HeroData.died.connect(show_game_over)
	DayNight.night_started.connect(_on_night_started)
	DayNight.day_started.connect(_on_day_started)
	if game_over:
		var r: Node = game_over.get_node_or_null("VBox/RestartBtn")
		if r: r.pressed.connect(_on_restart)
	_connect_menu_buttons()
	_on_stats_changed()
	_on_gold_changed(GameManager.gold_count)
	_hide_all_menus()
	if inventory_panel: inventory_panel.visible = false
	# Ukryj dolny panel statystyk bohatera (HP/XP/Stamina) — duplikują TopBar
	var hero_stats := get_node_or_null("HeroStats")
	if hero_stats: hero_stats.visible = false
	# Dodaj wskaźnik Teleportu do TopBar (JS: updateTeleportHud)
	var hbox := get_node_or_null("TopBar/HBox")
	if hbox:
		_teleport_label = Label.new()
		_teleport_label.text = "🌀 [T]"
		_teleport_label.modulate = Color(0.51, 0.55, 0.97, 0.35)
		_teleport_label.add_theme_font_size_override("font_size", 13)
		hbox.add_child(_teleport_label)

func _connect_menu_buttons() -> void:
	for mn in ["BarracksMenu","ForgeMenu","WallMenu","SmithMenu","ShopMenu"]:
		var m := get_node_or_null(mn)
		if not m: continue
		var cb: Node = m.get_node_or_null("VBox/CloseBtn")
		if cb: cb.pressed.connect(func(): _hide_all_menus())
	if barracks_menu:
		_btn_connect(barracks_menu,"VBox/RecruitArcher", _on_recruit_archer)
		_btn_connect(barracks_menu,"VBox/RecruitWarrior",_on_recruit_warrior)
		_btn_connect(barracks_menu,"VBox/AssignLeft", func(): _on_assign_archer("left_wall"))
		_btn_connect(barracks_menu,"VBox/AssignRight",func(): _on_assign_archer("right_wall"))
	if forge_menu:
		_btn_connect(forge_menu,"VBox/UpgArcher",  _on_upgrade_archers)
		_btn_connect(forge_menu,"VBox/UpgWarrior", _on_upgrade_warriors)
	if wall_menu:
		_btn_connect(wall_menu,"VBox/AssignArcher", _on_wall_assign_archer)
		_btn_connect(wall_menu,"VBox/UpgradeWall",  _on_wall_upgrade)
	if shop_menu:
		_btn_connect(shop_menu, "VBox/BtnSword", func(): _on_buy_weapon("Silver Sword", 20, 35, "short"))
		_btn_connect(shop_menu, "VBox/BtnSpear", func(): _on_buy_weapon("Iron Spear",   20, 20, "medium"))
		_btn_connect(shop_menu, "VBox/BtnBow",   func(): _on_buy_weapon("Ranger Bow",   20, 10, "ranged"))

func _btn_connect(panel: Panel, path: String, cb: Callable) -> void:
	var btn: Node = panel.get_node_or_null(path)
	if btn: btn.pressed.connect(cb)

func _hide_all_menus() -> void:
	for mn in ["BarracksMenu","ForgeMenu","WallMenu","SmithMenu","ShopMenu"]:
		var m := get_node_or_null(mn)
		if m: m.visible = false

func _process(delta: float) -> void:
	if _notif_timer > 0.0:
		_notif_timer -= delta
		if _notif_timer <= 0.0 and notif_label: notif_label.visible = false
	if _banner_timer > 0.0:
		_banner_timer -= delta
		if _banner_timer <= 0.0 and day_banner: day_banner.visible = false
	if day_label:
		day_label.text = ("Night %d" if DayNight.is_night else "Day %d") % DayNight.day_count
	if biome_label:
		var hero: Node2D = get_tree().get_first_node_in_group("hero") as Node2D
		if hero:
			var ax: float = absf(hero.position.x)
			if ax > Constants.BIOME_FOREST_END:
				biome_label.text = "🌋 Wasteland"
				biome_label.modulate = Color(0.9,0.35,0.1)
			elif ax > Constants.BIOME_KINGDOM_END:
				biome_label.text = "🌲 Forest"
				biome_label.modulate = Color(0.3,0.9,0.4)
			else:
				biome_label.text = "🏰 Kingdom"
				biome_label.modulate = Color(0.85,0.7,1.0)
	if stamina_bar:
		stamina_bar.max_value = HeroData.max_stamina
		stamina_bar.value     = HeroData.stamina
	_check_menu_proximity()
	if Input.is_action_just_pressed("inventory"):
		if inventory_panel:
			inventory_panel.visible = not inventory_panel.visible
			if inventory_panel.visible: _refresh_inventory()
	if Input.is_key_pressed(KEY_ESCAPE):
		_hide_all_menus()
		if inventory_panel: inventory_panel.visible = false
	# Aktualizuj paski murów co każdy frame
	_update_wall_tc_bars()
	# Aktualizuj wskaźnik teleportu (JS: updateTeleportHud)
	if _teleport_label:
		var tp_built := false
		for b in GameManager.buildings:
			if b.get("id","") == "teleport" and b.get("built", false):
				tp_built = true; break
		_teleport_label.modulate = Color(0.51, 0.55, 0.97, 1.0) if tp_built else Color(0.51, 0.55, 0.97, 0.35)

func _on_stats_changed() -> void:
	if hp_bar:     hp_bar.max_value     = HeroData.max_hp;  hp_bar.value     = HeroData.hp
	if xp_bar:     xp_bar.max_value     = HeroData.xp_cap;  xp_bar.value     = HeroData.xp
	if level_label: level_label.text    = "LV %d" % HeroData.level
	if xp_bar_top:  xp_bar_top.max_value = HeroData.xp_cap; xp_bar_top.value = HeroData.xp
	if level_label_top: level_label_top.text = "LVL %d" % HeroData.level
	_update_wall_tc_bars()
	# Zawsze odśwież ekwipunek gdy statystyki się zmieniają (np. po otwarciu skrzynki)
	_refresh_inventory()

func _update_wall_tc_bars() -> void:
	var lw_hp := 0; var lw_max := 100
	var rw_hp := 0; var rw_max := 100
	var tc_hp := 0; var tc_max := 1000
	var built_count := 0
	for b in GameManager.buildings:
		var btype : String = b.get("type", "")
		var bid   : String = b.get("id", "")
		var bcost : int    = b.get("cost", 0)
		if b.get("built", false) and btype != "chest" and bid != "town_center" and bcost > 0:
			built_count += 1
		if b["id"] == "left_wall":
			lw_hp = b.get("hp", 0); lw_max = b.get("max_hp", 100)
		elif b["id"] == "right_wall":
			rw_hp = b.get("hp", 0); rw_max = b.get("max_hp", 100)
		elif b["id"] == "town_center":
			tc_hp = b.get("hp", 0); tc_max = b.get("max_hp", 1000)
	if lw_bar:  lw_bar.max_value = lw_max; lw_bar.value = lw_hp
	if lw_text: lw_text.text = "%d/%d" % [lw_hp, lw_max]
	if rw_bar:  rw_bar.max_value = rw_max; rw_bar.value = rw_hp
	if rw_text: rw_text.text = "%d/%d" % [rw_hp, rw_max]
	if tc_bar:  tc_bar.max_value = tc_max; tc_bar.value = tc_hp
	if tc_text: tc_text.text = "%d/%d" % [tc_hp, tc_max]
	if built_label: built_label.text = "🏗️ %d" % built_count

func _on_gold_changed(amount: int) -> void:
	if gold_label: gold_label.text = "💰 %d" % amount

func show_notification(msg: String, color: Color = Color.WHITE) -> void:
	if not notif_label: return
	notif_label.text = msg; notif_label.modulate = color
	notif_label.visible = true; _notif_timer = 2.5

func _on_night_started(night: int, blood: bool) -> void:
	if not day_banner: return
	if blood: day_banner.text = "🩸 BLOOD MOON — Night %d" % night; day_banner.modulate = Color.RED
	else: day_banner.text = "🌑 Night %d — The Abyss Will Claim You!" % night; day_banner.modulate = Color(0.87,0.69,1.0)
	day_banner.visible = true; _banner_timer = 3.5

func _on_day_started(day: int) -> void:
	if not day_banner: return
	day_banner.text = "☀️ Dawn %d — The Abyss Recedes" % day
	day_banner.modulate = Color(1.0,0.89,0.48); day_banner.visible = true; _banner_timer = 3.5

func show_build_prompt(b: Dictionary) -> void:
	if not build_prompt: return
	for mn in ["BarracksMenu","ForgeMenu","WallMenu","SmithMenu"]:
		var m := get_node_or_null(mn)
		if m and m.visible: build_prompt.visible = false; return
	build_prompt.visible = true
	var title_str : String = b.get("name","Building")
	var desc_str  := ""
	match b.get("type",""):
		"chest":
			if b.get("opened", false):
				title_str = "📦 " + title_str
				desc_str  = "[color=gray]Empty...[/color]"
			else:
				title_str = "🎁 " + title_str
				desc_str  = "SPACE to open"
		"wall":
			var s: int = b.get("stage", 0)
			var cs: Array = [5, 10, 20]
			if s >= 3:
				title_str = "✅ " + title_str + " (Max)"
				desc_str  = "SPACE to configure"
			elif s == 0:
				desc_str = "Build: [color=yellow]%dG[/color] — SPACE" % cs[0]
			else:
				title_str += " Lv%d" % s
				desc_str   = "SPACE — Upgrade: [color=yellow]%dG[/color]" % cs[s]
		"town":
			var s: int = b.get("stage", 1)
			if s >= 3:
				title_str = "🏰 Citadel (Max)"
				desc_str  = "[color=green]Max![/color]"
			elif s == 2:
				title_str = "🏠 Outpost Lv2"
				desc_str  = "Upgrade to Citadel: [color=yellow]100G[/color] — SPACE"
			else:
				title_str = "⛺ Town Center Lv1"
				desc_str  = "Upgrade to Outpost: [color=yellow]50G[/color] — SPACE"
		"farm":
			if not b.get("built", false):
				title_str = "🌾 " + title_str
				desc_str  = "Build: [color=yellow]%dG[/color] — SPACE" % b.get("cost", 50)
			elif b.get("stage", 1) >= 3:
				title_str = "✅ " + title_str + " (Max)"
				desc_str  = "[color=green]Farm is max![/color]"
			else:
				title_str = "🌾 " + title_str + " Lv%d" % b.get("stage", 1)
				desc_str  = "Upgrade: [color=yellow]100G[/color] — SPACE"
		"barracks":
			if b.get("built", false):
				title_str = "🛡️ " + title_str
				desc_str  = "Open Recruitment — SPACE"
			else:
				desc_str = "Build: [color=yellow]%dG[/color] — SPACE" % b.get("cost", 30)
		"forge":
			if b.get("built", false):
				title_str = "🔮 " + title_str
				desc_str  = "Open Arcane Item Shop — SPACE"
			else:
				desc_str = "Build: [color=yellow]%dG[/color] — SPACE" % b.get("cost", 35)
		"smith":
			if b.get("built", false):
				title_str = "🔨 " + title_str
				desc_str  = "Open Unit Upgrade Forge — SPACE"
			else:
				desc_str = "Build: [color=yellow]%dG[/color] — SPACE" % b.get("cost", 20)
		"shop":
			if b.get("built", false):
				title_str = "⚔️ " + title_str
				desc_str  = "Open Weapon Shop — SPACE"
			else:
				desc_str = "Build: [color=yellow]%dG[/color] — SPACE" % b.get("cost", 20)
		"teleport":
			if b.get("built", false):
				title_str = "🌀 " + title_str
				desc_str  = "Press [T] to teleport here"
			else:
				desc_str = "Build: [color=yellow]%dG[/color] — SPACE" % b.get("cost", 50)
		_:
			if b.get("built", false):
				desc_str = "[color=green]Already built![/color]"
			else:
				desc_str = "Build: [color=yellow]%dG[/color] — SPACE" % b.get("cost", 0)
	if prompt_title: prompt_title.text = title_str
	if prompt_desc:  prompt_desc.text  = "[center]"+desc_str+"[/center]"

func hide_build_prompt() -> void:
	if build_prompt: build_prompt.visible = false

func show_build_prompt_text(title: String, desc: String) -> void:
	if not build_prompt: return
	build_prompt.visible = true
	if prompt_title: prompt_title.text = title
	if prompt_desc:  prompt_desc.text  = "[center]" + desc + "[/center]"

# ── Barracks ──────────────────────────────────
func show_barracks_menu() -> void:
	_hide_all_menus()
	if not barracks_menu: return
	_update_barracks_ui(); barracks_menu.visible = true

func _update_barracks_ui() -> void:
	if not barracks_menu: return
	var ac_lbl: Node = barracks_menu.get_node_or_null("VBox/ArcherCount")
	var wc_lbl: Node = barracks_menu.get_node_or_null("VBox/WarriorCount")
	var world := get_parent()
	var archers:=0; var warriors:=0
	if world:
		var an: Node = world.get_node_or_null("Allies")
		if an:
			for c in an.get_children():
				if c.is_in_group("archers"): archers+=1
				elif c.is_in_group("warriors"): warriors+=1
	if ac_lbl: ac_lbl.text="Archers: %d"%archers
	if wc_lbl: wc_lbl.text="Warriors: %d"%warriors

func _on_recruit_archer() -> void:
	if not GameManager.spend_gold(10): show_notification("Need 10G!",Color.RED); return
	var b:=GameManager.get_building("barracks")
	if b.is_empty(): return
	var w:=get_parent()
	if w and w.has_method("spawn_archer"): w.spawn_archer(b["x"],-1,"")
	show_notification("🏹 Archer recruited!",Color(0.66,0.33,0.97))
	_update_barracks_ui()

func _on_recruit_warrior() -> void:
	if not GameManager.spend_gold(10): show_notification("Need 10G!",Color.RED); return
	var b:=GameManager.get_building("barracks")
	if b.is_empty(): return
	var w:=get_parent()
	if w and w.has_method("spawn_warrior"): w.spawn_warrior(b["x"],-1)
	show_notification("⚔️ Warrior recruited!",Color(0.96,0.62,0.04))
	_update_barracks_ui()

func _on_assign_archer(wall_id: String) -> void:
	var wall:=GameManager.get_building(wall_id)
	if wall.is_empty() or not wall.get("built",false): show_notification("Build that wall first!",Color.RED); return
	var stage:int=wall.get("stage",0)
	var max_a:=8 if stage>=3 else (4 if stage>=2 else 2)
	var world:=get_parent()
	if not world: return
	var an: Node = world.get_node_or_null("Allies")
	if not an: return
	var on_wall: int = 0
	var free_archer: Node = null
	var min_dist: float = INF
	for c in an.get_children():
		if not c.is_in_group("archers"): continue
		if c.assigned_wall_id == wall_id:
			on_wall += 1
		elif c.assigned_wall_id == "" or c.assigned_wall_id == null:
			var d: float = absf(c.position.x - float(wall["x"]))
			if d < min_dist:
				min_dist = d
				free_archer = c
	if on_wall>=max_a: show_notification("Wall full! Max %d archers at Lv%d"%[max_a,stage],Color.RED); return
	if not free_archer: show_notification("No free archers! Recruit at Barracks first.",Color(0.98,0.57,0.09)); return
	free_archer.assigned_wall_id=wall_id
	show_notification("🏹 Archer assigned to %s!"%wall["name"],Color(0.66,0.33,0.97))
	_update_barracks_ui()

# ── Forge ─────────────────────────────────────
func show_forge_menu() -> void:
	_hide_all_menus()
	if not forge_menu: return
	_update_forge_ui(); forge_menu.visible = true

func _update_forge_ui() -> void:
	if not forge_menu: return
	var al:=forge_menu.get_node_or_null("VBox/UpgArcher")
	var wl:=forge_menu.get_node_or_null("VBox/UpgWarrior")
	if al: al.text="⬆ Archers Lv%d→%d  [20G]"%[GameManager.archer_level,GameManager.archer_level+1]
	if wl: wl.text="⬆ Warriors Lv%d→%d  [20G]"%[GameManager.warrior_level,GameManager.warrior_level+1]

func _on_upgrade_archers() -> void:
	if GameManager.upgrade_archers():
		var w:=get_parent()
		if w:
			var an: Node = w.get_node_or_null("Allies")
			if an:
				for c in an.get_children():
					if c.is_in_group("archers"):
						c.max_hp = int(float(c.max_hp) * 1.1)
						c.hp     = mini(int(float(c.hp) * 1.1), c.max_hp)
		_update_forge_ui()

func _on_upgrade_warriors() -> void:
	if GameManager.upgrade_warriors():
		var w:=get_parent()
		if w:
			var an: Node = w.get_node_or_null("Allies")
			if an:
				for c in an.get_children():
					if c.is_in_group("warriors"):
						c.max_hp = int(float(c.max_hp) * 1.1)
						c.hp     = mini(int(float(c.hp) * 1.1), c.max_hp)
		_update_forge_ui()

# ── Wall Menu ─────────────────────────────────
func show_wall_menu(b: Dictionary) -> void:
	_hide_all_menus()
	if not wall_menu: return
	_current_wall_id=b.get("id",""); _update_wall_ui(b); wall_menu.visible=true

func _update_wall_ui(b: Dictionary) -> void:
	if not wall_menu: return
	var tl:=wall_menu.get_node_or_null("VBox/Title")
	var il:=wall_menu.get_node_or_null("VBox/Info")
	var ub:=wall_menu.get_node_or_null("VBox/UpgradeWall")
	var ab:=wall_menu.get_node_or_null("VBox/AssignArcher")
	var stage:int=b.get("stage",0)
	if tl: tl.text="🏰 %s  Lv%d"%[b.get("name","Wall"),stage]
	var world:=get_parent(); var ac:=0; var ma:=8 if stage>=3 else (4 if stage>=2 else 2)
	var free_count:=0
	if world:
		var an: Node = world.get_node_or_null("Allies")
		if an:
			for c in an.get_children():
				if not c.is_in_group("archers"): continue
				if c.assigned_wall_id==_current_wall_id: ac+=1
				elif c.assigned_wall_id=="" or c.assigned_wall_id==null: free_count+=1
	if il: il.text="Archers: %d/%d  |  Free: %d"%[ac,ma,free_count]
	if ab: ab.text="Assign Free Archer (%d)"%free_count
	if ub:
		if stage>=3: ub.visible=false
		else:
			ub.visible=true
			var cs:=[5,10,20]; ub.text="⬆ Upgrade to Lv%d  [%dG]"%[stage+1,cs[stage]]

func _on_wall_assign_archer() -> void:
	_on_assign_archer(_current_wall_id)
	var w:=GameManager.get_building(_current_wall_id)
	if not w.is_empty(): _update_wall_ui(w)

func _on_wall_upgrade() -> void:
	var wall:=GameManager.get_building(_current_wall_id)
	if wall.is_empty(): return
	var world:=get_parent()
	if world and world.has_method("build_wall_from_hud"):
		world.build_wall_from_hud(wall)
		_update_wall_ui(wall)

# ── Smith ─────────────────────────────────────
func show_smith_menu() -> void:
	_hide_all_menus()
	if not smith_menu: return
	_update_smith_ui(); smith_menu.visible=true

func _update_smith_ui() -> void:
	if not smith_menu: return
	var items_vbox:=smith_menu.get_node_or_null("VBox/Items")
	if not items_vbox: return
	for c in items_vbox.get_children(): c.queue_free()
	var upgrades:=[
		{"name":"⚔ Iron Sword",    "slot":"weapon",  "bonus_damage":10,  "desc":"+10 ATK","cost":25},
		{"name":"⚔ Steel Blade",   "slot":"weapon",  "bonus_damage":20,  "desc":"+20 ATK","cost":50},
		{"name":"🛡 Wooden Shield","slot":"shield",  "bonus_defense":8,  "desc":"+8 DEF", "cost":20},
		{"name":"🛡 Iron Kite",    "slot":"shield",  "bonus_defense":15, "desc":"+15 DEF","cost":40},
		{"name":"⛑ Iron Helm",    "slot":"helmet",  "bonus_defense":5,  "desc":"+5 DEF", "cost":20},
		{"name":"🥿 Light Boots",  "slot":"boots",   "bonus_stamina_drain":0.5,"desc":"-50% Stamina Drain","cost":35},
		{"name":"📿 Amulet of Life","slot":"medallion","bonus_max_hp":50, "desc":"+50 Max HP","cost":45},
		{"name":"💍 Scholar Ring", "slot":"ring",    "bonus_xp_multiplier":0.5,"desc":"+50% XP","cost":40},
	]
	for upg in upgrades:
		var btn:=Button.new()
		btn.text="%s  (%s)  [%dG]"%[upg["name"],upg["desc"],upg["cost"]]
		btn.add_theme_font_size_override("font_size",12)
		btn.custom_minimum_size=Vector2(0,32)
		var u: Dictionary = upg.duplicate()
		btn.pressed.connect(func(): _on_buy_item(u))
		items_vbox.add_child(btn)

func _on_buy_item(item: Dictionary) -> void:
	var cost:int=item.get("cost",0)
	if not GameManager.spend_gold(cost): show_notification("Need %dG!"%cost,Color.RED); return
	var equip: Dictionary = item.duplicate(); equip.erase("cost")
	HeroData.equipment[item["slot"]]=equip
	HeroData.recalc_stats()
	show_notification("✅ Bought %s!"%item["name"],Color(0.29,0.87,0.50))
	_refresh_inventory(); _update_smith_ui()

# ── Inventory ─────────────────────────────────
func _refresh_inventory() -> void:
	if not inventory_panel: return
	var slots:={"helmet":"⛑ Helmet","weapon":"⚔ Weapon","shield":"🛡 Shield","armor":"🥋 Armor","boots":"🥿 Boots","medallion":"📿 Medallion","ring":"💍 Ring"}
	for sk in slots:
		var sn:=inventory_panel.get_node_or_null("Grid/Slot_%s"%sk)
		if not sn: continue
		var il:=sn.get_node_or_null("ItemLabel"); var sl:=sn.get_node_or_null("StatLabel")
		var item=HeroData.equipment.get(sk,null)
		if not il: continue
		if not item:
			il.text="[Empty]"; il.modulate=Color(0.45,0.45,0.45)
			if sl: sl.text=""
		else:
			il.text=item.get("name","?"); il.modulate=Color.WHITE
			var stats:=""
			if "bonus_damage"        in item: stats+="+%d ATK "%item["bonus_damage"]
			if "bonus_defense"       in item: stats+="+%d DEF "%item["bonus_defense"]
			if "bonus_max_hp"        in item: stats+="+%d HP "%item["bonus_max_hp"]
			if "bonus_stamina_drain" in item: stats+="STM×%.1f "%item["bonus_stamina_drain"]
			if "bonus_xp_multiplier" in item: stats+="XP×%.1f "%(1.0+item["bonus_xp_multiplier"])
			if sl: sl.text=stats.strip_edges()

func _check_menu_proximity() -> void:
	var hero:=get_tree().get_first_node_in_group("hero") as Node2D
	if not hero: return
	var px:=hero.position.x
	for mn in ["BarracksMenu","ForgeMenu","SmithMenu","ShopMenu"]:
		var menu:=get_node_or_null(mn)
		if not menu or not menu.visible: continue
		var btype:="barracks" if mn=="BarracksMenu" else ("forge" if mn=="ForgeMenu" else ("smith" if mn=="SmithMenu" else "shop"))
		for b in GameManager.get_buildings_of_type(btype):
			if b.get("built",false) and abs(px-float(b["x"]))>Constants.BUILD_RADIUS*2:
				menu.visible=false
	if wall_menu and wall_menu.visible:
		var wall:=GameManager.get_building(_current_wall_id)
		if not wall.is_empty() and abs(px-float(wall["x"]))>Constants.BUILD_RADIUS*2:
			wall_menu.visible=false

# ── Weapon Shop ───────────────────────────────
func show_shop_menu() -> void:
	_hide_all_menus()
	if not shop_menu: return
	_update_shop_ui()
	shop_menu.visible = true

func show_inventory() -> void:
	if not inventory_panel: return
	inventory_panel.visible = true
	_refresh_inventory()

func _update_shop_ui() -> void:
	if not shop_menu: return
	var lbl := shop_menu.get_node_or_null("VBox/WeaponLabel")
	if lbl:
		var weap = HeroData.equipment.get("weapon", null)
		lbl.text = "Current: %s" % (weap.get("name", "None") if weap else "None")

func _on_buy_weapon(wname: String, cost: int, bonus_dmg: int, range_type: String) -> void:
	if not GameManager.spend_gold(cost):
		GameManager.notify("Need %dG! 💰" % cost, Color(1.0, 0.27, 0.27))
		return
	var item := {"name": wname, "slot": "weapon", "range_type": range_type}
	if bonus_dmg > 0: item["bonus_damage"] = bonus_dmg
	HeroData.equipment["weapon"] = item
	HeroData.recalc_stats()
	GameManager.notify("⚔️ %s equipped!" % wname, Color(0.98, 0.57, 0.09))
	_update_shop_ui()
	_hide_all_menus()

func show_game_over() -> void:
	if game_over: game_over.visible = true

func _on_restart() -> void:
	HeroData.reset(); GameManager.reset(); DayNight.reset()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
