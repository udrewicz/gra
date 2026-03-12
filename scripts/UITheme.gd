## scripts/UITheme.gd
## ══════════════════════════════════════════════════════════════════
##  Neonowy system UI — StyleBoxFlat z HDR border glow
##
##  UŻYCIE:
##   • Wywołaj UITheme.apply_to_panel(panel_node, style) z dowolnego skryptu
##   • Lub: UITheme.make_panel_stylebox(style) → zwraca StyleBoxFlat
##
##  STYLE: "purple" | "orange" | "red" | "green" | "blue" | "gold"
##
##  WAŻNE — HDR kolory (świecenie przez Glow):
##    W Inspectorze → kolor → zakładka "Raw" → wpisz wartości > 1.0
##    Np. Color(2.5, 0.0, 3.0) → fioletowy neon bardzo jasny
##    W GDScript:  Color(2.5, 0.0, 3.0)  (bez clamp = HDR)
## ══════════════════════════════════════════════════════════════════

extends Node

# ── Definicje stylów ──────────────────────────────────────────────
# Format: { bg, border, shadow, border_width }
# Kolory border są HDR (> 1.0) → świecą przez WorldEnvironment Glow
const STYLES := {
	"purple": {
		"bg":           Color(0.055, 0.010, 0.120, 0.82),
		"border":       Color(2.2, 0.5, 3.5),        # HDR neon fiolet
		"shadow":       Color(0.40, 0.0,  0.70, 0.55),
		"border_width": 2,
	},
	"orange": {
		"bg":           Color(0.060, 0.018, 0.008, 0.84),
		"border":       Color(3.0, 1.2, 0.0),         # HDR neon pomarańcz
		"shadow":       Color(0.60, 0.22, 0.0,  0.55),
		"border_width": 2,
	},
	"red": {
		"bg":           Color(0.055, 0.006, 0.006, 0.84),
		"border":       Color(3.0, 0.15, 0.15),        # HDR neon czerwień
		"shadow":       Color(0.55, 0.05, 0.05, 0.55),
		"border_width": 2,
	},
	"green": {
		"bg":           Color(0.008, 0.040, 0.012, 0.84),
		"border":       Color(0.15, 3.0, 0.5),          # HDR neon zieleń
		"shadow":       Color(0.05, 0.55, 0.15, 0.55),
		"border_width": 2,
	},
	"blue": {
		"bg":           Color(0.008, 0.020, 0.060, 0.84),
		"border":       Color(0.2, 0.8, 3.5),            # HDR neon niebieski
		"shadow":       Color(0.05, 0.20, 0.65, 0.55),
		"border_width": 2,
	},
	"gold": {
		"bg":           Color(0.048, 0.032, 0.004, 0.88),
		"border":       Color(3.0, 2.2, 0.0),             # HDR neon złoty
		"shadow":       Color(0.60, 0.42, 0.0,  0.55),
		"border_width": 2,
	},
}

# ══════════════════════════════════════════════════════════════════
#  PUBLICZNE API
# ══════════════════════════════════════════════════════════════════

## Zwraca gotowy StyleBoxFlat dla danego stylu neonowego
func make_panel_stylebox(style: String = "purple", corner_r: int = 10) -> StyleBoxFlat:
	var s : Dictionary = STYLES.get(style, STYLES["purple"]) as Dictionary
	var sb := StyleBoxFlat.new()

	# ── Tło ────────────────────────────────────────────────────
	sb.bg_color             = s["bg"]
	sb.draw_center          = true

	# ── Zaokrąglone rogi ───────────────────────────────────────
	sb.corner_radius_top_left     = corner_r
	sb.corner_radius_top_right    = corner_r
	sb.corner_radius_bottom_left  = corner_r
	sb.corner_radius_bottom_right = corner_r
	sb.corner_detail              = 8

	# ── Neonowa ramka (HDR) ────────────────────────────────────
	var bw: int = s["border_width"]
	sb.border_width_left   = bw
	sb.border_width_right  = bw
	sb.border_width_top    = bw
	sb.border_width_bottom = bw
	sb.border_color        = s["border"]
	sb.border_blend        = false   # false = czyste HDR bez blend

	# ── Cień (glow shadow) ─────────────────────────────────────
	sb.shadow_color  = s["shadow"]
	sb.shadow_size   = 12
	sb.shadow_offset = Vector2(0, 2)

	# ── Padding wewnętrzny ─────────────────────────────────────
	sb.content_margin_left   = 14.0
	sb.content_margin_right  = 14.0
	sb.content_margin_top    = 10.0
	sb.content_margin_bottom = 10.0

	return sb

## Zastosuj styl bezpośrednio do węzła Panel/PanelContainer
func apply_to_panel(node: Control, style: String = "purple", corner_r: int = 10) -> void:
	var sb := make_panel_stylebox(style, corner_r)
	if node is Panel:
		node.add_theme_stylebox_override("panel", sb)
	elif node is PanelContainer:
		node.add_theme_stylebox_override("panel", sb)
	else:
		push_warning("UITheme.apply_to_panel: węzeł nie jest Panel/PanelContainer")

## Stylizuj przycisk w stylu neonowym
func make_button_stylebox(style: String = "purple", pressed: bool = false) -> StyleBoxFlat:
	var sb := make_panel_stylebox(style, 6)
	if pressed:
		var s : Dictionary = STYLES.get(style, STYLES["purple"]) as Dictionary
		sb.bg_color    = (s["border"] as Color) * 0.25
		sb.shadow_size = 4
	return sb

## Stylizuj cały przycisk (normal + hover + pressed)
func apply_to_button(btn: Button, style: String = "purple") -> void:
	btn.add_theme_stylebox_override("normal",   make_button_stylebox(style, false))
	btn.add_theme_stylebox_override("hover",    _make_hover_sb(style))
	btn.add_theme_stylebox_override("pressed",  make_button_stylebox(style, true))
	btn.add_theme_stylebox_override("disabled", _make_disabled_sb())
	btn.add_theme_color_override("font_color",         Color(1.0,  1.0,  1.0))
	btn.add_theme_color_override("font_hover_color",   Color(1.0,  1.0,  1.0))
	btn.add_theme_color_override("font_pressed_color", Color(0.85, 0.85, 0.85))
	btn.add_theme_font_size_override("font_size", 14)

# ── Prywatne helpery ─────────────────────────────────────────────
func _make_hover_sb(style: String) -> StyleBoxFlat:
	var sb := make_panel_stylebox(style, 6)
	var s  : Dictionary = STYLES.get(style, STYLES["purple"]) as Dictionary
	sb.bg_color    = (s["bg"] as Color).lightened(0.12)
	sb.shadow_size = 18
	return sb

func _make_disabled_sb() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color              = Color(0.08, 0.05, 0.12, 0.6)
	sb.border_color          = Color(0.30, 0.20, 0.40, 0.5)
	sb.border_width_left     = 1
	sb.border_width_right    = 1
	sb.border_width_top      = 1
	sb.border_width_bottom   = 1
	sb.corner_radius_top_left     = 6
	sb.corner_radius_top_right    = 6
	sb.corner_radius_bottom_left  = 6
	sb.corner_radius_bottom_right = 6
	sb.content_margin_left   = 14.0
	sb.content_margin_right  = 14.0
	sb.content_margin_top    = 10.0
	sb.content_margin_bottom = 10.0
	return sb
