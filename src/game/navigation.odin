package game

import "core:math"

enemy_scale :: proc(kind: Enemy_Kind) -> f32 {
	switch kind {
	case .Sentry: return 0.85
	case .Interceptor: return 0.70
	case .Crab: return 1.30
	case .Kettle: return 1.70
	case .Nanny: return 1.25
	case .Rabbit: return 2.4
	case .Rabbit_Young: return 1.4
	case .Rabbit_Kit: return 0.88
	}
	unreachable()
}

enemy_extent :: proc(kind: Enemy_Kind) -> Vec3 { return enemy_model_extent(kind)*enemy_scale(kind) }

enemy_model_extent :: proc(kind: Enemy_Kind) -> Vec3 {
	switch kind {
	case .Crab: return {1.05, 0.65, 1.05}
	case .Kettle: return {0.72, 0.9, 0.72}
	case .Nanny: return {0.80, 1.1, 0.80}
	case .Rabbit, .Rabbit_Young, .Rabbit_Kit: return {0.68, 0.72, 0.82}
	case .Sentry, .Interceptor: return {0.48, 1.07, 0.62}
	}
	unreachable()
}

enemy_grounded_kind :: proc(kind: Enemy_Kind) -> bool { return kind == .Crab || kind == .Kettle || kind == .Nanny || rabbit_kind(kind) }

// Bounded breadth-first search of the authored room graph. Perception schedules
// this work; an idle actor does not find a path every simulation tick.
enemy_route_goal :: proc(w: ^World, start, target: Vec3, kind: Enemy_Kind) -> (Vec3, bool) {
	r := &w.sector
	if r.count == 0 { return target, true }
	from, to := room_at(r, start), room_at(r, target)
	if from < 0 || to < 0 { return start, false }
	if from == to { return enemy_room_goal(w, from, start, target, kind) }
	previous, via: [SECTOR_ROOM_CAPACITY]int
	for &p in previous { p = -1 }
	queue: [SECTOR_ROOM_CAPACITY]int
	queue[0], previous[from] = from, from
	head, tail := 0, 1
	extent := enemy_extent(kind)
	for head < tail && previous[to] < 0 {
		current := queue[head]
		head += 1
		id := r.sections[current].id
		for i in 0..<r.connection_count {
			c := r.connections[i]
			if gate_blocks_link(w, c, kind) { continue }
			other := c.b if c.a == id else (c.a if c.b == id else Room_ID(0))
			if other == 0 || c.width < extent.x*2+0.3 || c.height < extent.y*2+0.2 { continue }
			next := room_index(r, other)
			if previous[next] >= 0 { continue }
			if enemy_grounded_kind(kind) && (abs(c.position.y-r.sections[current].origin.y) > 0.5 || abs(c.position.y-r.sections[next].origin.y) > 0.5) { continue }
			previous[next], via[next] = current, i
			queue[tail] = next
			tail += 1
		}
	}
	if previous[to] < 0 { return start, false }
	next := to
	for previous[next] != from { next = previous[next] }
	c := r.connections[via[next]]
	s := &r.sections[from]
	x_side := abs(abs(c.position.x-s.origin.x)-s.width*0.5) < 0.05
	normal := Vec3{0, 0, 1 if c.position.z > s.origin.z else -1}
	if x_side { normal = {1 if c.position.x > s.origin.x else -1, 0, 0} }
	goal := c.position+normal*(extent.x+0.75)
	goal.y = c.position.y+extent.y+0.03 if enemy_grounded_kind(kind) else clamp(start.y, c.position.y+extent.y+0.15, c.position.y+c.height-extent.y-0.15)
	return enemy_room_goal(w, from, start, goal, kind)
}

enemy_ground_supported :: proc(w: ^World, e: ^Enemy, offset: Vec3) -> bool {
	feet := e.position+Vec3{offset.x, 0.35-enemy_extent(e.kind).y, offset.z}
	// Allow steps and descending ramps, but do not voluntarily walk into a gap.
	return world_ray(w, feet, {0, -1, 0}, 1.7) < 1.7
}

