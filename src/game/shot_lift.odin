package game

LIFT_BUTTON_RADIUS :: f32(0.62)

Shot_Lift :: struct { button: Vec3, vent_index: int }

vent_running :: proc(v: Vent, started: bool) -> bool { return !v.controlled || started }

// A roof interrupts an updraft instead of leaking wind through it.
vent_reaches :: proc(w: ^World, v: Vent, position: Vec3) -> bool {
	d := position-v.position
	if d.x*d.x+d.z*d.z >= v.radius*v.radius || d.y <= -0.2 || position.y >= v.top { return false }
	height := max(0, d.y-0.08)
	return world_ray(w, {position.x, v.position.y+0.08, position.z}, {0, 1, 0}, height) >= height
}

lift_button_hit :: proc(w: ^World, origin, direction: Vec3, limit: f32) -> (f32, bool) {
	if w.sector.mechanism != .Shot_Lift { return limit, false }
	return ray_sphere(origin, direction, w.lift.button, LIFT_BUTTON_RADIUS, limit)
}

start_lift :: proc(g: ^State) {
	if g.world.sector.mechanism != .Shot_Lift || g.lift_started { return }
	g.lift_started = true
	button := g.world.lift.button
	sound_event(g, .RelayClick, button)
	sound_event(g, .PowerStart, g.world.vents[g.world.lift.vent_index].position+Vec3{0, 0.8, 0})
	emit(g, button, 24, 2)
	light_flash(g, button, {0.2, 1, 0.65}, 5, 3, 0.5)
	// Keep a shot made during the fight across death without checkpointing the
	// current enemy damage, attacks or the player's exposed firing position.
	if g.restart.valid {
		g.restart.run.lift_started = true
		g.checkpoint_sequence += 1
	}
}
