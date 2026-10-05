package game

import "core:math"

ram_column :: proc(w: ^World, position: Vec3, radius, height: f32, style: int = 7) {
	outer := radius/math.cos(f32(math.PI/8))
	add_block(w, position+Vec3{0, height*0.5, 0}, {outer*2, height, outer*2}, style)
	b := &w.blocks[len(w.blocks)-1]
	for face in 0..<8 {
		a := f32(face)*2*math.PI/8
		n := Vec3{math.cos(a), 0, math.sin(a)}
		clip_block(b, n, position+n*radius)
	}
	for y in ([2]f32{0.4, height-0.4}) {
		for edge in 0..<8 {
			a, z := (f32(edge)*2+1)*math.PI/8, (f32(edge+1)*2+1)*math.PI/8
			add_decor_beam(w, position+Vec3{math.cos(a)*(outer+0.06), y, math.sin(a)*(outer+0.06)}, position+Vec3{math.cos(z)*(outer+0.06), y, math.sin(z)*(outer+0.06)}, 0.08, 0.08, DECOR_MINT, 3, 4)
		}
	}
}

ram_ramp :: proc(w: ^World, from, to: Vec3, width: f32, style: int = 3) {
	assert(from.y < to.y && (from.x == to.x || from.z == to.z))
	x_axis := from.z == to.z
	base := from.y-0.3
	size := Vec3{width, to.y-base, abs(to.z-from.z)}
	if x_axis { size.x, size.z = abs(to.x-from.x), width }
	p := (from+to)*0.5
	p.y = (base+to.y)*0.5
	add_block(w, p, size, style)
	direction := normalized(Vec3{to.x-from.x, 0, to.z-from.z})
	grade := (to.y-from.y)/length(Vec3{to.x-from.x, 0, to.z-from.z})
	clip_block(&w.blocks[len(w.blocks)-1], {-direction.x*grade, 1, -direction.z*grade}, to)
	for side in ([2]f32{-1, 1}) {
		offset := Vec3{side*width*0.46, 0.06, 0} if !x_axis else Vec3{0, 0.06, side*width*0.46}
		add_decor_beam(w, from+offset, to+offset, 0.045, 0.045, DECOR_MINT, 3, 4)
	}
}

ram_capacitor_garden :: proc(w: ^World, s: Section_Recipe) {
	ram_column(w, s.origin, 6.5, 12.5)
	ram_column(w, s.origin+Vec3{-18, 0, -18}, 2.5, 8)
	ram_column(w, s.origin+Vec3{18, 0, 20}, 2.5, 11)
	// Broad ground lanes flank the capacitor. Three low housings can instead
	// be climbed to reach a firing perch and a descending aerial route.
	for p in ([3]Vec3{{-18, 1.3, 8}, {-14, 2.8, 11}, {-10, 4.3, 14}}) {
		ram_block(w, s.origin+Vec3{p.x, p.y*0.5, p.z}, {4, p.y, 5}, 13, 0.45)
	}
	ram_block(w, s.origin+Vec3{-4, 5, 18}, {16, 1, 8}, 13, 0.6)
	ram_block(w, s.origin+Vec3{18, 3.35, 1}, {8, 0.9, 24}, 13, 0.6)
	ram_block(w, s.origin+Vec3{10, 1.55, -19}, {10, 0.9, 10}, 13, 0.6)
	for p in ([4]Vec3{{-10, 4.5, 20}, {2, 4.5, 20}, {18, 2.9, 9}, {18, 2.9, -7}}) {
		ram_column(w, s.origin+Vec3{p.x, 0, p.z}, 0.7, p.y, 3)
	}
	for p in ([3]Vec3{{-10, 5.5, 21}, {21, 3.8, -7}, {13, 2, -22}}) {
		ram_deck_light(w, s.origin+p, {118, 177, 255})
	}
	ram_deck_light(w, s.origin+Vec3{2.5, 5.5, 20}, DECOR_ORANGE)
	for p in ([3]Vec3{{-22, 0, -5}, {6, 0, 12}, {0, 0, -22}}) { ram_deck_light(w, s.origin+p, DECOR_ORANGE) }
	for p in ([9]Vec3{{-22, 0, 0}, {-11, 0, 0}, {-11, 0, -10}, {0, 0, -19}, {6, 0, -12}, {11, 0, 0}, {9, 0, 11}, {-5, 0, 9}, {-20, 0, -9}}) { room_nav(w, s, p) }
	// A tilted cable gantry and the enormous split cap make a landmark visible
	// above nearby cover; the next room remains behind the enclosure's wall.
	for x in ([2]f32{-1, 1}) {
		add_decor_beam(w, s.origin+Vec3{x*5, 12.6, -1.6}, s.origin+Vec3{x*5, 12.6, 1.6}, 0.16, 0.16, {188, 200, 195}, 2, 4)
		add_decor_beam(w, s.origin+Vec3{x*5, 12, 0}, s.origin+Vec3{x*24, 7, -8}, 0.24, 0.24, {41, 53, 69}, 0, 8)
	}
}

ram_branch_landing :: proc(w: ^World, s: Section_Recipe) {
	ram_ramp(w, s.origin+Vec3{12, 0, 19}, s.origin+Vec3{12, 6, -3}, 5)
	add_block(w, s.origin+Vec3{12, 2.9, -6}, {5, 6.2, 6}, 3)
	add_block(w, s.origin+Vec3{16.25, 2.9, -2}, {3.5, 6.2, 14}, 3)
	// A quiet supply recess behind the stair base, reached around its west side.
	ram_deck_light(w, s.origin+Vec3{15.5, 0, -17.5}, DECOR_MINT)
	// The rising ramp is now the only continuation. Local combat and flying
	// routes provide the alternatives instead of another long loop of rooms.
	room_nav(w, s, {0, 0, 17})
	room_nav(w, s, {0, 0, 0})
	room_nav(w, s, {-13, 0, 0})
}

