package game

import "core:math"

Hit_Zone :: enum u8 { None, Body, Armour, Weak }

enemy_basis :: proc(facing: Vec3) -> (Vec3, Vec3, Vec3) {
	f := normalized(facing)
	if length(f) < 0.5 { f = {0, 0, 1} }
	helper := Vec3{0, 1, 0} if abs(f.y) < 0.95 else Vec3{0, 0, 1}
	right := normalized(cross(f, helper))
	return right, cross(right, f), f
}

crab_open :: proc(e: $E) -> bool {
	return e.exposed > 0 || e.phase == .Recover || enemy_charge(e) > 0.29
}

enemy_weak_spot :: proc(e: $E) -> (Vec3, f32, bool) {
	point, radius, exposed := enemy_model_weak_spot(e)
	scale := enemy_scale(e.kind)
	return e.position+(point-e.position)*scale, radius*scale, exposed
}

enemy_model_weak_spot :: proc(e: $E) -> (Vec3, f32, bool) {
	_, up, f := enemy_basis(e.facing)
	switch e.kind {
	case .Sentry: return e.position+f*0.78, 0.20, e.phase == .Windup
	case .Interceptor: return e.position-f*0.36+up*0.30, 0.23, e.phase == .Recover
	case .Crab: return e.position+f*0.74+up*0.08, 0.25, crab_open(e)
	case .Kettle: return e.position+up*0.83, 0.20, e.phase == .Windup || e.phase == .Recover
	case .Nanny: return e.position+up*1.03, 0.22, e.phase == .Windup || e.phase == .Attack
	case .Rabbit, .Rabbit_Young, .Rabbit_Kit: return e.position+f*0.92+up*0.16, 0.25, e.phase == .Windup || e.phase == .Recover
	}
	unreachable()
}

// Directions are unit length, as for ray_sphere. Reject distant misses before
// building a basis or solving the detailed hit volumes. The bound includes the
// closed crab plate's outer corners (1.37 model units) and every exposed insert.
enemy_hit :: proc(e: $E, origin, direction: Vec3, limit: f32) -> (f32, Hit_Zone) {
	if !enemy_active(e) { return limit, .None }
	relative := e.position-origin
	closest := relative-direction*clamp(dot(relative, direction), 0, limit)
	radius := 1.4*enemy_scale(e.kind)+0.001
	if dot(closest, closest) > radius*radius { return limit, .None }
	return enemy_hit_exact(e, origin, direction, limit)
}

// Keep the narrow query independent so tests can check that the conservative
// rejection never discards body, armour or weak-spot intersections.
enemy_hit_exact :: proc(e: $E, origin, direction: Vec3, limit: f32) -> (f32, Hit_Zone) {
	if !enemy_active(e) { return limit, .None }
	right, up, f := enemy_basis(e.facing)
	radii := Vec3{0.34, 0.93, 0.34}
	if e.kind == .Interceptor { radii = {0.34, 0.93, 0.34} }
	if e.kind == .Crab { radii = {0.79, 0.49, 0.82} }
	if e.kind == .Kettle { radii = {0.62, 0.63, 0.65} }
	if e.kind == .Nanny { radii = {0.63, 0.71, 0.78} }
	if rabbit_kind(e.kind) { radii = {0.62, 0.70, 0.81} }
	scale := enemy_scale(e.kind)
	radii *= scale
	relative := origin-e.position
	p := Vec3{dot(relative, right)/radii.x, dot(relative, up)/radii.y, dot(relative, f)/radii.z}
	d := Vec3{dot(direction, right)/radii.x, dot(direction, up)/radii.y, dot(direction, f)/radii.z}
	a, b, c := dot(d, d), dot(p, d), dot(p, p)-1
	root := b*b-a*c
	distance, zone := limit, Hit_Zone.None
	if root >= 0 && a > 0.00001 {
		t := (-b-math.sqrt(root))/a
		if t < 0 { t = (-b+math.sqrt(root))/a }
		if t >= 0 && t < limit {
			distance, zone = t, .Body
		}
	}
	if rabbit_kind(e.kind) {
		// The projecting muzzle is solid even when the mouth is closed. Its
		// head sphere sits outside part of the broad belly ellipsoid.
		t, hit := ray_sphere(origin, direction, e.position+(f*0.61+up*0.30)*scale, 0.40*scale, distance)
		if hit { distance, zone = t, .Body }
	}
	if e.kind == .Crab && !crab_open(e) {
		// The plate is the rendered 1.27 x 0.60 x 0.13 hinged slab. A broad
		// directional cone wrongly protected visible flank shots missing it.
		plate := e.position+(f*1.05+up*0.17)*scale
		offset := origin-plate
		start := Vec3{dot(offset, right), dot(offset, up), dot(offset, f)}
		dir := Vec3{dot(direction, right), dot(direction, up), dot(direction, f)}
		half := Vec3{0.635, 0.30, 0.065}*scale
		enter, leave := f32(0), distance
		intersects := true
		for axis in 0..<3 {
			if abs(dir[axis]) < 0.000001 {
				if abs(start[axis]) > half[axis] { intersects = false; break }
			} else {
				near, far := (-half[axis]-start[axis])/dir[axis], (half[axis]-start[axis])/dir[axis]
				enter, leave = max(enter, min(near, far)), min(leave, max(near, far))
				if enter > leave { intersects = false; break }
			}
		}
		if intersects && enter < distance { distance, zone = enter, .Armour }
	}
	weak, radius, exposed := enemy_weak_spot(e)
	if exposed {
		t, hit := ray_sphere(origin, direction, weak, radius, limit)
		// The exposed insert sits on the shell; tolerate its small inset, never
		// a shot through the body from the opposite side.
		if hit && t <= distance+0.08 { distance, zone = t, .Weak }
	}
	return distance, zone
}

