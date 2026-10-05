package front

import game "../game"

// Presentation state stays outside saves and deterministic input recordings.
// Settings remember completion across deaths, quickloads and later launches.
Wing_Hint :: struct { active: bool, elapsed, opacity: f32 }
WING_HINT_DURATION :: f32(9)

wing_hint_near :: proc(world: ^game.World, position: game.Vec3) -> bool {
	anchor, ok := game.resolve_location(&world.sector, world.sector.wing_hint)
	if !ok { return false }
	delta := position-anchor
	// Do not trigger from the recovery floor below the crossing.
	return delta.x*delta.x+delta.z*delta.z < 64 && abs(delta.y) < 4
}

wing_hint_update :: proc(s: ^Wing_Hint, seen, near, used: bool, dt: f32) -> (completed: bool) {
	step := clamp(dt, 0, 0.1)
	if seen || used {
		s.active = false
		completed = used && !seen
	} else {
		if near && !s.active { s.active, s.elapsed = true, 0 }
		if s.active {
			s.elapsed += step
			if s.elapsed >= WING_HINT_DURATION { s.active, completed = false, true }
		}
	}
	s.opacity = game.approach(s.opacity, 1 if s.active else 0, step*4)
	return
}
