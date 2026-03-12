## autoloads/Constants.gd
## Autoload singleton — wszystkie stałe gry
## Dodaj do Project Settings → Autoload jako "Constants"

extends Node

# ── Świat ──────────────────────────────────────
const WORLD_W       := 20000.0
const GROUND_Y      := 640.0   # viewport 720 - 80
const HALF_W        := WORLD_W / 2.0

# ── Biomy ─────────────────────────────────────
const BIOME_KINGDOM_END := 2000.0
const BIOME_FOREST_END  := 5000.0

# ── Gracz ─────────────────────────────────────
const PLAYER_W      := 22.0
const PLAYER_H      := 44.0
const PLAYER_SPEED  := 220.0
const JUMP_VEL      := -520.0
const GRAVITY       := 980.0
const BUILD_RADIUS  := 120.0

# ── Wróg ──────────────────────────────────────
const ENEMY_W       := 24.0
const ENEMY_H       := 40.0
const ENEMY_HP_BASE := 40
const ENEMY_SPEED   := 80.0    # px/s
const ENEMY_CAP     := 80      # max enemies na mapie

# ── Dzień/Noc ─────────────────────────────────
const CYCLE_S       := 180.0   # Całkowity cykl: 180s (80 dzień + 100 noc)
const DAY_S         := 80.0    # Dzień: 80 sekund
const MOON_CYCLE    := 10

# ── Portale do dungeonu ───────────────────────
const DUNGEON_PORTAL_LEFT  := -8000.0
const DUNGEON_PORTAL_RIGHT :=  8000.0
const DUNGEON_PORTAL_RADIUS:= 80.0

# ── Portale wrogów (overworld) ────────────────
const PORTALS := [
	{"x":  2800.0, "biome": "kingdom"},
	{"x": -2800.0, "biome": "kingdom"},
	{"x":  4200.0, "biome": "forest"},
	{"x": -4200.0, "biome": "forest"},
	{"x":  6500.0, "biome": "waste"},
	{"x": -6500.0, "biome": "waste"},
	{"x":  9000.0, "biome": "waste"},
	{"x": -9000.0, "biome": "waste"},
]

# ── Loot pool ─────────────────────────────────
const LOOT_POOL := [
	{"slot": "helmet",   "name": "Iron Helm",     "bonus_defense": 5,                    "desc": "+5 DEF"},
	{"slot": "weapon",   "name": "Silver Sword",  "bonus_damage": 15,                    "desc": "+15 DMG"},
	{"slot": "shield",   "name": "Wooden Kite",   "bonus_defense": 10,                   "desc": "+10 DEF"},
	{"slot": "armor",    "name": "Chainmail",     "bonus_defense": 15,                   "desc": "+15 DEF"},
	{"slot": "boots",    "name": "Light Boots",   "bonus_stamina_drain": 0.5,            "desc": "-50% Stamina Drain"},
	{"slot": "medallion","name": "Amulet of Life","bonus_max_hp": 50,                    "desc": "+50 Max HP"},
	{"slot": "ring",     "name": "Scholar Ring",  "bonus_xp_multiplier": 0.5,            "desc": "+50% XP"},
]

