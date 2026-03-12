## autoloads/DayNight.gd
## Autoload singleton — cykl dnia i nocy
## Dodaj do Project Settings → Autoload jako "DayNight"

extends Node

# ── Sygnały ────────────────────────────────────
signal night_started(night_number: int, is_blood_moon: bool)
signal day_started(day_number: int)

# ── Stan ───────────────────────────────────────
var elapsed   : float = 0.0
var is_night  : bool  = false
var day_count : int   = 0

# day_fraction: 0.0 = świt/północ, 1.0 = południe
var day_fraction : float:
	get:
		if not is_night:
			return elapsed / Constants.DAY_S
		else:
			return 1.0 - (elapsed - Constants.DAY_S) / (Constants.CYCLE_S - Constants.DAY_S)

# ── Tick — wywoływane w _process World.gd ──────
func tick(delta: float) -> void:
	elapsed = fmod(elapsed + delta, Constants.CYCLE_S)
	var was_night := is_night
	is_night = elapsed >= Constants.DAY_S

	if is_night != was_night:
		if is_night:
			day_count += 1
			var moon_phase := day_count % Constants.MOON_CYCLE
			var blood := moon_phase == 0

			GameManager.is_blood_moon = blood
			var base: int = max(10, day_count * 3)
			GameManager.enemies_to_spawn_this_night = base * (2 if blood else 1)
			night_started.emit(day_count, blood)
		else:
			day_started.emit(day_count)

# ── Kolor nieba ────────────────────────────────
# Zwraca Color interpolowany przez keyframe'y dnia/nocy
func get_sky_color() -> Color:
	var f := day_fraction
	if is_night:
		# Noc: granatowa → ciemna purpura
		return Color(0.04, 0.06, 0.18).lerp(Color(0.08, 0.10, 0.28), f)
	else:
		# Dzień: świt różowy → błękitne południe → wieczorny pomarańcz
		if f < 0.25:  # Świt
			return Color(0.08, 0.10, 0.28).lerp(Color(0.92, 0.55, 0.25), f * 4.0)
		elif f < 0.5:  # Ranek → południe
			return Color(0.92, 0.55, 0.25).lerp(Color(0.40, 0.72, 0.96), (f - 0.25) * 4.0)
		elif f < 0.75:  # Południe (najpiękniejszy błękit)
			return Color(0.40, 0.72, 0.96).lerp(Color(0.92, 0.55, 0.25), (f - 0.5) * 4.0)
		else:  # Wieczór → zmierzch
			return Color(0.92, 0.55, 0.25).lerp(Color(0.08, 0.10, 0.28), (f - 0.75) * 4.0)

# ── Reset ──────────────────────────────────────
func reset() -> void:
	elapsed   = 0.0
	is_night  = false
	day_count = 0
