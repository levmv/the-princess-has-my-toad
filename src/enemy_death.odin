package main

import "core:math"
import game "game"

CORPSE_PART_CAPACITY :: 8
Corpse_Cache :: struct {
	facing: game.Vec3,
	kind: game.Enemy_Kind,
	hull_bottom: f32,
	parts: [CORPSE_PART_CAPACITY]f32,
	valid: bool,
}

// Query the supporting body and detached pieces, not a simulated ragdoll.
// CPU vertex arrays already belong to the renderer; this bounded reduction
// allocates nothing and avoids the empty corners of a rotated bounding box.
enemy_part_bottom :: proc(r: ^Renderer, command: ^Object_Command) -> f32 {
	mesh := r.objects.models[command.kind].mesh
	m := command.instance.transform
	bottom := f32(1e9)
	for i in 0..<int(mesh.vertexCount) {
		v := mesh.vertices
		y := m[3][1]+v[i*3]*m[0][1]+v[i*3+1]*m[1][1]+v[i*3+2]*m[2][1]
		bottom = min(bottom, y)
	}
	return bottom
}

enemy_detached_part :: proc(kind: Model_Kind) -> bool {
	return kind == .EnemyFin || kind == .CrabPlate || kind == .KettleLid || kind == .NannyUmbrella || kind == .NannyWheel
}