damage_enemy :: proc(g: ^State, index: int, amount: int, zone: Hit_Zone, point: Vec3, bypass_support: bool = false, dismember: bool = false) -> int {
	e := &g.enemies[index]
	if !enemy_active(e^) || zone == .None { return 0 }
	was_alerted := e.alerted
	e.alerted, e.memory_time, e.nav_time = true, 7, 0
	source := g.player.position+Vec3{0, 0.9, 0}
	delta := source-e.position
	if world_ray(g, e.position, normalized(delta), length(delta)) >= length(delta)-0.05 {
		e.last_known, e.known_velocity = source, g.player.velocity
	} else if !was_alerted {
		// A blast or kick does not reveal the player through several rooms.
		// An audible impact may subsequently supply its own last-known point.
		e.last_known, e.known_velocity = point, {}
	}
	if zone == .Armour {
		e.flash = 0.045
		emit(g, point, 5, 2)
		sound_event(g, .Ricochet, point)
		return 0
	}
	remaining := amount
	if !bypass_support && zone != .Weak { remaining -= absorb_support_shot(g, index, amount, point) }
	if remaining <= 0 { return 0 }
	dealt := remaining*(3 if zone == .Weak else 1)
	e.health -= dealt
	if e.health > 0 { sound_event(g, .FleshHit if enemy_organic(e.kind) else .MetalHit, point) }
	e.flash = 0.13
	g.player.hit_marker = 0.22 if zone == .Weak else 0.15
	emit(g, point, 12 if zone == .Weak else 8, 3 if enemy_organic(e.kind) else 0)
	if zone == .Weak && (e.phase == .Windup || (e.kind == .Nanny && e.phase == .Attack)) {
		e.phase, e.phase_time = .Recover, 0.9 if e.kind == .Crab else 0.55
		e.exposed = e.phase_time
		e.shield = 0
	}
	if e.health <= 0 {
		e.phase, e.phase_time, e.shield = .Recover, enemy_death_duration(e.kind), 0
		e.velocity = e.knockback+normalized(e.position-g.player.position)*2.8+Vec3{0, 2.4, 0}
		e.knockback = {}
		g.kills += 1
		g.kill_sequence += 1
		if dismember || (rabbit_kind(e.kind) && e.kind != .Rabbit_Kit) { gib_enemy(g, e) }
		split_rabbit(g, e)
		if !e.gibbed { sound_event(g, .RabbitDeath if rabbit_kind(e.kind) else (.FaeDeath if enemy_organic(e.kind) else (.SteamBurst if e.kind == .Kettle else .MechanicalBreak)), e.position) }
		organic := enemy_organic(e.kind)
		light_flash(g, e.position, {0.9, 0.08, 0.16} if organic else Vec3{1, 0.3, 0.06}, 9, 5, 0.24)
		emit(g, e.position, 48, 3 if organic else 0)
		emit(g, e.position, 12, 4 if organic else 2)
	}
	return dealt
}
