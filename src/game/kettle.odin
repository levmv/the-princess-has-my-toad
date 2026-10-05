package game

KETTLE_RADIUS :: f32(4.8)
KETTLE_FLIGHT :: f32(0.62)

// Track observed movement early in the whistle, then freeze the floor marker
// for the final 240 ms and the whole leap. A direction change beats the lead.
kettle_target :: proc(g: ^State, e: ^Enemy) {
	delta := e.last_known+e.known_velocity*(KETTLE_FLIGHT+0.24)-e.position
	delta.y = 0
	point := e.position+normalized(delta)*min(34, length(delta))
	point.y = e.last_known.y+0.3
	drop := world_ray(g, point, {0, -1, 0}, 16)
	if drop >= 16 { point = e.position; point.y -= enemy_extent(.Kettle).y } else { point.y -= drop }
	e.attack_target = point+Vec3{0, 0.04, 0}
}

kettle_launch :: proc(e: ^Enemy) {
	delta := e.attack_target-e.position
	height := e.attack_target.y+enemy_extent(.Kettle).y-e.position.y
	e.velocity = {delta.x/KETTLE_FLIGHT, height/KETTLE_FLIGHT+GRAVITY*KETTLE_FLIGHT*0.5, delta.z/KETTLE_FLIGHT}
	e.phase_time = 1.5
}

update_kettle_leap :: proc(g: ^State, e: ^Enemy, dt: f32) {
	velocity := e.velocity
	velocity.y = max(-24, velocity.y-GRAVITY*dt)
	blocked := move_enemy(g, e, velocity, dt)
	if blocked { e.velocity.x, e.velocity.z = 0, 0 }
	landed := velocity.y < 0 && abs(e.velocity.y) < 0.03
	if !landed && e.phase_time > 0 { return }
	if landed {
		point := e.position-Vec3{0, enemy_extent(.Kettle).y-0.04, 0}
		spawn_floor_hazard(g, point, KETTLE_RADIUS)
		delta := g.player.position+Vec3{0, 0.5, 0}-(point+Vec3{0, 0.5, 0})
		if abs(delta.y) < 1.5 && length(Vec3{delta.x, 0, delta.z}) < KETTLE_RADIUS && world_ray(g, point+Vec3{0, 0.5, 0}, normalized(delta), length(delta)) >= length(delta)-0.05 {
			damage(g, 28*difficulty_profile(g.difficulty).damage, .Kettle)
		}
		sound_event(g, .SteamBurst, point)
		light_flash(g, point+Vec3{0, 0.6, 0}, {1, 0.4, 0.05}, 5, 3, 0.35)
		emit(g, point, 20, 0)
	}
	e.phase, e.phase_time, e.exposed = .Recover, 0.55, 0.55
	e.velocity = {}
}

spawn_floor_hazard :: proc(g: ^State, point: Vec3, radius: f32) -> bool {
	for &h in g.hazards {
		if h.life > 0 { continue }
		h = {point, radius, 3.5, 0.2, 0}
		return true
	}
	g.hazards_refused += 1
	return false
}

update_floor_hazards :: proc(g: ^State, dt: f32) {
	for &h in g.hazards {
		if h.life <= 0 { continue }
		h.life = max(0, h.life-dt)
		h.warmup = max(0, h.warmup-dt)
		h.pulse -= dt
		if h.warmup > 0 || h.pulse > 0 { continue }
		h.pulse = 0.4
		delta := g.player.position-h.position
		if abs(delta.y) > 0.85 || length(Vec3{delta.x, 0, delta.z}) > h.radius { continue }
		from, target := h.position+Vec3{0, 0.5, 0}, g.player.position+Vec3{0, 0.5, 0}
		ray := target-from
		if world_ray(g, from, normalized(ray), length(ray)) >= length(ray)-0.05 { damage(g, 12*difficulty_profile(g.difficulty).damage, .Kettle) }
	}
}
