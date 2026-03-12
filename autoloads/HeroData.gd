## autoloads/HeroData.gd
## Autoload singleton — dane i statystyki bohatera
## Dodaj do Project Settings → Autoload jako "HeroData"

extends Node

# ── Sygnały ────────────────────────────────────
signal hit_taken  # for camera shake
signal stats_changed
signal died
signal leveled_up(new_level: int)

# ── Statystyki bazowe ─────────────────────────
var hp        : int   = 100
var max_hp    : int   = 100
var xp        : int   = 0
var xp_cap    : int   = 100
var level     : int   = 1

var damage        : int   = 5
var base_damage   : int   = 5
var defense       : int   = 0
var base_defense  : int   = 0

var stamina         : float = 100.0
var max_stamina     : float = 100.0
var stamina_drain   : float = 1.0
var base_stamina_drain : float = 1.0

var xp_multiplier : float = 1.0

var invincible_frames : float = 0.0
var dead : bool = false

var items_collected : int = 0

# ── Ekwipunek ─────────────────────────────────
var equipment : Dictionary = {
	"helmet":    null,
	"weapon":    null,
	"shield":    null,
	"armor":     null,
	"boots":     null,
	"medallion": null,
	"ring":      null,
}

# ── Przelicz statystyki na podstawie ekwipunku ─
func recalc_stats() -> void:
	damage        = base_damage
	max_hp        = 100 + (level - 1) * 20
	max_stamina   = 100.0
	stamina_drain = base_stamina_drain
	defense       = base_defense
	xp_multiplier = 1.0

	for item in equipment.values():
		if item == null: continue
		if "bonus_damage"        in item: damage        += item["bonus_damage"]
		if "bonus_max_hp"        in item: max_hp        += item["bonus_max_hp"]
		if "bonus_defense"       in item: defense       += item["bonus_defense"]
		if "bonus_stamina_drain" in item: stamina_drain  = item["bonus_stamina_drain"]
		if "bonus_xp_multiplier" in item: xp_multiplier += item["bonus_xp_multiplier"]

	hp      = min(hp, max_hp)
	stamina = min(stamina, max_stamina)
	stats_changed.emit()

# ── Obrażenia ──────────────────────────────────
func take_damage(n: int) -> void:
	if invincible_frames > 0 or dead: return
	var dmg: int = max(1, n - defense)
	hp = max(0, hp - dmg)
	invincible_frames = 1.5  # sekundy
	hit_taken.emit()
	stats_changed.emit()

	if hp <= 0:
		dead = true
		died.emit()

# ── Doświadczenie ──────────────────────────────
func gain_xp(n: int) -> void:
	var gained: int = int(n * xp_multiplier)
	xp += gained
	while xp >= xp_cap:
		_level_up()
	stats_changed.emit()

func _level_up() -> void:
	xp     -= xp_cap
	level  += 1
	xp_cap  = int(xp_cap * 1.5)
	recalc_stats()
	hp = max_hp
	leveled_up.emit(level)
	stats_changed.emit()

# ── Fizyczna regeneracja iframes ───────────────
func tick_iframes(delta: float) -> void:
	if invincible_frames > 0:
		invincible_frames = max(0.0, invincible_frames - delta)

# ── Reset do stanu początkowego ───────────────
func reset() -> void:
	hp = 100; max_hp = 100
	xp = 0;   xp_cap = 100; level = 1
	damage = 5; base_damage = 5
	defense = 0; base_defense = 0
	stamina = 100.0; max_stamina = 100.0
	stamina_drain = 1.0
	xp_multiplier = 1.0
	invincible_frames = 0.0
	dead = false
	items_collected = 0
	for key in equipment:
		equipment[key] = null
	stats_changed.emit()

# ── Serializacja (dla SaveSystem) ─────────────
func to_dict() -> Dictionary:
	return {
		"hp": hp, "max_hp": max_hp,
		"xp": xp, "xp_cap": xp_cap, "level": level,
		"damage": damage, "base_damage": base_damage,
		"defense": defense, "stamina": stamina,
		"items_collected": items_collected,
		"equipment": equipment.duplicate(true),
	}

func from_dict(d: Dictionary) -> void:
	hp              = d.get("hp", 100)
	max_hp          = d.get("max_hp", 100)
	xp              = d.get("xp", 0)
	xp_cap          = d.get("xp_cap", 100)
	level           = d.get("level", 1)
	damage          = d.get("damage", 5)
	base_damage     = d.get("base_damage", 5)
	defense         = d.get("defense", 0)
	stamina         = d.get("stamina", 100.0)
	items_collected = d.get("items_collected", 0)
	equipment       = d.get("equipment", {
		"helmet": null, "weapon": null, "shield": null,
		"armor": null, "boots": null, "medallion": null, "ring": null,
	})
	recalc_stats()
