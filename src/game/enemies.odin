package game

import "core:math"

// Swept movement is shared with the level's real collision geometry.
move_enemy :: proc(g: ^State, e: ^Enemy, velocity: Vec3, dt: f32) -> bool {
	v := velocity
	remaining := dt
	blocked := false
	before := e.position
	for _ in 0..<3 {
		delta := v*remaining
		distance := length(delta)
		if distance < 0.00001 { break }
		fraction, normal := world_sweep(g.world, e.position, delta, enemy_extent(e.kind))
		e.position += delta*max(0, fraction-CONTACT_MARGIN/distance)
		if fraction >= 1 { break }
		if !enemy_grounded_kind(e.kind) || normal.y < 0.65 { blocked = true }
		v -= normal*min(0, dot(v, normal))
		remaining *= 1-fraction
	}
	e.velocity = v
	motion := e.position-before
	stride := 1.8/enemy_scale(e.kind) if rabbit_kind(e.kind) else f32(3.5)
	e.gait_phase = math.mod(e.gait_phase+length(Vec3{motion.x, 0, motion.z})*stride, 2*math.PI)
	return blocked
}

enemy_windup :: proc(kind: Enemy_Kind) -> f32 {
	switch kind {
	case .Sentry: return 0.6
	case .Interceptor: return 0.72
	case .Crab: return 0.68
	case .Kettle: return 0.65
	case .Nanny: return 0.85
	case .Rabbit: return 0.58
	case .Rabbit_Young: return 0.48
	case .Rabbit_Kit: return 0.40
	}
	unreachable()
}

// Solve the intercept using the last observed motion, never the hidden player.
// A bounded lead rewards changing direction, unlike a slow bolt aimed behind
// a runner. The last part of a windup still commits before the first shot.
enemy_lead :: proc(e: ^Enemy, speed: f32, delay: f32 = 0) -> Vec3 {
	delta := e.last_known+e.known_velocity*delay-e.position
	v := e.known_velocity
	a, b, c := dot(v, v)-speed*speed, 2*dot(delta, v), dot(delta, delta)
	t := length(delta)/speed
	discriminant := b*b-4*a*c
	if abs(a) > 0.001 && discriminant >= 0 {
		root := math.sqrt(discriminant)
		x, y := (-b-root)/(2*a), (-b+root)/(2*a)
		if x > 0 { t = x }
		if y > 0 && (x <= 0 || y < x) { t = y }
	}
	return normalized(delta+v*clamp(t, 0, 2.2))
}

enemy_move_speed :: proc(kind: Enemy_Kind) -> f32 {
	switch kind {
	case .Sentry: return 8
	case .Interceptor: return 13
	case .Crab: return 12
	case .Kettle: return 9
	case .Nanny: return 7
	case .Rabbit: return 14
	case .Rabbit_Young: return 16.5
	case .Rabbit_Kit: return 19
	}
	unreachable()
}

