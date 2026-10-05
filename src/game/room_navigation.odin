package game

ROOM_NAV_CAPACITY :: 16
Room_Navigation :: struct {
	points: [ROOM_NAV_CAPACITY]Vec3, // Feet at the authored floor or landing.
	links: [Enemy_Kind][ROOM_NAV_CAPACITY]u16,
	count: int,
}

room_nav :: proc(w: ^World, s: Section_Recipe, local: Vec3) {
	room_nav_world(w, s, ram_local(s, local))
}

room_nav_world :: proc(w: ^World, s: Section_Recipe, point: Vec3) {
	n := &w.room_navigation[room_index(&w.sector, s.id)]
	for p in n.points[:n.count] { if length(p-point) < 0.1 { return } }
	assert(n.count < len(n.points), "Room navigation capacity exceeded")
	n.points[n.count] = point
	n.count += 1
}

// Bake short visibility graphs only where an authored/selected form needs one.
// Clearance is baked per hull: growing a miniboss must not close a crab's
// corridor, nor may a large actor borrow a route only its offspring can fit.
// No raylib, navmesh library, or per-tick allocation is involved.
build_room_navigation :: proc(w: ^World) {
	for &n in w.room_navigation[:w.sector.count] {
		n.links = {}
		for kind in Enemy_Kind {
			extent := enemy_extent(kind)
			offset := Vec3{0, extent.y+0.04 if enemy_grounded_kind(kind) else 2, 0}
			for a in 0..<n.count {
				for b in a+1..<n.count {
					fraction, _ := world_sweep(w, n.points[a]+offset, n.points[b]-n.points[a], extent)
					if fraction < 0.999 { continue }
					links := &n.links[kind]
					links[a] |= u16(1)<<u32(b)
					links[b] |= u16(1)<<u32(a)
				}
			}
		}
	}
}

enemy_room_goal :: proc(w: ^World, room: int, start, target: Vec3, kind: Enemy_Kind) -> (Vec3, bool) {
	extent := enemy_extent(kind)
	destination := target
	if enemy_grounded_kind(kind) {
		from := target+Vec3{0, extent.y+1, 0}
		drop := world_ray(w, from, {0, -1, 0}, extent.y+8)
		if drop < extent.y+8 { destination.y = from.y-drop+extent.y+0.04 }
	}
	fraction, _ := world_sweep(w, start+Vec3{0, 0.025, 0}, destination-start, extent)
	if fraction > 0.999 { return destination, true }
	n := &w.room_navigation[room]
	if n.count == 0 { return destination, true } // Simple cover uses local steering.
	offset := Vec3{0, extent.y+0.04 if enemy_grounded_kind(kind) else 2, 0}
	links := &n.links[kind]
	distance: [ROOM_NAV_CAPACITY]f32
	first: [ROOM_NAV_CAPACITY]int
	visited, finishes: u16
	best, result := f32(1e20), -1
	for i in 0..<n.count {
		p := n.points[i]+offset
		clear, _ := world_sweep(w, start+Vec3{0, 0.025, 0}, p-start, extent)
		distance[i], first[i] = length(p-start) if clear > 0.999 else f32(1e20), i
		clear, _ = world_sweep(w, p, destination-p, extent)
		if clear > 0.999 { finishes |= u16(1)<<u32(i) }
	}
	for _ in 0..<n.count {
		nearest, score := -1, f32(1e20)
		for i in 0..<n.count {
			if visited & (u16(1)<<u32(i)) == 0 && distance[i] < score { nearest, score = i, distance[i] }
		}
		if nearest < 0 || score >= best { break }
		visited |= u16(1)<<u32(nearest)
		if finishes & (u16(1)<<u32(nearest)) != 0 {
			cost := score+length(destination-(n.points[nearest]+offset))
			if cost < best { best, result = cost, first[nearest] }
		}
		for i in 0..<n.count {
			if links[nearest] & (u16(1)<<u32(i)) == 0 { continue }
			cost := score+length(n.points[nearest]-n.points[i])
			if cost < distance[i] { distance[i], first[i] = cost, first[nearest] }
		}
	}
	if result >= 0 { return n.points[result]+offset, true }
	return start, false
}
