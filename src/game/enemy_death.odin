package game

// A shove into the void is a defeat. Keep the stable actor slot for saves,
// and stop both AI and corpse physics once it leaves the playable world.
retire_fallen_enemy :: proc(g: ^State, e: ^Enemy) {
	if e.health > 0 {
		e.health = 0
		g.kills += 1
		g.kill_sequence += 1
	}
	e.phase, e.phase_time, e.shield = .Recover, 0, 0
	e.velocity, e.knockback = {}, {}
}

enemy_death_duration :: proc(kind: Enemy_Kind) -> f32 {
	switch kind {
	case .Sentry: return 0.75
	case .Interceptor: return 0.85
	case .Crab: return 1.0
	case .Kettle: return 1.05
	case .Nanny: return 1.2
	case .Rabbit, .Rabbit_Young, .Rabbit_Kit: return 0.8
	}
	unreachable()
}

update_enemy_death :: proc(g: ^State, e: ^Enemy, dt: f32) {
	if e.phase_time <= 0 && e.velocity == (Vec3{}) { return }
	e.phase_time = max(0, e.phase_time-dt)
	e.flash = max(0, e.flash-dt)
	// Falling continues after the articulation finishes, even from high bridges.
	// Settled wrecks stay in their existing actor slots until this sector ends.
	e.velocity.y = max(-18, e.velocity.y-14*dt)
	move_enemy(g, e, e.velocity, dt)
	e.velocity.x *= max(0, 1-dt*3)
	e.velocity.z *= max(0, 1-dt*3)
	if e.phase_time <= 0 && length(e.velocity) < 0.025 { e.velocity = {} }
}