// The high route consists of staggered decks over a recoverable lower trough.
// Falls cost position, not a life. A ramp always leads back onto the last deck.
ram_address_bridge :: proc(w: ^World, s: Section_Recipe) {
	span, half := max(s.width, s.depth), min(s.width, s.depth)*0.5
	if half >= 15 {
		for side in ([2]f32{-1, 1}) { ram_column(w, ram_local(s, {side*12, 0, 0}), 3.2, 14, 6) }
	}
	gap := f32(6)
	length := (span-gap*3)/4
	for i in 0..<4 {
		z := span*0.5-length*0.5-f32(i)*(length+gap)
		x := f32(1 if i == 1 else -1)*1.5 if i == 1 || i == 2 else 0
		width := half*2 if i == 0 || i == 3 else min(half*2-3, 10)
		ram_local_block(w, s, {x, 5.55, z}, {width, 0.9, length}, 3, 0.45)
		for side in ([2]f32{-1, 1}) {
			ram_local_beam(w, s, {x+side*(width*0.5-0.2), 6.04, z+length*0.5-0.3}, {x+side*(width*0.5-0.2), 6.04, z-length*0.5+0.3}, 0.055, DECOR_MINT, 3)
			// Hanging braces have collision; narrow suspended beams remain trim.
			ram_local_block(w, s, {side*(half-0.85), 3, z}, {0.5, 6, 0.65}, 3, 0.1)
		}
		room_nav(w, s, {x, 6, z})
	}
	end := -span*0.5+length
	ram_ramp(w, ram_local(s, {half-2, 0, end+22}), ram_local(s, {half-2, 6, end}), 3.2)
	for z in ([2]f32{-span*0.13, span*0.13}) {
		// Lower machinery keeps the fallback passage spatially distinct from
		// the fast high route; its small central gap is still walkable.
		for side in ([2]f32{-1, 1}) {
			if side > 0 && z < 0 { continue } // Keep the recovery ramp clear.
			ram_local_block(w, s, {side*(half-2), 1, z}, {2.4, 2, 6}, 6, 0.4)
		}
	}
}

ram_switching_hall :: proc(w: ^World, s: Section_Recipe) {
	if w.sector.key == .RAM_Bank_01 { ram_pony_monument(w, s)
	} else { ram_column(w, s.origin+Vec3{4, 0, -3}, 6.5, 11, 3) }
	for i in 0..<5 {
		z := -11+f32(i)*5.5
		ram_block(w, s.origin+Vec3{24, 3.5, z}, {5, 7, 2.5}, 6, 0.6)
		add_decor_beam(w, s.origin+Vec3{23.5, 7.1, z}, s.origin+Vec3{8, 12, -3}, 0.16, 0.16, DECOR_ORANGE, 0, 8)
	}
	// An optional overlook overlooks the battle, then drops next to the west
	// exit. It offers a real choice without blocking ground-level progress.
	ram_ramp(w, s.origin+Vec3{-18, 0, 20}, s.origin+Vec3{-18, 4, 4}, 5)
	ram_block(w, s.origin+Vec3{-21, 3.55, -2}, {11, 0.9, 12}, 3, 0.3)
	for p in ([6]Vec3{{-9, 0, 15}, {15, 0, 15}, {15, 0, -15}, {-9, 0, -15}, {-10, 0, 0}, {-28, 0, 0}}) { room_nav_world(w, s, s.origin+p) }
}

ram_secret_scene :: proc(w: ^World, s: Section_Recipe) {
	if s.id == 1021 {
		// An inexplicably monumental frog, hidden in a maintenance cupboard.
		p := s.origin+Vec3{3, 0, -2}
		ram_column(w, p, 2.5, 0.8, 3)
		ram_block(w, p+Vec3{0, 1.45, 0}, {2.2, 1.35, 2.8}, 6, 0.6)
		for side in ([2]f32{-1, 1}) {
			ram_block(w, p+Vec3{0.8, 2.22, side*0.8}, {0.72, 0.8, 0.72}, 6, 0.2)
			add_decor_beam(w, p+Vec3{1.2, 2.25, side*0.8}, p+Vec3{1.25, 2.25, side*0.8}, 0.18, 0.18, {230, 203, 109}, 3, 8)
			add_decor_beam(w, p+Vec3{-0.5, 1.2, side}, p+Vec3{-1.9, 0.9, side*1.6}, 0.34, 0.24, {39, 110, 70}, 0, 6)
			add_decor_beam(w, p+Vec3{-1.9, 0.9, side*1.6}, p+Vec3{0.6, 0.9, side*2}, 0.24, 0.18, {39, 110, 70}, 0, 6)
		}
	} else {
		// An oversized empty cradle: a quiet oddity before the final rooms.
		p := s.origin+Vec3{0, 0, 2}
		ram_block(w, p+Vec3{0, 0.6, 0}, {5, 1.2, 3}, 8, 0.6)
		for side in ([2]f32{-1, 1}) {
			ram_block(w, p+Vec3{side*2.2, 1.9, 0}, {0.5, 2.6, 3}, 7, 0.1)
			for i in 0..<7 {
				x := -2+f32(i)*0.67
				add_decor_beam(w, p+Vec3{x, 1.15, side*1.4}, p+Vec3{x, 2.4, side*1.4}, 0.075, 0.075, {170, 190, 186}, 2, 6)
			}
			add_decor_beam(w, p+Vec3{-2, 2.45, side*1.4}, p+Vec3{2, 2.45, side*1.4}, 0.1, 0.1, DECOR_MINT, 3, 6)
		}
	}
}
