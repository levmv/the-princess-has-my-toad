package game

import "core:math"

dot :: proc(a, b: Vec3) -> f32 {
	return a.x*b.x + a.y*b.y + a.z*b.z
}

length :: proc(v: Vec3) -> f32 {
	return math.sqrt(dot(v, v))
}

normalized :: proc(v: Vec3) -> Vec3 {
	n := length(v)
	if n < 0.00001 { return {} }
	return v / n
}

forward :: proc(yaw, pitch: f32) -> Vec3 {
	return {math.sin(yaw)*math.cos(pitch), math.sin(pitch), -math.cos(yaw)*math.cos(pitch)}
}

approach :: proc(value, target, amount: f32) -> f32 {
	return value + clamp(target-value, -amount, amount)
}

random_stream :: proc(state: ^u32) -> f32 {
	x := state^
	x ~= x << 13
	x ~= x >> 17
	x ~= x << 5
	state^ = x
	return f32(x & 0xFFFFFF) / f32(0x1000000)
}

random :: proc(g: ^State) -> f32 {
	return random_stream(&g.rng)
}

ray_box :: proc(origin, direction: Vec3, block: Block, limit: f32, padding: f32 = 0) -> (f32, bool) {
	lo := block.center - block.size*0.5 - Vec3{padding, padding, padding}
	hi := block.center + block.size*0.5 + Vec3{padding, padding, padding}
	tmin, tmax := f32(0), limit
	for axis in 0..<3 {
		if abs(direction[axis]) < 0.000001 {
			if origin[axis] < lo[axis] || origin[axis] > hi[axis] { return limit, false }
		} else {
			a := (lo[axis]-origin[axis]) / direction[axis]
			b := (hi[axis]-origin[axis]) / direction[axis]
			tmin = max(tmin, min(a, b))
			tmax = min(tmax, max(a, b))
			if tmin > tmax { return limit, false }
		}
	}
	for i in 0..<block.clip_count {
		plane := block.clips[i]
		n := plane.normal
		distance := plane.distance+padding*(abs(n.x)+abs(n.y)+abs(n.z))-dot(n, origin)
		motion := dot(n, direction)
		if abs(motion) < 0.000001 {
			if distance < 0 { return limit, false }
			continue
		}
		t := distance/motion
		if motion < 0 { tmin = max(tmin, t) } else { tmax = min(tmax, t) }
		if tmin > tmax { return limit, false }
	}
	return tmin, true
}

ray_sphere :: proc(origin, direction, center: Vec3, radius, limit: f32) -> (f32, bool) {
	offset := origin-center
	b := dot(offset, direction)
	c := dot(offset, offset)-radius*radius
	d := b*b-c
	if d < 0 { return limit, false }
	t := -b-math.sqrt(d)
	if t < 0 { t = -b+math.sqrt(d) }
	return t, t >= 0 && t < limit
}

camera_arm :: proc(p: ^Player) -> Vec3 {
	right := Vec3{math.cos(p.yaw), 0, math.sin(p.yaw)}
	return -forward(p.yaw, p.pitch)*CAMERA_DISTANCE + Vec3{0, CAMERA_HEIGHT, 0} + right*CAMERA_SIDE
}

camera_near_clip :: proc(fov, aspect: f32) -> f32 {
	// The entire near rectangle must fit inside the camera's collision padding,
	// including its corners when the window is stretched very wide.
	tangent := math.tan(fov*math.PI/360)
	diagonal := math.sqrt(1+tangent*tangent*(1+aspect*aspect))
	return min(CAMERA_NEAR, CAMERA_CLEARANCE*0.9/diagonal)
}

camera :: proc{camera_state, camera_snapshot}
scope_offset :: proc(p: ^Player) -> Vec2 {
	t := p.scope_time
	moving := min(1, length(Vec3{p.velocity.x, 0, p.velocity.z})/RUN_SPEED)
	amount := 0.008+moving*0.006
	return {(math.sin(t*0.95)+math.sin(t*2.13)*0.35)*amount, (math.sin(t*1.25)+math.sin(t*2.7)*0.2)*amount*0.75}
}

