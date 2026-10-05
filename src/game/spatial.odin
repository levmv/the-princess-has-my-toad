package game

Bounds :: struct { lo, hi: Vec3 }
BVH_Node :: struct {
	bounds: Bounds,
	first, count, escape: int,
}

block_bounds :: proc(b: Block) -> Bounds { return {b.center-b.size*0.5, b.center+b.size*0.5} }

bounds_union :: proc(a, b: Bounds) -> Bounds {
	return {{min(a.lo.x, b.lo.x), min(a.lo.y, b.lo.y), min(a.lo.z, b.lo.z)},
		{max(a.hi.x, b.hi.x), max(a.hi.y, b.hi.y), max(a.hi.z, b.hi.z)}}
}

ray_bounds :: proc(bounds: Bounds, origin, direction, padding: Vec3, limit: f32, epsilon: f32 = 0.000001) -> bool {
	near, far := f32(0), limit
	for axis in 0..<3 {
		lo, hi := bounds.lo[axis]-padding[axis], bounds.hi[axis]+padding[axis]
		if abs(direction[axis]) < epsilon {
			if origin[axis] < lo || origin[axis] > hi { return false }
		} else {
			a, b := (lo-origin[axis])/direction[axis], (hi-origin[axis])/direction[axis]
			near, far = max(near, min(a, b)), min(far, max(a, b))
			if near > far { return false }
		}
	}
	return true
}

// Median partition keeps traversal depth bounded even for irregular generated maps.
partition_blocks :: proc(w: ^World, first, count, axis: int) {
	left, right, middle := first, first+count-1, first+count/2
	for left < right {
		pivot := w.blocks[w.block_order[(left+right)/2]].center[axis]
		i, j := left, right
		for i <= j {
			for w.blocks[w.block_order[i]].center[axis] < pivot { i += 1 }
			for w.blocks[w.block_order[j]].center[axis] > pivot { j -= 1 }
			if i <= j { w.block_order[i], w.block_order[j] = w.block_order[j], w.block_order[i]; i += 1; j -= 1 }
		}
		if middle <= j { right = j } else if middle >= i { left = i } else { break }
	}
}

build_bvh_node :: proc(w: ^World, first, count: int) {
	index := len(w.nodes)
	bounds := block_bounds(w.blocks[w.block_order[first]])
	for id in w.block_order[first+1:first+count] { bounds = bounds_union(bounds, block_bounds(w.blocks[id])) }
	append(&w.nodes, BVH_Node{bounds = bounds, first = first, count = count})
	if count > 4 {
		extent := bounds.hi-bounds.lo
		axis := 0
		if extent.y > extent.x { axis = 1 }
		if extent.z > extent[axis] { axis = 2 }
		partition_blocks(w, first, count, axis)
		build_bvh_node(w, first, count/2)
		build_bvh_node(w, first+count/2, count-count/2)
		w.nodes[index].count = 0
	}
	w.nodes[index].escape = len(w.nodes)
}

// Commit after level edits. Queries remain correct (linear) until committed.
// The renderer observes revision and rebuilds its static chunks at a frame boundary.
world_commit :: proc(w: ^World) {
	w.revision += 1
	clear(&w.nodes)
	clear(&w.block_order)
	for _, i in w.blocks { append(&w.block_order, i) }
	if len(w.blocks) > 0 { build_bvh_node(w, 0, len(w.blocks)) }
	w.index_revision = w.revision
}

world_ray_linear :: proc(w: ^World, origin, direction: Vec3, limit: f32, padding: f32 = 0) -> f32 {
	distance := limit
	for block in w.blocks {
		t, hit := ray_box(origin, direction, block, distance, padding)
		if hit { distance = t }
	}
	return moving_solids_ray(w, origin, direction, distance, padding)
}

moving_solids_ray :: proc(w: ^World, origin, direction: Vec3, limit: f32, padding: f32) -> f32 {
	distance := limit
	for gate in w.gates[:w.gate_count] {
		t, hit := ray_box(origin, direction, gate_shape(gate), distance, padding)
		if hit { distance = t }
	}
	if boss_exit_present(w) {
		t, hit := ray_box(origin, direction, boss_exit_shape(w), distance, padding)
		if hit { distance = t }
	}
	return distance
}

world_ray_indexed :: proc(w: ^World, origin, direction: Vec3, limit: f32, padding: f32 = 0) -> f32 {
	if w.index_revision != w.revision { return world_ray_linear(w, origin, direction, limit, padding) }
	distance := limit
	index := 0
	for index < len(w.nodes) {
		node := &w.nodes[index]
		if !ray_bounds(node.bounds, origin, direction, {padding, padding, padding}, distance) { index = node.escape; continue }
		for id in w.block_order[node.first:node.first+node.count] {
			t, hit := ray_box(origin, direction, w.blocks[id], distance, padding)
			if hit { distance = t }
		}
		index += 1
	}
	return moving_solids_ray(w, origin, direction, distance, padding)
}

world_ray :: proc{world_ray_state, world_ray_indexed}
world_ray_state :: proc(g: ^State, origin, direction: Vec3, limit: f32, padding: f32 = 0) -> f32 {
	return world_ray_indexed(g.world, origin, direction, limit, padding)
}

world_sweep :: proc(w: ^World, center, delta, extent: Vec3) -> (fraction: f32, normal: Vec3) {
	fraction = 1
	last := -1
	indexed := w.index_revision == w.revision
	index, end := 0, len(w.nodes) if indexed else len(w.blocks)
	for index < end {
		first, count := index, 1
		if indexed {
			node := &w.nodes[index]
			if !ray_bounds(node.bounds, center, delta, extent+Vec3{0.00001, 0.00001, 0.00001}, fraction, 0.0000001) { index = node.escape; continue }
			first, count = node.first, node.count
		}
		for order in first..<first+count {
			id := w.block_order[order] if indexed else order
			block := &w.blocks[id]
			if !ray_bounds(block_bounds(block^), center, delta, extent+Vec3{0.00001, 0.00001, 0.00001}, fraction, 0.0000001) { continue }
			t, n, hit := sweep_block(center, delta, extent, block, fraction)
			// Preserve authoring-order tie breaks independently of BVH ordering.
			if hit && (t < fraction || (t == fraction && id > last)) { fraction, normal, last = t, n, id }
		}
		index += 1
	}
	for gate in w.gates[:w.gate_count] {
		shape := gate_shape(gate)
		t, n, hit := sweep_block(center, delta, extent, &shape, fraction)
		if hit { fraction, normal = t, n }
	}
	if boss_exit_present(w) {
		shape := boss_exit_shape(w)
		t, n, hit := sweep_block(center, delta, extent, &shape, fraction)
		if hit { fraction, normal = t, n }
	}
	return
}
