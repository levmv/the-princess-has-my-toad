package game

import "core:math"

overlap :: proc(position: Vec3, b: Block) -> bool {
	lo := b.center-b.size*0.5
	hi := b.center+b.size*0.5
	e := f32(0.00001)
	return position.x+PLAYER_RADIUS > lo.x+e && position.x-PLAYER_RADIUS < hi.x-e &&
		position.z+PLAYER_RADIUS > lo.z+e && position.z-PLAYER_RADIUS < hi.z-e &&
		position.y+PLAYER_HEIGHT > lo.y+e && position.y < hi.y-e
}

allows_velocity :: proc(velocity: Vec3, planes: []Vec3) -> bool {
	for normal in planes { if dot(velocity, normal) < -0.00001 { return false } }
	return true
}

slide_velocity :: proc(velocity: Vec3, planes: []Vec3) -> Vec3 {
	// Keep every contact from this move. Clipping only the most recent normal
	// lets a floor push the player back into an overhanging wall, and vice versa.
	for normal in planes {
		backoff := min(0, dot(velocity, normal))
		// An exactly tangent velocity slowly rounds into an inclined floor as
		// world positions are stored in f32. A tiny outward bias on walkable
		// slopes prevents that drift; flat floors and ceilings still stop dead.
		if normal.y > 0.6 && normal.y < 0.99999 { backoff *= 1.001 }
		candidate := velocity-normal*backoff
		if allows_velocity(candidate, planes) { return candidate }
	}
	// Two blocking planes leave a crease to slide along. Choose the closest
	// allowed velocity; a third blocking plane can reduce that movement to zero.
	best: Vec3
	for normal, i in planes {
		for other in planes[:i] {
			crease := normalized(cross(normal, other))
			candidate := crease*dot(velocity, crease)
			if dot(candidate, candidate) > dot(best, best) && allows_velocity(candidate, planes) { best = candidate }
		}
	}
	return best
}

move_player :: proc(g: ^State, dt: f32) {
	p := &g.player
	p.grounded = false
	remaining := dt
	extent := Vec3{PLAYER_RADIUS, PLAYER_HEIGHT*0.5, PLAYER_RADIUS}
	planes: [6]Vec3
	plane_count := 0
	for _ in 0..<6 {
		delta := p.velocity*remaining
		if length(delta) < 0.000001 { break }
		center := p.position+Vec3{0, PLAYER_HEIGHT*0.5, 0}
		fraction, normal := world_sweep(g.world, center, delta, extent)
		if fraction >= 1 { p.position += delta; break }
		// Stop just before contact along the known clear path. Pushing outward
		// along one normal can put the player inside an adjacent solid.
		p.position += delta*max(0, fraction-CONTACT_MARGIN/length(delta))
		if normal.y > 0.6 { p.grounded = true }
		duplicate := false
		for previous in planes[:plane_count] { if dot(previous, normal) > 0.99999 { duplicate = true; break } }
		if !duplicate { planes[plane_count] = normal; plane_count += 1 }
		p.velocity = slide_velocity(p.velocity, planes[:plane_count])
		remaining *= 1-fraction
	}
}

// Ground steering has an isotropic acceleration limit. Air steering adds
// acceleration along the requested direction while preserving released momentum.
steer_player :: proc(p: ^Player, wish: Vec3, speed, dt: f32) {
	horizontal := Vec3{p.velocity.x, 0, p.velocity.z}
	if p.grounded || p.gliding {
		if p.grounded || length(wish) > 0.001 {
			delta := wish*speed-horizontal
			accel := f32(110) if p.grounded else f32(32)
			horizontal += delta*min(1, accel*dt/max(length(delta), 0.0001))
		}
	} else if magnitude := length(wish); magnitude > 0.001 {
		direction := wish/magnitude
		limit := max(speed, length(horizontal))
		gain := min(28*dt*magnitude, max(0, speed*magnitude-dot(horizontal, direction)))
		horizontal += direction*gain
		// Preserve a dash, but do not gain unlimited speed by alternating strafes.
		horizontal *= min(1, limit/max(length(horizontal), 0.0001))
	}
	p.velocity.x, p.velocity.z = horizontal.x, horizontal.z
}