// Convex cover is skirted with short swept probes. A persistent side preference
// prevents a centred obstacle from making an actor switch sides every frame.
enemy_steer :: proc(g: ^State, e: ^Enemy, goal: Vec3, speed: f32) -> Vec3 {
	delta := goal-e.position
	if enemy_grounded_kind(e.kind) { delta.y = 0 }
	distance := length(delta)
	if distance < 0.08 { return {} }
	direction := normalized(delta+e.separation)
	// Pack spacing must retain its influence even when the target is far away.
	if rabbit_kind(e.kind) { direction = normalized(delta/distance+e.separation*2.2) }
	travel := min(2.5, distance)
	extent := enemy_extent(e.kind)
	origin := e.position+Vec3{0, 0.025, 0}
	fraction, _ := world_sweep(g.world, origin, direction*travel, extent)
	grounded := enemy_grounded_kind(e.kind)
	if grounded && !enemy_ground_supported(g.world, e, direction*travel) { fraction = 0 }
	if fraction < 0.98 {
		side := f32(1 if e.generation%2 == 0 else -1)
		best, score := Vec3{}, f32(-1e6)
		for i in 0..<8 {
			angle := f32(i/2+1)*math.PI/6*(side if i%2 == 0 else -side)
			candidate := Vec3{direction.x*math.cos(angle)-direction.z*math.sin(angle), direction.y, direction.x*math.sin(angle)+direction.z*math.cos(angle)}
			clearance, _ := world_sweep(g.world, origin, candidate*travel, extent)
			if grounded && !enemy_ground_supported(g.world, e, candidate*travel) { clearance = 0 }
			value := clearance*3+dot(candidate, direction)*0.65+(0.12 if i%2 == 0 else 0)
			if value > score { best, score = candidate*clamp(clearance*2, 0, 1), value }
		}
		direction = best
	}
	return direction*min(speed, distance*2.5)
}

player_noise :: proc(g: ^State, position: Vec3, radius: f32) {
	g.player_noise.position, g.player_noise.radius, g.player_noise.life = position, radius, 0.25
	g.player_noise.sequence += 1
}

enemy_sense :: proc(g: ^State, e: ^Enemy, index: int, dt: f32) {
	e.memory_time = max(0, e.memory_time-dt)
	e.nav_time = max(0, e.nav_time-dt)
	if e.sight_timer > 0 { return }
	e.sight_timer = 0.1
	target := g.player.position+Vec3{0, 0.9, 0}
	delta := target-e.position
	distance := length(delta)
	radius := e.awareness if e.awareness > 0 else f32(80)
	if !enemy_grounded_kind(e.kind) { radius *= 0.9 }
	direction := normalized(delta)
	// Close motion is noticed even behind the initial viewing direction.
	in_view := e.alerted || distance < 5 || dot(direction, e.facing) > -0.15
	e.sees_player = distance < radius && in_view && world_ray(g, e.position, direction, distance) >= distance-0.1
	if e.sees_player {
		if !e.alerted { e.fire_timer = min(e.fire_timer, 0.06+f32(index%4)*0.07) }
		e.last_known, e.memory_time, e.alerted = target, 12, true
		e.known_velocity = g.player.velocity
	} else if g.player_noise.life > 0 && g.player_noise.sequence != e.heard_sequence {
		e.heard_sequence = g.player_noise.sequence
		noise_delta := g.player_noise.position-e.position
		noise_distance := length(noise_delta)
		if noise_distance < g.player_noise.radius {
			clear := world_ray(g, e.position, normalized(noise_delta), noise_distance) >= noise_distance-0.1
			if clear || noise_distance < g.player_noise.radius*0.4 {
				e.last_known, e.memory_time, e.alerted = g.player_noise.position, 5, true
				e.known_velocity = {}
			}
		}
	}
	if e.memory_time <= 0 && e.phase == .Patrol { e.alerted = false }
	if !e.alerted { return }
	if e.nav_time <= 0 {
		e.nav_goal, _ = enemy_route_goal(g.world, e.position, e.last_known, e.kind)
		e.nav_time = 0.25
	}
	e.separation = {}
	pack := rabbit_kind(e.kind)
	extent := enemy_extent(e.kind)
	for other, i in g.enemies[:g.enemy_count] {
		if i == index || !enemy_active(other) { continue }
		offset := e.position-other.position
		offset.y = 0
		gap := length(offset)
		personal_space := f32(2.6)
		if pack {
			shape := enemy_extent(other.kind)
			personal_space = max(extent.x, extent.z)+max(shape.x, shape.z)+1.1
		}
		if gap >= personal_space || abs(e.position.y-other.position.y) >= 2 { continue }
		if gap > 0.01 {
			e.separation += offset*((personal_space-gap)/(gap*personal_space))
		} else if pack {
			// Exact overlaps need opposite escape directions too, e.g. births
			// squeezed into the same clear corner next to a wall.
			e.separation.x += 1 if index < i else -1
		}
	}
}
