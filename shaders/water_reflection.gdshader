// ══════════════════════════════════════════════════════════════════
//  water_reflection.gdshader
//  Użycie: Podłącz do ShaderMaterial na ColorRect (Water strip)
//  ColorRect powinien siedzieć na ground level, np.:
//    position = (0, GROUND_Y),  size = (WORLD_W, 28)
//  Wymaga: Project Settings → Rendering → Textures →
//           "Screen Space Reflection" LUB po prostu viewport texture.
// ══════════════════════════════════════════════════════════════════
shader_type canvas_item;

// ── Parametry edytowalne w Inspectorze ──────────────────
uniform float wave_speed      : hint_range(0.0, 5.0)   = 1.2;
uniform float wave_strength   : hint_range(0.0, 0.05)  = 0.012;
uniform float wave_frequency  : hint_range(1.0, 40.0)  = 18.0;
uniform float wave_frequency2 : hint_range(1.0, 40.0)  = 11.0;
uniform float alpha           : hint_range(0.0, 1.0)   = 0.42;
uniform float brightness      : hint_range(0.0, 2.0)   = 0.55;
uniform float blur_amount     : hint_range(0.0, 0.01)  = 0.003;
uniform vec4  tint_color      : source_color            = vec4(0.18, 0.05, 0.35, 1.0);
uniform float tint_strength   : hint_range(0.0, 1.0)   = 0.35;

// Korzystamy z SCREEN_TEXTURE — automatycznie dostępne w canvas_item
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	// UV.y = 0 → górna krawędź paska wody, UV.y = 1 → dół
	// Odbicie = "lustrzane" UV w osi Y ekranu.
	// SCREEN_UV.y aktualnej pozycji piksela = punkt na ekranie gdzie jesteśmy.
	// Odbijamy pionowo: reflected_y = SCREEN_UV.y - (UV.y * strip_height_normalized)
	// Prostsze podejście: flipp SCREEN_UV.y względem środka paska.
	vec2 screen_uv = SCREEN_UV;

	// ── Falowanie (dwie nakładające się fale sin) ────────────────
	float wave1 = sin(UV.x * wave_frequency  + TIME * wave_speed)        * wave_strength;
	float wave2 = sin(UV.x * wave_frequency2 + TIME * wave_speed * 0.7 + 1.57) * wave_strength * 0.5;
	float distort_x = wave1 + wave2;

	// Słabsze falowanie w osi Y (głębsze → mniej fal)
	float distort_y = cos(UV.x * wave_frequency * 0.6 + TIME * wave_speed * 0.5) * wave_strength * 0.3;

	// ── Kierunek odbicia: lustrzane flip Y ──────────────────────
	// Odbity piksel siedzi POWYŻEJ paska wody.
	// UV.y=0 → sięgamy tuż powyżej, UV.y=1 → sięgamy wyżej.
	// Skalujemy "głębokość" lustra przez UV.y.
	float mirror_offset = (1.0 - UV.y) * 0.22 + 0.02;  // im wyżej, tym głębszy "reflex"
	vec2 reflected_uv = vec2(
		screen_uv.x + distort_x,
		screen_uv.y - mirror_offset + distort_y
	);
	reflected_uv = clamp(reflected_uv, vec2(0.0), vec2(1.0));

	// ── Soft blur odbicia (rozmycie perspektywiczne) ────────────
	vec4 col  = texture(SCREEN_TEXTURE, reflected_uv);
	vec4 col2 = texture(SCREEN_TEXTURE, reflected_uv + vec2(blur_amount, 0.0));
	vec4 col3 = texture(SCREEN_TEXTURE, reflected_uv - vec2(blur_amount, 0.0));
	vec4 col4 = texture(SCREEN_TEXTURE, reflected_uv + vec2(0.0, blur_amount));
	vec4 reflection = (col + col2 + col3 + col4) * 0.25;

	// ── Przyciemnienie głębszej wody (UV.y = 1 → ciemniej) ─────
	float depth_fade = 1.0 - UV.y * 0.6;
	reflection.rgb *= brightness * depth_fade;

	// ── Tint neonowy (fiolet/granat) ────────────────────────────
	reflection.rgb = mix(reflection.rgb, tint_color.rgb, tint_strength);

	// ── Pozioma linia odblasków słońca/neonu ────────────────────
	float sparkle = pow(max(0.0, sin(UV.x * 60.0 + TIME * 3.0) * 0.5 + 0.5), 12.0);
	sparkle      += pow(max(0.0, sin(UV.x * 37.0 - TIME * 2.1) * 0.5 + 0.5), 16.0) * 0.5;
	float sparkle_fade = (1.0 - UV.y) * 0.7;  // tylko przy górnej krawędzi
	reflection.rgb += vec3(0.8, 0.4, 1.0) * sparkle * sparkle_fade * 0.18;

	// ── Alpha: górna krawędź pełna, dół zanika ──────────────────
	float edge_alpha = alpha * (1.0 - UV.y * 0.55);

	COLOR = vec4(reflection.rgb, edge_alpha);
}