// Deaths reuse the actor meshes but articulate and detach different pieces.
// Both world and shadow passes see these same transformed instances.
draw_enemy_death :: proc(r: ^Renderer, dead: game.Enemy_Pose, time: f32, cache: ^Corpse_Cache = nil) {
	if dead.gibbed { draw_gibbed_corpse(r, dead); return }
	progress := clamp(1-dead.phase_time/game.enemy_death_duration(dead.kind), 0, 1)
	scale := f32(1)
	e := dead
	e.phase, e.shielding, e.flash = .Recover, false, 0
	start := r.objects.count
	e.gait_phase = 0
	draw_enemy(r, e, 0)
	right, up, f := game.enemy_basis(dead.facing)
	x, y, z := right, up, f
	angle := progress*2.7
	switch dead.kind {
	case .Sentry: angle = progress*1.65
	case .Interceptor: angle = progress*1.9
	case .Crab: angle = min(1, progress*2)*2.8
	case .Kettle: angle = progress*1.3
	case .Nanny: angle = progress*0.8
	case .Rabbit, .Rabbit_Young, .Rabbit_Kit: angle = progress*1.65
	}
	if dead.kind == .Interceptor || dead.kind == .Kettle { y, z = up*math.cos(angle)-f*math.sin(angle), up*math.sin(angle)+f*math.cos(angle)
	} else { x, y = right*math.cos(angle)+up*math.sin(angle), -right*math.sin(angle)+up*math.cos(angle) }
	for &command in r.objects.commands[start:r.objects.count] {
		instance := &command.instance
		position := game.Vec3{instance.transform[3][0], instance.transform[3][1], instance.transform[3][2]}
		delta := position-dead.position
		detach: game.Vec3
		if (dead.kind == .Sentry || dead.kind == .Interceptor) && command.kind == .EnemyFin { detach = right*(1 if game.dot(delta, right) > 0 else f32(-1))*progress*1.1+f*progress*0.45 }
		if dead.kind == .Crab && command.kind == .CrabPlate { detach = f*progress*0.7+up*progress*0.4 }
		if dead.kind == .Kettle && command.kind == .KettleLid { detach = up*math.sin(progress*math.PI)*1.7+right*progress*0.6 }
		if dead.kind == .Nanny && command.kind == .NannyUmbrella { detach = -up*progress*0.45-f*progress*0.8 }
		if dead.kind == .Nanny && command.kind == .NannyWheel { detach = right*game.dot(delta, right)*progress*0.8 }
		position = dead.position+(x*game.dot(delta, right)+y*game.dot(delta, up)+z*game.dot(delta, f))*scale+detach*scale
		instance.transform[3] = {position.x, position.y, position.z, 1}
		for axis in 0..<3 {
			column := instance.transform[axis]
			v := game.Vec3{column[0], column[1], column[2]}
			rotated := (x*game.dot(v, right)+y*game.dot(v, up)+z*game.dot(v, f))*scale
			instance.transform[axis] = {rotated.x, rotated.y, rotated.z, 0}
			normal := instance.normal[axis]
			v = {normal[0], normal[1], normal[2]}
			rotated = (x*game.dot(v, right)+y*game.dot(v, up)+z*game.dot(v, f))/scale
			instance.normal[axis] = {rotated.x, rotated.y, rotated.z, 0}
		}
		for channel in 0..<3 { instance.tint[channel] *= 0.65 }
		if command.kind == .EnemyFin {
			// Torn membranes turn broadside as they fall, then lie flat. A wing
			// left in the actor's roll would balance unnaturally on its edge.
			a, b := instance.transform[0], instance.transform[1]
			n := game.normalized(game.cross({a[0], a[1], a[2]}, {b[0], b[1], b[2]}))
			target := game.Vec3{0, 1 if n.y >= 0 else -1, 0}
			axis := game.normalized(game.cross(n, target))
			turn := math.acos(clamp(game.dot(n, target), -1, 1))*progress
			for basis in 0..<2 {
				for col in 0..<3 {
					v := instance.transform[col] if basis == 0 else instance.normal[col]
					p := game.Vec3{v[0], v[1], v[2]}
					q := p*math.cos(turn)+game.cross(axis, p)*math.sin(turn)+axis*game.dot(axis, p)*(1-math.cos(turn))
					if basis == 0 { instance.transform[col] = {q.x, q.y, q.z, 0} } else { instance.normal[col] = {q.x, q.y, q.z, 0} }
				}
			}
		}
	}
	// The upright collision centre remains useful to physics and saves, but a
	// toppled hull no longer rests on its upright feet. Settle shell and loose
	// pieces independently onto that same supporting floor, smoothly over the
	// fall. Even high falls keep following their real swept actor position.
	ground := dead.position.y-game.enemy_extent(dead.kind).y+0.025
	settled := progress >= 1 && cache != nil
	// Interpolation can renormalize an unchanged direction by one float ULP.
	// Ignore that noise without reusing a meaningfully different orientation.
	reuse := settled && cache.valid && cache.kind == dead.kind && game.dot(cache.facing-dead.facing, cache.facing-dead.facing) < 1e-10
	hull_bottom := f32(1e9)
	if reuse { hull_bottom = dead.position.y+cache.hull_bottom
	} else {
		for &command in r.objects.commands[start:r.objects.count] {
			if ((dead.kind == .Sentry || dead.kind == .Interceptor) && !enemy_detached_part(command.kind)) || game.rabbit_kind(dead.kind) || command.kind == .CrabShell || command.kind == .KettleBody || command.kind == .NannyBody {
				hull_bottom = min(hull_bottom, enemy_part_bottom(r, &command))
			}
		}
	}
	part := 0
	for &command in r.objects.commands[start:r.objects.count] {
		bottom := hull_bottom
		if enemy_detached_part(command.kind) {
			assert(part < CORPSE_PART_CAPACITY)
			bottom = dead.position.y+cache.parts[part] if reuse else enemy_part_bottom(r, &command)
			if settled && !reuse { cache.parts[part] = bottom-dead.position.y }
			part += 1
		}
		command.instance.transform[3][1] += (ground-bottom)*progress*progress
	}
	// Resting articulation depends on kind and facing, not translation. Cache
	// its support offsets so a room full of old wrecks never rescans vertices.
	if settled && !reuse { cache.hull_bottom, cache.kind, cache.facing, cache.valid = hull_bottom-dead.position.y, dead.kind, dead.facing, true }
	if game.enemy_organic(dead.kind) && progress > 0.6 {
		// A stain belongs to the supporting floor, never floats under a falling corpse.
		distance := game.world_ray(r.world_source, dead.position, {0, -1, 0}, game.enemy_extent(dead.kind).y+0.12)
		if distance < game.enemy_extent(dead.kind).y+0.10 {
			for patch in 0..<3 {
				size := (0.50-f32(patch)*0.10)*progress
				p := dead.position+game.Vec3{f32(patch-1)*0.22, -distance+0.018+f32(patch)*0.003, f32(patch%2)*0.18}
				object_instance(r, .BloodSplat, p, {size, 0, 0}, {0, 1, 0}, {0, 0, size*0.70}, {105, 9, 15, 255})
			}
		}
	}
}
