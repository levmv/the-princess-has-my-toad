package game

import "core:math"

RABBIT_HATCH_TIME :: f32(0.35)
rabbit_kind :: proc(kind: Enemy_Kind) -> bool { return kind == .Rabbit || kind == .Rabbit_Young || kind == .Rabbit_Kit }
enemy_organic :: proc(kind: Enemy_Kind) -> bool { return kind == .Sentry || kind == .Interceptor || rabbit_kind(kind) }
enemy_active :: proc(e: $E) -> bool { return e.health > 0 && e.phase != .Dormant && e.phase != .Hatching }

// Seven stable authored slots form a binary tree: 1 -> 2 -> 4. Reserving the
// children at load keeps splitting bounded, allocation-free and saveable.
// Newborns finish emerging before accepting damage, so one splash cannot
// recursively consume the entire family in a single iteration of the pool.
split_rabbit :: proc(g: ^State, parent: ^Enemy) {
	if parent.kind != .Rabbit && parent.kind != .Rabbit_Young { return }
	ordinal := int(u32(parent.content_id)&0xffff)-0x100
	if ordinal < 0 || ordinal > 2 { return }
	room := Room_ID(u32(parent.content_id)>>16)
	right, _, forward := enemy_basis(parent.facing)
	for side in 0..<2 {
		id := room_object_id(room, u16(0x100+ordinal*2+1+side))
		for &child in g.enemies[:g.enemy_count] {
			if child.content_id != id || child.phase != .Dormant { continue }
			extent := enemy_extent(child.kind)
			best, clearance := parent.position, f32(-1)
			for direction in ([4]Vec3{right, forward, -right, -forward}) {
				delta := direction*(extent.x+0.15)*f32(1 if side == 0 else -1)
				delta.y = extent.y-enemy_extent(parent.kind).y
				fraction, _ := world_sweep(g.world, parent.position, delta, extent)
				if fraction > clearance {
					clearance, best = fraction, parent.position+delta*max(0, fraction-0.002)
				}
			}
			child.position, child.phase, child.phase_time = best, .Hatching, RABBIT_HATCH_TIME
			child.facing, child.alerted, child.last_known, child.memory_time = parent.facing, true, parent.last_known, 12
			child.fire_timer, child.sight_timer, child.nav_time = 0.10+f32(side)*0.08, 0, 0
			child.gait_phase = math.mod(f32(child.generation)*2.4, 2*math.PI)
			break
		}
	}
}

rabbit_rush_speed :: proc(kind: Enemy_Kind) -> f32 {
	return 22 if kind == .Rabbit else (23.5 if kind == .Rabbit_Young else 25)
}

// Individual lanes and short leads break up a single-file chase. The drift is
// smooth and keyed to actor identity/time, so saves and replays keep its phase.
// Lost targets still use the real navigation route, never their hidden motion.
rabbit_pursuit_goal :: proc(g: ^State, e: ^Enemy, temperament: f32) -> Vec3 {
	if !e.sees_player { return e.nav_goal }
	delta := e.last_known-e.position
	delta.y = 0
	direction := normalized(delta)
	side := Vec3{-direction.z, 0, direction.x}
	phase := f32(e.generation%19)*2.39996
	lane := f32(int(e.generation%5)-2)*1.25+math.sin(g.time*(1.1+temperament*0.35)+phase)*0.85
	if e.kind == .Rabbit { lane *= 0.45 }
	return e.last_known+e.known_velocity*(0.12+temperament*0.16)+side*lane*clamp((length(delta)-2)/9, 0, 1)
}

update_rabbit :: proc(g: ^State, e: ^Enemy, dt: f32) {
	profile := difficulty_profile(g.difficulty)
	temperament := f32((e.generation*7)%11)/10
	rush_speed := rabbit_rush_speed(e.kind)*profile.move
	vertical := max(-22, e.velocity.y-GRAVITY*dt)
	if e.phase != .Attack && e.phase != .Patrol { move_enemy(g, e, {0, vertical, 0}, dt) }
	if !e.alerted && e.phase == .Patrol { move_enemy(g, e, {0, vertical, 0}, dt); return }
	delta := e.last_known-e.position
	direction := normalized(Vec3{delta.x, 0, delta.z})
	distance := length(Vec3{delta.x, 0, delta.z})
	switch e.phase {
	case .Patrol:
		goal := rabbit_pursuit_goal(g, e, temperament)
		velocity := enemy_steer(g, e, goal, enemy_move_speed(e.kind)*profile.move*(0.96+temperament*0.08))
		if length(velocity) > 0.1 { e.facing = normalized(e.facing+(normalized(velocity)-e.facing)*min(1, dt*10)) }
		velocity.y = vertical
		move_enemy(g, e, velocity, dt)
		if e.sees_player && distance < 8.2+temperament*1.4 && abs(delta.y) < 2.8 && e.fire_timer <= 0 {
			begin_enemy_attack(g, e)
			e.attack_direction = direction
		}
	case .Windup:
		// The last 180 ms commit to a direction: lateral dodges must work.
		if e.phase_time > 0.18 && e.sees_player {
			lead := enemy_lead(e, rush_speed, e.phase_time)
			e.attack_direction = normalized(Vec3{lead.x, 0, lead.z})
		}
		e.facing = e.attack_direction
		if e.phase_time <= 0 {
			e.phase, e.phase_time, e.velocity = .Attack, 0.48, e.attack_direction*rush_speed+Vec3{0, 7.5, 0}
			sound_event(g, .RabbitBite, e.position)
		}
	case .Attack:
		before := e.position
		blocked := move_enemy(g, e, e.attack_direction*rush_speed+Vec3{0, vertical, 0}, dt)
		motion := e.position-before
		target := g.player.position+Vec3{0, 0.85, 0}
		reach := 0.6+enemy_scale(e.kind)*0.65
		t, hit := ray_sphere(before, normalized(motion), target, reach, length(motion))
		contact := before+normalized(motion)*t
		if !hit && length(e.position-target) < reach { hit, contact = true, e.position }
		hit = hit && player_hit_visible(g.world, g.player.position, contact)
		if hit { damage(g, f32(34 if e.kind == .Rabbit else (23 if e.kind == .Rabbit_Young else 15))*profile.damage, .Rabbit) }
		if hit || blocked || e.phase_time <= 0 {
			e.phase, e.phase_time = .Recover, 0.58+temperament*0.15
			e.velocity.x, e.velocity.z = 0, 0
		}
	case .Recover:
		if e.phase_time <= 0 { e.phase, e.fire_timer = .Patrol, (0.24-temperament*0.14)*profile.cooldown }
	case .Dormant, .Hatching: unreachable()
	}
}
