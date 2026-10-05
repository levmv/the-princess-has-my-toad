package game

// Variant selection is independent of decoration and encounter RNG. Explicit
// choices survive rebuilding, which also lets a save restore its chosen forms.
resolve_room_variants :: proc(r: ^Sector_Recipe, seed: u32) {
	for &s in r.sections[:r.count] {
		if s.variant != .Auto { continue }
		choice := content_seed(seed, u32(s.id), 0xC04A3921)
		// Xorshift alone is linear: choosing its lowest bit would flip every
		// room together when the seed changes. Mix before selecting a form.
		choice = (choice ~ (choice>>16))*0x85EBCA6B
		choice = (choice ~ (choice>>13))*0xC2B2AE35
		choice ~= choice>>16
		s.variant = .Weave if choice%2 == 0 else .Split
	}
}

ram_local_block :: proc(w: ^World, s: Section_Recipe, position, size: Vec3, style: int, bevel: f32 = 0.35) {
	shape := size
	if s.width > s.depth { shape.x, shape.z = shape.z, shape.x }
	ram_block(w, ram_local(s, position), shape, style, bevel)
}

ram_local_beam :: proc(w: ^World, s: Section_Recipe, a, b: Vec3, radius: f32, color: [3]u8, material: f32 = 0) {
	add_decor_beam(w, ram_local(s, a), ram_local(s, b), radius, radius, color, material, 6)
}

ram_local_prism :: proc(w: ^World, s: Section_Recipe, points: []Vec2, near_z, far_z: f32, style: int) {
	local_points: [12]Vec2
	for p, i in points { local_points[i] = p+Vec2{s.origin.x, s.origin.y} }
	add_prism(w, local_points[:len(points)], s.origin.z+near_z, s.origin.z+far_z, style)
	if s.width > s.depth {
		b := &w.blocks[len(w.blocks)-1]
		// Rotate around the room, including the translated plane equations.
		center := b.center-s.origin
		b.center = s.origin+Vec3{-center.z, center.y, center.x}
		b.size.x, b.size.z = b.size.z, b.size.x
		for &p in b.clips[:b.clip_count] {
			distance := p.distance-dot(p.normal, s.origin)
			p.normal = {-p.normal.z, p.normal.y, p.normal.x}
			p.distance = distance+dot(p.normal, s.origin)
		}
	}
}

// Crosswise racks force three changes of firing lane. The other form has a
// central spine with two flanking lanes and a cross passage in its middle.
ram_memory_gallery :: proc(w: ^World, s: Section_Recipe) {
	half, span := s.width*0.5, s.depth
	if s.variant == .Weave {
		for i in 0..<3 {
			sign := f32(1 if i%2 == 0 else -1)
			z := f32(1-i)*span*0.29
			p := Vec3{sign*(half*0.5-0.3), s.height*0.38, z}
			ram_local_block(w, s, p, {half-0.6, s.height*0.76, 8}, 6, 0.7)
			for pin in 0..<8 {
				pz := z-3+f32(pin)*0.85
				ram_local_beam(w, s, {sign*0.05, 0.3, pz}, {-sign*0.65, 0.9, pz}, 0.12, {190, 144, 63})
			}
			ram_local_beam(w, s, {sign*0.05, 2.1, z-3}, {sign*0.05, s.height*0.70, z-3}, 0.065, DECOR_MINT, 3)
			for offset in ([2]f32{6, -6}) { room_nav(w, s, {-sign*half*0.52, 0, z+offset}) }
		}
	} else {
		for side in ([2]f32{-1, 1}) {
			ram_local_block(w, s, {0, s.height*0.38, side*span*0.19}, {8, s.height*0.76, span*0.25}, 6, 0.65)
			for lane in ([2]f32{-1, 1}) {
				for z in ([3]f32{-span*0.36, 0, span*0.36}) { room_nav(w, s, {lane*(half+4)*0.5, 0, z}) }
				ram_local_beam(w, s, {lane*4.06, 1.1, side*span*0.19-6}, {lane*4.06, s.height*0.7, side*span*0.19-6}, 0.08, DECOR_MINT, 3)
			}
		}
	}
	// The ceiling is a visible memory socket, with gold contacts above the
// fighting lanes. These thin parts do not pretend to be collision cover.
	for side in ([2]f32{-1, 1}) {
		for i in 0..<8 {
			z := (f32(i)-3.5)*span/9
			ram_local_beam(w, s, {side*(half-0.7), s.height-0.1, z}, {side*(half-2.8), s.height-1.1, z}, 0.23, {196, 146, 62})
		}
	}
	room_nav(w, s, {0, 0, span*0.5-3})
	room_nav(w, s, {0, 0, -span*0.5+3})
}

// Real baffles hide what is beyond the next bend. Split ducts offer a loop
// around a central exchanger instead. Both reserve generous door approaches.
ram_service_variant :: proc(w: ^World, s: Section_Recipe) {
	span, half := max(s.width, s.depth), min(s.width, s.depth)*0.5
	wall_style, _ := ram_theme_styles(s)
	if s.variant == .Weave {
		for i in 0..<3 {
			sign := f32(1 if i%2 == 0 else -1)
			z := f32(1-i)*span*0.24
			gap := min(4.4, half)
			ram_local_block(w, s, {sign*gap*0.5, s.height*0.5, z}, {half*2-gap-0.5, s.height+0.4, 2.8}, wall_style, 0.32)
			// Centre the lane between the baffle and the raised wall gutter.
			// A broad actor at the old point clipped the gutter with its feet.
			lane := -sign*(half-gap*0.5-0.575)
			for offset in ([2]f32{4.6, -4.6}) { room_nav(w, s, {lane, 0, z+offset}) }
			ram_local_beam(w, s, {lane, 0.07, z+1.9}, {lane, 0.07, z-1.9}, 0.045, DECOR_ORANGE, 3)
		}
	} else {
		width := max(1.0, half*2-8)
		z_end := span*0.28
		ram_local_block(w, s, {0, s.height*0.5, 0}, {width, s.height+0.4, z_end*2}, wall_style, 0.45)
		for side in ([2]f32{-1, 1}) {
			lane := side*(half-0.9+width*0.5)*0.5
			for z in ([3]f32{z_end+3, 0, -z_end-3}) { room_nav(w, s, {lane, 0, z}) }
			for i in 0..<int(span/6) {
				z := (f32(i)+0.5)*span/f32(int(span/6))-span*0.5
				ram_local_beam(w, s, {side*(width*0.5+0.06), 0.7, z*0.5}, {side*(width*0.5+0.06), s.height-0.5, z*0.5}, 0.09, {134, 143, 139})
			}
		}
	}
	room_nav(w, s, {0, 0, span*0.5-3})
	room_nav(w, s, {0, 0, -span*0.5+3})
	// Shallow faceted gutters and angled shoulders change the cross-section,
	// while leaving the full walking width clear above knee height.
	for side in ([2]f32{-1, 1}) {
		floor := [3]Vec2{{side*(half-0.6), 0}, {side*(half-0.6), 0.22}, {side*(half-0.9), 0}}
		ram_local_prism(w, s, floor[:], span*0.5-1, -span*0.5+1, 4)
	}
	ram_passage(w, s)
}
