package game

NANNY_SUPPORT_RANGE :: f32(16)

// The beam and damage absorption must agree, including at the range limit.
nanny_link_clear :: proc(w: ^World, from, to: Vec3) -> bool {
	delta := to-from
	distance := length(delta)
	return distance <= NANNY_SUPPORT_RANGE && world_ray(w, from, normalized(delta), distance) >= distance-0.1
}

// One ally at a time; shields have a finite charge and never form support chains.
// A broken line of sight, a dead/reused slot or a valve hit cancels the channel.
nanny_partner :: proc(g: ^State, e: ^Enemy, index: int) -> ^Enemy {
	partner := find_enemy(g, e.support)
	if partner != nil && partner.kind != .Nanny && nanny_link_clear(g.world, e.position, partner.position) { return partner }
	e.support = {}
	best := NANNY_SUPPORT_RANGE
	for other, i in g.enemies[:g.enemy_count] {
		if i == index || !enemy_active(other) || other.kind == .Nanny || !other.alerted { continue }
		delta := other.position-e.position
		distance := length(delta)
		if distance >= best || !nanny_link_clear(g.world, e.position, other.position) { continue }
		e.support, best = {u32(i), other.generation}, distance
	}
	return find_enemy(g, e.support)
}

update_nanny :: proc(g: ^State, e: ^Enemy, index: int, dt: f32) {
	e.support_time -= dt
	if e.support_time <= 0 {
		partner := find_enemy(g, e.support)
		if e.phase == .Patrol { partner = nanny_partner(g, e, index) }
		e.support_time = 0.25
		if partner != nil && partner.alerted {
			e.alerted, e.memory_time = true, max(3, e.memory_time)
			if !e.sees_player { e.last_known, e.known_velocity = partner.last_known, partner.known_velocity }
		}
	}
	if !e.alerted && e.phase == .Patrol { return }
	partner := find_enemy(g, e.support)
	if partner != nil && !nanny_link_clear(g.world, e.position, partner.position) { partner = nil }
	direction := normalized(e.last_known-e.position)
	direction = normalized(Vec3{direction.x, 0, direction.z})
	e.facing = normalized(e.facing+(direction-e.facing)*min(1, dt*5))
	switch e.phase {
	case .Patrol:
		desired := e.nav_goal
		if partner != nil {
			away := normalized(partner.position-e.last_known)
			desired = partner.position+away*3.2
		} else if e.sees_player { desired = e.last_known-direction*14 }
		velocity := enemy_steer(g, e, desired, enemy_move_speed(.Nanny)*difficulty_profile(g.difficulty).move)
		velocity.y = e.velocity.y
		move_enemy(g, e, velocity, dt)
		if e.fire_timer <= 0 && (partner != nil || e.sees_player) {
			begin_enemy_attack(g, e)
			e.attack_direction = normalized(e.last_known-e.position)
		}
	case .Windup:
		if e.phase_time > 0 { return }
		if partner != nil {
			e.phase, e.phase_time, e.shield = .Attack, 2.4, 6
		} else {
			// A stranded support can defend itself, but is a weak lone opponent.
			muzzle := e.position+e.attack_direction*0.8
			if e.sees_player && world_ray(g, e.position, e.attack_direction, 0.9) >= 0.85 {
				if spawn_projectile(g, {muzzle, enemy_lead(e, 28*difficulty_profile(g.difficulty).projectile)*(28*difficulty_profile(g.difficulty).projectile), 3, .Nanny}) { sound_event(g, .NannyShot, muzzle) }
			}
			e.phase, e.phase_time = .Recover, 0.8
		}
	case .Attack:
		if partner != nil && e.shield > 0 {
			// Stay with an advancing ground ally instead of anchoring the shield
			// to the spot where the channel started. Cover still breaks the link.
			goal := partner.position+normalized(partner.position-e.last_known)*3.2
			velocity := enemy_steer(g, e, goal, 5*difficulty_profile(g.difficulty).move)
			velocity.y = e.velocity.y
			move_enemy(g, e, velocity, dt)
		}
		if partner == nil || e.phase_time <= 0 || e.shield <= 0 {
			sound_event(g, .ShieldBreak, e.position)
			e.phase, e.phase_time, e.shield = .Recover, 1.2, 0
			if partner == nil { e.support = {} }
		}
	case .Dormant, .Hatching: unreachable()
	case .Recover:
		if e.phase_time <= 0 { e.phase, e.fire_timer = .Patrol, (1.5+random(g)*0.7)*difficulty_profile(g.difficulty).cooldown }
	}
}

absorb_support_shot :: proc(g: ^State, victim, amount: int, point: Vec3) -> int {
	for &support in g.enemies[:g.enemy_count] {
		if support.health <= 0 || support.kind != .Nanny || support.phase != .Attack || support.shield <= 0 { continue }
		if int(support.support.slot) != victim || support.support.generation != g.enemies[victim].generation { continue }
		if !nanny_link_clear(g.world, support.position, g.enemies[victim].position) { continue }
		absorbed := min(support.shield, amount)
		support.shield -= absorbed
		emit(g, point, 7, 1)
		light_flash(g, point, {0.2, 1, 0.65}, 2.2, 2, 0.12)
		return absorbed
	}
	return 0
}
