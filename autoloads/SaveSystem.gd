## autoloads/SaveSystem.gd
## Autoload singleton — zapis i wczytanie gry
## Używa FileAccess (działa na PC i Android)
## Dodaj do Project Settings → Autoload jako "SaveSystem"

extends Node

const SAVE_PATH := "user://kingdom_save.json"

# ── Sprawdź czy zapis istnieje ─────────────────
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

# ── Zapisz grę ─────────────────────────────────
func save_game(world_node: Node) -> void:
	var data := {
		"hero":    HeroData.to_dict(),
		"game":    GameManager.to_dict(),
		"day":     {"elapsed": DayNight.elapsed, "day_count": DayNight.day_count},
		"allies":  _serialize_allies(world_node),
		"hero_pos": _get_hero_pos(world_node),
	}

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		GameManager.notify("Save FAILED! Error: %d" % FileAccess.get_open_error(), Color.RED)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	GameManager.notify("Game Saved! ✅", Color(0.29, 0.87, 0.50))

# ── Wczytaj grę ────────────────────────────────
func load_game(world_node: Node) -> bool:
	if not has_save(): return false

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null: return false
	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		GameManager.notify("Save file corrupted!", Color.RED)
		return false

	# 1. Przywróć dane bohatera
	if "hero" in parsed:
		HeroData.from_dict(parsed["hero"])

	# 2. Przywróć GameManager (budynki, gold, itp.)
	if "game" in parsed:
		GameManager.from_dict(parsed["game"])

	# 3. Przywróć czas
	if "day" in parsed:
		DayNight.elapsed   = float(parsed["day"].get("elapsed", 0.0))
		DayNight.day_count = int(parsed["day"].get("day_count", 0))
		DayNight.is_night  = DayNight.elapsed >= Constants.DAY_S

	# 4. Sygnalizuj World, żeby przebudował fizykę i sojuszników
	if world_node and world_node.has_method("on_game_loaded"):
		world_node.on_game_loaded(parsed)

	GameManager.notify("Game Loaded! ✅", Color(0.29, 0.87, 0.50))
	return true

# ── Usuń zapis ─────────────────────────────────
func delete_save() -> void:
	DirAccess.remove_absolute(SAVE_PATH)

# ── Pomocnicze ────────────────────────────────
func _serialize_allies(world_node: Node) -> Dictionary:
	if not world_node: return {}
	var archers_data := []
	var warriors_data := []

	var allies: Node = world_node.get_node_or_null("Allies")
	if allies:
		for child in allies.get_children():
			if child.is_in_group("archers"):
				archers_data.append({
					"x": child.position.x,
					"dir": child.facing_dir,
					"hp": child.hp,
					"assigned_wall_id": child.assigned_wall_id,
				})
			elif child.is_in_group("warriors"):
				warriors_data.append({
					"x": child.position.x,
					"dir": child.facing_dir,
					"hp": child.hp,
				})

	return {"archers": archers_data, "warriors": warriors_data}

func _get_hero_pos(world_node: Node) -> Dictionary:
	var hero: Node = world_node.get_node_or_null("Hero") if world_node else null
	if hero:
		return {"x": hero.position.x, "y": hero.position.y}
	return {"x": 0.0, "y": Constants.GROUND_Y - 30.0}
