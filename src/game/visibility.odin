package game

// Conservative AABB/frustum test shared by perspective and orthographic passes.
bounds_visible :: proc(bounds: Bounds, clip: #row_major matrix[4, 4]f32) -> bool {
	center, extent := (bounds.lo+bounds.hi)*0.5, (bounds.hi-bounds.lo)*0.5
	for axis in 0..<3 {
		for side in 0..<2 {
			sign := f32(side*2-1)
			n := Vec3{clip[3, 0]+sign*clip[axis, 0], clip[3, 1]+sign*clip[axis, 1], clip[3, 2]+sign*clip[axis, 2]}
			d := clip[3, 3]+sign*clip[axis, 3]
			if dot(n, center)+d+dot(Vec3{abs(n.x), abs(n.y), abs(n.z)}, extent) < -0.001 { return false }
		}
	}
	return true
}