update_player :: proc(g: ^State, input: Input, dt: f32) {
	boss_exit_sync(g)
	p := &g.player
	was_grounded := p.grounded
	previous_position := p.position
	p.dash_cooldown = max(0, p.dash_cooldown-dt)
	p.dash_time = max(0, p.dash_time-dt)
	p.invulnerable = max(0, p.invulnerable-dt)
	p.hurt_time = max(0, p.hurt_time-dt)
	p.recoil = max(0, p.recoil-dt*22)
	p.weapon_bloom = max(0, p.weapon_bloom-dt*1.25)
	p.scope_time += dt
	p.hit_marker = max(0, p.hit_marker-dt)
	p.land_time = max(0, p.land_time-dt)
	if !input.jump_held {
		p.gliding = false
		if !p.grounded { p.glide_ready = true }
	}
	if p.grounded { p.glide_ready = false }
	p.coyote = 0.12 if p.grounded else max(0, p.coyote-dt)
	p.jump_buffer = 0.13 if input.jump_pressed else max(0, p.jump_buffer-dt)
	if p.jump_buffer > 0 && p.coyote > 0 {
		p.velocity.y = JUMP_SPEED
		p.land_time = 0
		p.grounded = false
		p.gliding, p.glide_ready = false, false
		p.coyote = 0
		p.jump_buffer = 0
		g.jump_sequence += 1
	}
	f := forward(p.yaw, 0)
	r := Vec3{math.cos(p.yaw), 0, math.sin(p.yaw)}
	wish := f*input.move.y + r*input.move.x
	wish /= max(1, length(wish))
	p.in_current = false
	for vent in g.world.vents {
		if vent_running(vent, g.lift_started) && vent_reaches(g.world, vent, p.position) { p.in_current = true }
	}
	if input.jump_pressed && input.jump_held && p.glide_ready && !p.grounded && p.coyote <= 0 {
		// A press immediately above the floor remains a buffered jump. It must
		// not deploy the wing and prevent the landing it was intended for.
		clearance := world_ray(g.world, p.position+Vec3{0, 0.1, 0}, {0, -1, 0}, 0.7)
		if p.velocity.y > 0 || clearance >= 0.7 {
			p.gliding, p.glide_ready = true, false
			p.jump_buffer = 0
			g.glide_sequence += 1
		}
	}
	speed := RUN_SPEED
	if p.gliding { speed = GLIDE_SPEED }
	if input.focus { speed *= 0.8 }
	if p.dash_time <= 0 { steer_player(p, wish, speed, dt) }
	if input.dash_pressed && p.dash_cooldown <= 0 {
		dir := normalized(wish)
		if length(dir) < 0.1 { dir = f }
		p.velocity.x = dir.x*30
		p.velocity.z = dir.z*30
		p.velocity.y = max(p.velocity.y, 2)
		p.dash_cooldown = DASH_COOLDOWN
		p.dash_time = 0.18
		emit(g, p.position+Vec3{0, 0.8, 0}, 15, 1)
	}
	gravity := GRAVITY
	// Keep the deployed wing open after an updraft, without a floaty upward coast.
	if p.gliding && p.velocity.y < 1.5 { gravity = 6 }
	p.velocity.y -= gravity*dt
	if p.gliding {
		p.velocity.y = max(p.velocity.y, -2.8)
		if p.in_current { p.velocity.y = approach(p.velocity.y, 15, 48*dt) }
	}
	impact_speed := max(0, -p.velocity.y)
	move_player(g, dt)
	if p.grounded {
		p.gliding, p.glide_ready = false, false
		p.air_time = 0
		if !was_grounded && impact_speed > 1.5 {
			p.land_time = 0.24
			p.land_strength = clamp((impact_speed-2)/15, 0.1, 1)
			g.land_sequence += 1
		}
		if was_grounded {
			delta := p.position-previous_position
			distance := length(Vec3{delta.x, 0, delta.z})
			before := int(p.gait_phase/math.PI)
			p.gait_phase += distance*2*math.PI/STRIDE_DISTANCE
			if int(p.gait_phase/math.PI) != before && distance > 0.001 { g.step_sequence += 1 }
			p.gait_phase = math.mod(p.gait_phase, 2*math.PI)
		}
	} else { p.air_time += dt }
	p.glide_blend = approach(p.glide_blend, 1 if p.gliding else 0, dt*8)
	if length(wish) > 0.01 || !p.grounded || input.fire { p.idle_time = 0 } else { p.idle_time += dt }
	if p.position.y < VOID_HEIGHT { g.last_death = .Void; respawn(g) }
}