camera_state :: proc(g: ^State, focus: bool = false) -> Camera { return camera_pose(g.world, &g.player, focus) }
camera_pose :: proc(w: ^World, p: ^Player, focus: bool = false) -> Camera {
	dir := forward(p.yaw, p.pitch)
	pivot := p.position + Vec3{0, EYE_HEIGHT, 0}
	if focus {
		sway := scope_offset(p)
		dir = forward(p.yaw+sway.x, p.pitch+sway.y)
		return {pivot, dir, pivot+dir*100, SCOPE_FOV, true}
	}
	// Height is independent of aim pitch: see over the suit while aiming ahead.
	// A nearly centred arm keeps movement, the weapon and the reticle on one axis.
	desired := camera_arm(p)
	arm := length(desired)
	arm_dir := normalized(desired)
	clearance := world_ray(w, pivot, arm_dir, arm, CAMERA_CLEARANCE)
	travel := arm if clearance >= arm else max(0, clearance-0.12)
	eye := pivot + arm_dir*travel
	return {eye, dir, eye+dir*100, VIEW_FOV, false}
}

aim_point :: proc{aim_point_state, aim_point_snapshot}
aim_point_state :: proc(g: ^State, cam: Camera) -> Vec3 { return aim_point_pose(g.world, g.enemies[:g.enemy_count], cam, g.boss) }
aim_point_pose :: proc(w: ^World, enemies: $Enemies, cam: Camera, boss: Boss_State = {}) -> Vec3 {
	range := world_ray(w, cam.position, cam.forward, 110)
	button_distance, button := lift_button_hit(w, cam.position, cam.forward, range)
	if button { range = button_distance }
	for enemy in enemies {
		if enemy.health <= 0 { continue }
		t, zone := enemy_hit(enemy, cam.position, cam.forward, range)
		if zone != .None { range = t }
	}
	t, zone := boss_hit(w, boss, cam.position, cam.forward, range)
	if zone != .None { range = t }
	return cam.position+cam.forward*range
}

aim_at :: proc(g: ^State, target: Vec3, focused: bool) {
	p := &g.player
	pivot := p.position+Vec3{0, EYE_HEIGHT, 0}
	fraction := f32(0) if focused else f32(1)
	for _ in 0..<12 {
		// Solve the elevated/sideways camera anchor directly. Distance along the
		// viewing axis cancels out, so close targets do not require slow iteration.
		delta := target-pivot-Vec3{0, CAMERA_HEIGHT*fraction, 0}
		if length(delta) < 0.0001 { break }
		horizontal := math.sqrt(delta.x*delta.x+delta.z*delta.z)
		p.yaw = math.atan2(delta.x, -delta.z)-math.asin(clamp(CAMERA_SIDE*fraction/max(horizontal, 0.0001), -1, 1))
		right := Vec3{math.cos(p.yaw), 0, math.sin(p.yaw)}
		dir := normalized(delta-right*CAMERA_SIDE*fraction)
		p.pitch = clamp(math.asin(clamp(dir.y, -1, 1)), -1.2, 1.15)
		if focused {
			sway := scope_offset(p)
			p.yaw -= sway.x
			// Compensating scope sway must preserve the input/save pitch range,
			// including when switching focus at the upper or lower limit.
			p.pitch = clamp(p.pitch-sway.y, -1.2, 1.15)
			break
		}
		// Only an obstructed camera needs another pass with its shorter arm.
		cam := camera(g)
		actual_fraction := length(cam.position-pivot)/length(camera_arm(p))
		if abs(actual_fraction-fraction) < 0.00001 { break }
		fraction = actual_fraction
	}
}

change_focus :: proc(g: ^State, was_focused, focused: bool) {
	g.focused = focused
	if was_focused == focused { return }
	// Preserve the actual point under the crosshair, including nearby targets.
	aim_at(g, aim_point(g, camera(g, was_focused)), focused)
}

weapon_muzzle :: proc{weapon_muzzle_state, weapon_muzzle_snapshot}
weapon_muzzle_state :: proc(g: ^State) -> Vec3 { return weapon_muzzle_pose(g.world, &g.player) }
weapon_muzzle_pose :: proc(w: ^World, p: ^Player) -> Vec3 {
	right := Vec3{math.cos(p.yaw), 0, math.sin(p.yaw)}
	origin := p.position+Vec3{0, 1.28, 0}
	arm := right*0.27+forward(p.yaw, 0)*0.6
	distance := world_ray(w, origin, normalized(arm), length(arm), 0.03)
	return origin+normalized(arm)*max(0, distance-0.04)
}
