package game

import "core:math"

TUNNEL_X :: f32(-9)
TUNNEL_Z_NEAR :: f32(18)
TUNNEL_Z_FAR :: f32(6)
TUNNEL_PROFILE :: [8]Vec2{
	{-3.2, 1.0}, {-3.45, 2.8}, {-2.65, 4.7}, {-1.6, 5.45},
	{1.6, 5.45}, {2.65, 4.7}, {3.45, 2.8}, {3.2, 1.0},
}

cross :: proc(a, b: Vec3) -> Vec3 {
	return {a.y*b.z-a.z*b.y, a.z*b.x-a.x*b.z, a.x*b.y-a.y*b.x}
}

box_overlaps_solid :: proc(center, extent: Vec3, b: ^Block) -> bool {
	for i in 0..<6+b.clip_count {
		plane := block_plane(b, i)
		n := plane.normal
		if dot(n, center)-plane.distance >= abs(n.x)*extent.x+abs(n.y)*extent.y+abs(n.z)*extent.z-CONTACT_MARGIN { return false }
	}
	return true
}

// Used for rare placement, not the hot movement query. The same expanded
// planes as world_sweep reject starts embedded in bevels, roofs or doors.
world_clear_box :: proc(w: ^World, center, extent: Vec3) -> bool {
	for &b in w.blocks { if box_overlaps_solid(center, extent, &b) { return false } }
	for gate in w.gates[:w.gate_count] {
		b := gate_shape(gate)
		if box_overlaps_solid(center, extent, &b) { return false }
	}
	return true
}

block_plane :: proc(b: ^Block, index: int) -> Plane {
	if index >= 6 { return b.clips[index-6] }
	axis := index/2
	sign := f32(-1) if index%2 == 0 else f32(1)
	n: Vec3
	n[axis] = sign
	return {n, b.center[axis]*sign+b.size[axis]*0.5}
}

clip_block :: proc(b: ^Block, normal: Vec3, point: Vec3) {
	assert(b.clip_count < len(b.clips))
	n := normalized(normal)
	b.clips[b.clip_count] = {n, dot(n, point)}
	b.clip_count += 1
}

bevel_block :: proc(b: ^Block, corner, rim: f32) {
	half := b.size*0.5
	cut := min(corner, min(half.x, half.z)*0.6)
	signs := [2]f32{-1, 1}
	for x in signs {
		for z in signs {
			n := Vec3{x, 0, z}
			point := b.center+Vec3{x*(half.x-cut), 0, z*half.z}
			clip_block(b, n, point)
			if rim > 0 {
				clip_block(b, Vec3{x, 1.41421356, z}, point+Vec3{0, half.y-rim, 0})
			}
		}
	}
	if rim > 0 {
		for sign in signs {
			clip_block(b, {sign, 1, 0}, b.center+Vec3{sign*half.x, half.y-rim, 0})
			clip_block(b, {0, 1, sign}, b.center+Vec3{0, half.y-rim, sign*half.z})
		}
	}
}

// Extrude a convex cross section along Z. A small set of plane cuts gives the
// faceted floor, sloping walls and roof real collision, without a triangle soup.
add_prism :: proc(g: ^World, points: []Vec2, near_z, far_z: f32, style: int) {
	assert(len(points) >= 3 && len(points) <= 12)
	lo, hi := points[0], points[0]
	for p in points {
		lo = {min(lo.x, p.x), min(lo.y, p.y)}
		hi = {max(hi.x, p.x), max(hi.y, p.y)}
	}
	center := Vec3{(lo.x+hi.x)*0.5, (lo.y+hi.y)*0.5, (near_z+far_z)*0.5}
	add_block(g, center, {hi.x-lo.x, hi.y-lo.y, abs(near_z-far_z)}, style)
	b := &g.blocks[len(g.blocks)-1]
	for a, i in points {
		edge := points[(i+1)%len(points)]-a
		n := Vec3{edge.y, -edge.x, 0}
		point := Vec3{a.x, a.y, center.z}
		if dot(n, center-point) > 0 { n = -n }
		clip_block(b, n, point)
	}
}

add_tunnel :: proc(g: ^World) {
	floor := [8]Vec2{{-3.2, 1}, {-2.7, 0.5}, {-2, 0.15}, {-1.2, 0}, {1.2, 0}, {2, 0.15}, {2.7, 0.5}, {3.2, 1}}
	for i in 0..<len(floor)-1 {
		a, b := floor[i]+Vec2{TUNNEL_X, 0}, floor[i+1]+Vec2{TUNNEL_X, 0}
		// The existing deck is the flat centre; avoid two coplanar floor surfaces.
		if a.y == 0 && b.y == 0 { continue }
		points := [4]Vec2{{a.x, -0.25}, {b.x, -0.25}, b, a}
		add_prism(g, points[:], TUNNEL_Z_NEAR, TUNNEL_Z_FAR, 4)
	}
	profile := TUNNEL_PROFILE
	for i in 0..<len(profile)-1 {
		a, b := profile[i]+Vec2{TUNNEL_X, 0}, profile[i+1]+Vec2{TUNNEL_X, 0}
		d := b-a
		n := Vec2{-d.y, d.x}/math.sqrt(d.x*d.x+d.y*d.y)*0.32
		points := [4]Vec2{a, b, b+n, a+n}
		add_prism(g, points[:], TUNNEL_Z_NEAR, TUNNEL_Z_FAR, 5)
	}
}

sweep_block :: proc(position, delta, extent: Vec3, b: ^Block, limit: f32) -> (fraction: f32, normal: Vec3, hit: bool) {
	// Sweeping the player box is a point sweep against expanded solid planes.
	enter, leave := f32(-1), limit
	nearest_distance := f32(-1e30)
	nearest_normal: Vec3
	for i in 0..<6+b.clip_count {
		plane := block_plane(b, i)
		n := plane.normal
		support := abs(n.x)*extent.x+abs(n.y)*extent.y+abs(n.z)*extent.z
		distance := dot(n, position)-plane.distance-support
		if distance > nearest_distance { nearest_distance, nearest_normal = distance, n }
		motion := dot(n, delta)
		if abs(motion) < 0.0000001 {
			// Tangential contact is not penetration. In particular, the side
			// face of the next coplanar floor tile must not become a wall when
			// roundoff leaves the feet a few micrometres above/below its top.
			if distance >= -CONTACT_MARGIN*0.1 { return limit, {}, false }
			continue
		}
		t := -distance/motion
		if motion < 0 {
			if t > enter { enter, normal = t, n }
		} else {
			leave = min(leave, t)
		}
		if enter > leave { return limit, {}, false }
	}
	if enter > limit || leave < 0 { return limit, {}, false }
	if enter < 0 {
		// A start inside a solid still blocks motion deeper into its nearest
		// face. Ignoring it beyond CONTACT_MARGIN let tiny slope drift turn a
		// downward blast into a fall through the entire ramp. Escape stays free.
		if dot(nearest_normal, delta) >= -0.0000001 { return limit, {}, false }
		return 0, nearest_normal, true
	}
	return max(0, enter), normal, true
}