# ── Definicje budynków ────────────────────────
# Zwraca świeżą tablicę przy każdym wywołaniu (unikamy współdzielenia referencji).
func make_building_defs() -> Array:
	return [
		# Centrum
		{"id":"town_center","x":0.0,     "name":"Town Center",  "stage":1, "cost":0,  "color":Color(0.99,0.83,0.30), "glow":Color(1.0,0.94,0.54), "w":100.0,"h":160.0, "built":true,  "type":"town",     "hp":1000,"max_hp":1000},
		# Mury graniczne
		{"id":"left_wall",  "x":-1800.0, "name":"West Wall",    "stage":0, "cost":5,  "color":Color(0.16,0.0,0.38),  "glow":Color(0.49,0.23,0.93),"w":90.0, "h":80.0,  "built":false, "type":"wall",     "hp":0,   "max_hp":100},
		{"id":"right_wall", "x": 1800.0, "name":"East Wall",    "stage":0, "cost":5,  "color":Color(0.16,0.0,0.38),  "glow":Color(0.49,0.23,0.93),"w":90.0, "h":80.0,  "built":false, "type":"wall",     "hp":0,   "max_hp":100},
		# Budynki
		{"id":"smith",      "x":-1400.0, "name":"Forge",        "stage":0, "cost":20, "color":Color(0.10,0.04,0.0),  "glow":Color(0.98,0.45,0.09),"w":256.0,"h":223.0, "built":false, "type":"smith",    "hp":300, "max_hp":300},
		{"id":"farm",       "x":-600.0,  "name":"Farm",         "stage":1, "cost":50, "color":Color(0.05,0.17,0.05), "glow":Color(0.29,0.87,0.50),"w":70.0, "h":55.0,  "built":true,  "type":"farm",     "hp":200, "max_hp":200},
		{"id":"farm2",      "x":-300.0,  "name":"Small Farm",   "stage":1, "cost":50, "color":Color(0.05,0.17,0.05), "glow":Color(0.29,0.87,0.50),"w":70.0, "h":55.0,  "built":false, "type":"farm",     "hp":200, "max_hp":200},
		{"id":"shop",       "x": 600.0,  "name":"Weapon Shop",  "stage":0, "cost":20, "color":Color(0.10,0.04,0.0),  "glow":Color(0.98,0.57,0.24),"w":50.0, "h":65.0,  "built":false, "type":"shop",     "hp":0,   "max_hp":0},
		{"id":"teleport",   "x": 300.0,  "name":"Teleport",     "stage":0, "cost":50, "color":Color(0.02,0.0,0.16),  "glow":Color(0.51,0.55,0.97),"w":50.0, "h":70.0,  "built":false, "type":"teleport", "hp":0,   "max_hp":0},
		{"id":"barracks",   "x": 1000.0, "name":"Barracks",     "stage":0, "cost":30, "color":Color(0.27,0.04,0.04), "glow":Color(0.94,0.27,0.27),"w":70.0, "h":60.0,  "built":false, "type":"barracks", "hp":0,   "max_hp":0},
		{"id":"forge",      "x":-1000.0, "name":"Arcane Forge", "stage":0, "cost":35, "color":Color(0.23,0.03,0.39), "glow":Color(0.96,0.62,0.04),"w":55.0, "h":70.0,  "built":false, "type":"forge",    "hp":0,   "max_hp":0},
		# Skrzynie — overworld
		{"id":"chest1",  "x":-2400.0, "name":"Ancient Chest", "cost":0,"color":Color(0.55,0.27,0.07),"glow":Color(0.99,0.83,0.30),"w":40.0,"h":30.0,"built":true,"opened":false,"type":"chest","hp":0,"max_hp":0,"stage":0},
		{"id":"chest2",  "x": 2600.0, "name":"Ancient Chest", "cost":0,"color":Color(0.55,0.27,0.07),"glow":Color(0.99,0.83,0.30),"w":40.0,"h":30.0,"built":true,"opened":false,"type":"chest","hp":0,"max_hp":0,"stage":0},
		{"id":"chest3",  "x":-3200.0, "name":"Forest Cache",  "cost":0,"color":Color(0.10,0.23,0.0), "glow":Color(0.29,0.87,0.50),"w":40.0,"h":30.0,"built":true,"opened":false,"type":"chest","hp":0,"max_hp":0,"stage":0},
		{"id":"chest4",  "x": 3200.0, "name":"Forest Cache",  "cost":0,"color":Color(0.10,0.23,0.0), "glow":Color(0.29,0.87,0.50),"w":40.0,"h":30.0,"built":true,"opened":false,"type":"chest","hp":0,"max_hp":0,"stage":0},
		{"id":"chest5",  "x":-4600.0, "name":"Stone Relic",   "cost":0,"color":Color(0.20,0.20,0.27),"glow":Color(0.66,0.33,0.97),"w":64.0,"h":90.0,"built":true,"opened":false,"type":"chest","hp":0,"max_hp":0,"stage":0},
		{"id":"chest6",  "x": 4600.0, "name":"Stone Relic",   "cost":0,"color":Color(0.20,0.20,0.27),"glow":Color(0.66,0.33,0.97),"w":64.0,"h":90.0,"built":true,"opened":false,"type":"chest","hp":0,"max_hp":0,"stage":0},
		{"id":"chest7",  "x":-6500.0, "name":"Cursed Urn",    "cost":0,"color":Color(0.29,0.08,0.0), "glow":Color(1.0,0.40,0.0),  "w":40.0,"h":36.0,"built":true,"opened":false,"type":"chest","hp":0,"max_hp":0,"stage":0},
		{"id":"chest8",  "x": 6500.0, "name":"Cursed Urn",    "cost":0,"color":Color(0.29,0.08,0.0), "glow":Color(1.0,0.40,0.0),  "w":40.0,"h":36.0,"built":true,"opened":false,"type":"chest","hp":0,"max_hp":0,"stage":0},
		{"id":"chest9",  "x":-8800.0, "name":"Void Shard",    "cost":0,"color":Color(0.05,0.0,0.13), "glow":Color(0.66,0.33,0.97),"w":44.0,"h":34.0,"built":true,"opened":false,"type":"chest","hp":0,"max_hp":0,"stage":0},
		{"id":"chest10", "x": 8800.0, "name":"Void Shard",    "cost":0,"color":Color(0.05,0.0,0.13), "glow":Color(0.66,0.33,0.97),"w":44.0,"h":34.0,"built":true,"opened":false,"type":"chest","hp":0,"max_hp":0,"stage":0},
	]