update_enemies :: proc(g: ^State, dt: f32) {
	profile := difficulty_profile(g.difficulty)
	g.player_noise.life = max(0, g.player_noise.life-dt)
	target := g.player.position+Vec3{0, 0.9, 0}
	for &e, i in g.enemies[:g.enemy_count] {
		if g.respawn_pending { return }
		if e.phase == .Dormant { continue }
		if e.phase == .Hatching {
			e.phase_time = max(0, e.phase_time-dt)
			if e.phase_time <= 0 { e.phase = .Patrol }
			continue
		}
		if e.position.y < VOID_HEIGHT { retire_fallen_enemy(g, &e); continue }
		if e.health <= 0 { update_enemy_death(g, &e, dt); continue }
		if length(e.knockback) > 0.03 {
			velocity := e.velocity
			move_enemy(g, &e, e.knockback, dt)
			e.knockback = e.velocity*max(0, 1-dt*7)
			e.velocity = velocity
		}
		e.flash = max(0, e.flash-dt)
		e.exposed = max(0, e.exposed-dt)
		e.fire_timer -= dt
		e.sight_timer = max(0, e.sight_timer-dt)
		e.phase_time = max(0, e.phase_time-dt)
		enemy_sense(g, &e, i, dt)
		if rabbit_kind(e.kind) { update_rabbit(g, &e, dt); continue }
		if enemy_grounded_kind(e.kind) && !(e.kind == .Kettle && e.phase == .Attack) { move_enemy(g, &e, {0, max(-20, e.velocity.y-GRAVITY*dt), 0}, dt) }
		if e.kind == .Nanny { update_nanny(g, &e, i, dt); continue }
		if !e.alerted && e.phase == .Patrol { continue }
		known_delta := e.last_known-e.position
		distance := length(known_delta)
		direction := normalized(known_delta)
		if enemy_grounded_kind(e.kind) { direction = normalized(Vec3{direction.x, 0, direction.z}) }
		switch e.phase {
		case .Patrol:
			if distance > 0.3 { e.facing = normalized(e.facing+(direction-e.facing)*min(1, dt*(6 if e.kind == .Crab else 7))) }
			desired := e.nav_goal
			if e.sees_player {
				range := f32(16)
				if e.kind == .Interceptor { range = 6 }
				if e.kind == .Crab { range = 1.9 }
				if e.kind == .Kettle { range = 9 }
				desired = e.last_known-direction*range
				// Cut across a visible runner's path while keeping the plate forward.
				if e.kind == .Crab { desired += e.known_velocity*0.3 }
				if e.kind == .Sentry {
					side := normalized(cross(direction, Vec3{0, 1, 0}))
					desired += side*math.sin(g.time*0.65+f32(i)*1.71)*2
				}
			}
			velocity := enemy_steer(g, &e, desired, enemy_move_speed(e.kind)*profile.move)
			if enemy_grounded_kind(e.kind) { velocity.y = e.velocity.y }
			move_enemy(g, &e, velocity, dt)
			// A rush must actually reach the distance at which it is started.
			range := f32(86 if e.kind == .Sentry else (23*profile.move*0.55-0.5 if e.kind == .Interceptor else (30 if e.kind == .Kettle else 13.5)))
			if e.sees_player && distance < range && e.fire_timer <= 0 {
				if world_ray(g, e.position, normalized(target-e.position), length(target-e.position)) < length(target-e.position)-0.1 { continue }
				begin_enemy_attack(g, &e)
				e.attack_direction = direction
				if e.kind == .Sentry { e.attack_direction = enemy_lead(&e, 36*profile.projectile, e.windup_duration) }
				if e.kind == .Kettle { kettle_target(g, &e) }
				e.velocity = {}
			}
		case .Windup:
			// The committed final 200 ms never tracks a dodge or a hidden target.
			if e.phase_time > 0.2 && e.sees_player && e.kind != .Kettle {
				e.attack_direction = enemy_lead(&e, (36*profile.projectile if e.kind == .Sentry else (CRAB_RUSH_SPEED if e.kind == .Crab else 23)*profile.move), e.phase_time)
				if e.kind == .Crab { e.attack_direction = normalized(Vec3{e.attack_direction.x, 0, e.attack_direction.z}) }
			}
			if e.kind == .Kettle && e.phase_time > 0.24 && e.sees_player { kettle_target(g, &e) }
			e.facing = e.attack_direction
			if e.phase_time <= 0 {
				e.phase, e.rounds = .Attack, 2 if e.kind == .Sentry else 3
				e.phase_time = 0.55 if e.kind == .Interceptor else (0.5 if e.kind == .Crab else 0)
				if e.kind == .Kettle { kettle_launch(&e) }
				if e.kind == .Crab {
					sound_event(g, .ClawSnap, e.position)
					light_flash(g, e.position+e.facing, {0.3, 0.9, 0.45}, 3, 2, 0.12)
				}
			}
		case .Attack:
			e.facing = e.attack_direction
			switch e.kind {
			case .Interceptor:
				before := e.position
				blocked := move_enemy(g, &e, e.attack_direction*(23*profile.move), dt)
				motion := e.position-before
				motion_direction := normalized(motion)
				contact_distance, hit := ray_sphere(before, motion_direction, target, 1.05, length(motion))
				contact := before+motion_direction*contact_distance
				if !hit && length(e.position-target) < 1.05 { hit, contact = true, e.position }
				// Claws have some reach, but their contact margin cannot extend
				// through cover. Test at impact, before sliding farther along a wall.
				if hit && player_hit_visible(g.world, g.player.position, contact) { damage(g, 22*profile.damage, .Hunter); blocked = true }
				if blocked || e.phase_time <= 0 {
					if blocked { sound_event(g, .ClawSnap, e.position) }
					e.phase, e.phase_time = .Recover, 0.95
					e.velocity = {}
				}
			case .Crab:
				update_crab_rush(g, &e, dt)
			case .Sentry:
				if e.phase_time > 0 { continue }
				// Follow-up rounds reacquire only a visible target. A burst is now
				// sustained pressure instead of three copies of a stale miss.
				if e.rounds < 2 && e.sees_player { e.attack_direction = enemy_lead(&e, 36*profile.projectile) }
				muzzle := e.position+e.attack_direction*0.85
				if world_ray(g, e.position, e.attack_direction, 1) < 0.95 {
					e.phase, e.phase_time = .Recover, 0.45
					continue
				}
				if !spawn_projectile(g, {muzzle, e.attack_direction*(36*profile.projectile), 3.6, .Fairy}) {
					e.phase_time = 0.1
					continue
				}
				light_flash(g, muzzle, {1, 0.25, 0.05}, 2.2, 1.8, 0.08)
				sound_event(g, .EnemyShot, muzzle)
				e.rounds -= 1
				e.phase_time = 0.21
				if e.rounds == 0 { e.phase, e.phase_time = .Recover, 0.45 }
			case .Kettle: update_kettle_leap(g, &e, dt)
			case .Nanny, .Rabbit, .Rabbit_Young, .Rabbit_Kit: unreachable()
			}
		case .Dormant, .Hatching: unreachable()
		case .Recover:
			if e.phase_time <= 0 {
				e.phase = .Patrol
				e.fire_timer = (0.25+random(g)*0.35)*profile.cooldown*(1.10 if e.kind == .Sentry else f32(1))
			}
		}
	}
}
