package game

// Parameterised pieces shared by the first real sector and the short combat
// fixture. Keep the central walking route and authored doorway approaches clear.
ram_combat_bay :: proc(w: ^World, s: Section_Recipe) {
	for z in ([3]f32{s.depth*0.5-3, 0, -s.depth*0.5+3}) { room_nav_world(w, s, s.origin+Vec3{0, 0, z}) }
	rows := 3 if s.depth > 45 else 2
	for row in 0..<rows {
		z := (f32(row)/f32(rows-1)-0.5)*s.depth*0.48
		sign := f32(1 if row%2 == 0 else -1)
		p := s.origin+Vec3{sign*s.width*0.29, 0.85, z}
		ram_block(w, p, {3.0, 1.7, 5.0}, 3, 0.55)
		// Sloped console, vents and an uneven overhead duct make useful cover
		// a recognisable machine rather than an isolated rectangular crate.
		points := [4]Vec2{{p.x-1.3, s.origin.y+1.68}, {p.x+1.3, s.origin.y+1.68}, {p.x+1.3, s.origin.y+2.50}, {p.x-1.3, s.origin.y+2.04}}
		add_prism(w, points[:], p.z+1.4, p.z-1.4, 6)
		for fin in 0..<6 {
			q := p+Vec3{-sign*1.51, -0.3+f32(fin)*0.18, 0}
			add_decor_beam(w, q-Vec3{0, 0, 1.7}, q+Vec3{0, 0, 1.7}, 0.035, 0.035, {144, 152, 139}, 0, 4)
		}
		arm := s.origin+Vec3{-sign*(s.width*0.5-1.1), s.height*0.48, z+1.7}
		ram_block(w, arm, {1.4, s.height*0.96, 2.2}, 3, 0.3)
		add_decor_beam(w, arm+Vec3{sign*0.73, -s.height*0.33, 0}, arm+Vec3{sign*0.73, s.height*0.36, 0}, 0.04, 0.04, DECOR_ORANGE, 3, 4)
	}
	// Angled corner infills break the box silhouette without closing the doors.
	for side in 0..<2 {
		sign := f32(side*2-1)
		p := s.origin+Vec3{sign*(s.width*0.5-1.0), s.height*0.5, -s.depth*0.5+1}
		ram_block(w, p, {2, s.height, 2}, 5, 0.65)
	}
}

ram_stair_hall :: proc(w: ^World, s: Section_Recipe) {
	c := s.origin
	// A broad climb leaves room to strafe. A low side route remains available
	// for cover, and stepping stones let the player cut the turn with a jump.
	profile := [4]Vec2{{c.z+4, c.y-0.1}, {c.z-9, c.y-0.1}, {c.z-9, c.y+3.6}, {c.z+4, c.y+0.05}}
	add_prism(w, profile[:], c.x+3, c.x-3, 3)
	b := &w.blocks[len(w.blocks)-1]
	b.center.x, b.center.z = b.center.z, b.center.x
	b.size.x, b.size.z = b.size.z, b.size.x
	for &plane in b.clips[:b.clip_count] { plane.normal.x, plane.normal.z = plane.normal.z, plane.normal.x }
	add_block(w, c+Vec3{0, 1.3, -13}, {12, 4.6, 8}, 3)
	ram_block(w, c+Vec3{-6.5, 0.6, -1}, {3.8, 1.2, 4}, 6, 0.4)
	ram_block(w, c+Vec3{-6.5, 1.2, -5}, {3.8, 2.4, 4}, 6, 0.4)
	for side in 0..<2 {
		sign := f32(side*2-1)
		add_decor_beam(w, c+Vec3{sign*3.0, 0.1, 4}, c+Vec3{sign*3.0, 3.68, -9}, 0.04, 0.04, DECOR_MINT, 3, 4)
		add_decor_beam(w, c+Vec3{sign*5.8, 3.67, -9}, c+Vec3{sign*5.8, 3.67, -17}, 0.05, 0.05, DECOR_MINT, 3, 4)
	}
}
