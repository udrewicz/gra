## autoloads/GameManager.gd
## Autoload singleton — zarządzanie grą, złoto, budynki, sojusznicy
## Dodaj do Project Settings → Autoload jako "GameManager"

extends Node

# ── Sygnały ────────────────────────────────────
signal gold_changed(new_amount: int)
signal building_built(building_id: String)
signal notification(msg: String, color: Color)
signal scene_changed(scene_name: String)  # "overworld" | "dungeon"

# ── Stan gry ──────────────────────────────────
var is_running    : bool = false
var pending_load  : bool = false
var gold_count    : int  = 500
var built_count   : int  = 0
var active_upgrades : Array = []
var is_blood_moon : bool = false
var enemies_to_spawn_this_night : int = 0

# ── Wojsko ────────────────────────────────────
var archer_level  : int = 1
var warrior_level : int = 1

# ── Punkt zbiórki (rally) ─────────────────────
var rally_point : Dictionary = {}  # {x, in_dungeon} lub pusty

# ── Definicje budynków (mutable runtime state) ─
var buildings : Array = []         # załadowane z Constants.make_building_defs()

# ── Scena ─────────────────────────────────────
var current_scene : String = "overworld"

func _ready() -> void:
	buildings = Constants.make_building_defs()

# ── Złoto ──────────────────────────────────────
func add_gold(n: int) -> void:
	gold_count += n
	gold_changed.emit(gold_count)

func spend_gold(n: int) -> bool:
	if gold_count < n: return false
	gold_count -= n
	gold_changed.emit(gold_count)
	return true

# ── Budynki ────────────────────────────────────
func add_upgrade(upgrade_name: String) -> void:
	active_upgrades.append(upgrade_name)
	built_count += 1
	building_built.emit(upgrade_name)

func get_building(id: String) -> Dictionary:
	for b in buildings:
		if b["id"] == id: return b
	return {}

func get_buildings_of_type(type: String) -> Array:
	return buildings.filter(func(b): return b["type"] == type)

# ── Powiadomienia ──────────────────────────────
func notify(msg: String, color: Color = Color.WHITE) -> void:
	notification.emit(msg, color)

# ── Ulepszenia wojska ─────────────────────────
func upgrade_archers() -> bool:
	if not spend_gold(20):
		notify("Not enough gold!", Color.RED)
		return false
	archer_level += 1
	notify("Archers upgraded to Lvl %d!" % archer_level, Color(0.29, 0.87, 0.50))
	return true

func upgrade_warriors() -> bool:
	if not spend_gold(20):
		notify("Not enough gold!", Color.RED)
		return false
	warrior_level += 1
	notify("Warriors upgraded to Lvl %d!" % warrior_level, Color(0.29, 0.87, 0.50))
	return true

# ── Zmiana sceny ──────────────────────────────
func set_scene(scene_name: String) -> void:
	current_scene = scene_name
	scene_changed.emit(scene_name)

func is_in_dungeon() -> bool:
	return current_scene == "dungeon"

# ── Serializacja ──────────────────────────────
func to_dict() -> Dictionary:
	var b_states := []
	for b in buildings:
		b_states.append({
			"id":     b["id"],
			"built":  b["built"],
			"hp":     b.get("hp", 0),
			"max_hp": b.get("max_hp", 0),
			"stage":  b.get("stage", 0),
			"opened": b.get("opened", false),
		})
	return {
		"gold_count":    gold_count,
		"built_count":   built_count,
		"active_upgrades": active_upgrades.duplicate(),
		"archer_level":  archer_level,
		"warrior_level": warrior_level,
		"rally_point":   rally_point.duplicate(),
		"buildings":     b_states,
	}

func from_dict(d: Dictionary) -> void:
	gold_count      = d.get("gold_count", 50)
	built_count     = d.get("built_count", 0)
	active_upgrades = d.get("active_upgrades", [])
	archer_level    = d.get("archer_level", 1)
	warrior_level   = d.get("warrior_level", 1)
	rally_point     = d.get("rally_point", {})

	# Restore building states
	buildings = Constants.make_building_defs()
	var saved_buildings : Array = d.get("buildings", [])
	for saved in saved_buildings:
		var bid : String = saved["id"]
		for b in buildings:
			if b["id"] == bid:
				b["built"]  = saved.get("built",  b["built"])
				b["hp"]     = saved.get("hp",     b.get("hp", 0))
				b["max_hp"] = saved.get("max_hp", b.get("max_hp", 0))
				b["stage"]  = saved.get("stage",  b.get("stage", 0))
				b["opened"] = saved.get("opened", b.get("opened", false))
				break
	gold_changed.emit(gold_count)

func reset() -> void:
	is_running      = false
	pending_load    = false
	gold_count      = 500
	built_count     = 0
	active_upgrades = []
	archer_level    = 1
	warrior_level   = 1
	rally_point     = {}
	buildings       = Constants.make_building_defs()
	is_blood_moon   = false
	enemies_to_spawn_this_night = 0
	current_scene   = "overworld"
	gold_changed.emit(gold_count)
