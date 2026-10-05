package front

import game "../game"

Death_Screen :: struct { active, armed: bool, age: f32, cause: game.Death_Cause }

death_begin :: proc(s: ^Death_Screen, cause: game.Death_Cause) { s^ = {active = true, cause = cause} }

// A held movement/fire key at the lethal hit must not eat the death screen.
// This presentation wait never adds ticks to the simulation or input replay.
death_update :: proc(s: ^Death_Screen, dt: f32, focused, held, pressed: bool) -> bool {
	if !s.active { return false }
	if !focused { s.armed = false; return false }
	s.age += clamp(dt, 0, 0.1)
	if !held { s.armed = true }
	if s.age >= 0.5 && s.armed && pressed { s.active = false; return true }
	return false
}
