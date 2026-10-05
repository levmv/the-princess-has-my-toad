package game

// Authored landmarks share the level's clipped solids. Their silhouettes,
// cover and camera collision cannot diverge from the rendered architecture.
STYLE_ROSE_STONE :: 16
STYLE_DARK_ROSE :: 17
STYLE_OLD_GOLD :: 18
STYLE_ROYAL_CANVAS :: 19

Royal_Banner :: struct { base, right: Vec3, width, height: f32 }

ram_royal_banner :: proc(s: Section_Recipe) -> (Royal_Banner, bool) {
	switch s.id {
	case 1005: return {s.origin+Vec3{14, 3.2, -24.65}, {1, 0, 0}, 8.2, 12.6}, true
	case 1015: return {s.origin+Vec3{32.65, 3, 8}, {0, 0, 1}, 7, 10.5}, true
	}
	return {}, false
}

ram_banner_mount :: proc(w: ^World, s: Section_Recipe) {
	b, ok := ram_royal_banner(s)
	if !ok { return }
	up := Vec3{0, 1, 0}
	normal := cross(b.right, up)
	// A shallow backing plate, rods, suspension brackets and two uplights.
	size := Vec3{abs(b.right.x)*b.width+abs(normal.x)*0.16, b.height, abs(b.right.z)*b.width+abs(normal.z)*0.16}
	add_block(w, b.base+up*(b.height*0.5)-normal*0.12, size, STYLE_ROYAL_CANVAS)
	for y in ([2]f32{0, b.height}) {
		add_decor_beam(w, b.base-b.right*(b.width*0.55)+up*y, b.base+b.right*(b.width*0.55)+up*y, 0.14, 0.14, {138, 112, 63}, 2, 8)
	}
	for side in ([2]f32{-1, 1}) {
		p := b.base+b.right*(side*b.width*0.42)
		add_decor_beam(w, p+up*(b.height+0.1), p+up*(b.height+0.55)-normal*0.7, 0.09, 0.09, {74, 71, 62}, 2, 6)
		lamp := p+normal*1.2-up*0.5
		add_decor_beam(w, lamp-up*0.25, lamp, 0.23, 0.16, {67, 63, 59}, 2, 8)
		add_decor_beam(w, lamp, lamp+up*0.035, 0.15, 0.15, {248, 211, 143}, 3, 8)
		append(&w.lamps, lamp+up*0.25)
	}
}

ram_statue_piece :: proc(w: ^World, base: Vec3, profile: []Vec2, front, back: f32, style: int = STYLE_ROSE_STONE) {
	points: [12]Vec2
	assert(len(profile) >= 3 && len(profile) <= len(points))
	winding := f32(0)
	for a, i in profile {
		b, c := profile[(i+1)%len(profile)], profile[(i+2)%len(profile)]
		turn := (b.x-a.x)*(c.y-b.y)-(b.y-a.y)*(c.x-b.x)
		assert(turn*winding >= -0.00001, "Sculpture profiles must be convex, like their collision volumes")
		if abs(turn) > 0.00001 { winding = turn }
	}
	for p, i in profile { points[i] = p+Vec2{base.x, base.y} }
	add_prism(w, points[:len(profile)], base.z+front, base.z+back, style)
	if len(profile) <= 8 {
		b := &w.blocks[len(w.blocks)-1]
		for x in ([2]f32{-1, 1}) {
			for z in ([2]f32{-1, 1}) {
				clip_block(b, {x, 0, z}, b.center+Vec3{x*(b.size.x*0.5-min(0.24, b.size.x*0.15)), 0, z*b.size.z*0.5})
			}
		}
		if b.clip_count+2 <= len(b.clips) {
			for z in ([2]f32{-1, 1}) {
				clip_block(b, {0, 1, z}, b.center+Vec3{0, b.size.y*0.5-min(0.35, b.size.y*0.15), z*b.size.z*0.5})
			}
		}
	}
}

ram_pony_monument :: proc(w: ^World, s: Section_Recipe) {
	p := s.origin+Vec3{4, 0, -3}
	// A deliberately over-important monument to an entirely ordinary pony.
	// Broad plinth lanes still connect the entry, the overlook and the west exit.
	ram_block(w, p+Vec3{0, 0.35, 0}, {13, 0.7, 8}, 14, 0.7)
	ram_block(w, p+Vec3{0, 1.3, 0}, {11.8, 1.2, 6.8}, 12, 0.6)
	ram_block(w, p+Vec3{0, 1.98, 0}, {12.2, 0.25, 7.2}, STYLE_OLD_GOLD, 0.4)
	// Barrel, rising neck, cheek and blunt muzzle: substantial, planar stone.
	ram_statue_piece(w, p, []Vec2{{-3.1, 4.1}, {-3.7, 5.3}, {-2.4, 6.4}, {1.8, 6.5}, {3.1, 5.6}, {2.7, 4.1}}, 1.45, -1.45)
	ram_statue_piece(w, p, []Vec2{{-3.4, 4.7}, {-4.25, 7.4}, {-3.7, 8.4}, {-2.5, 7.9}, {-1.5, 5.3}}, 1.05, -1.05)
	ram_statue_piece(w, p, []Vec2{{-4.25, 6.9}, {-5.15, 7.3}, {-5.35, 8.15}, {-4.15, 8.95}, {-3.0, 8.65}, {-2.95, 7.7}}, 1.12, -1.12)
	ram_statue_piece(w, p, []Vec2{{-5.8, 6.9}, {-5.95, 7.5}, {-5.1, 8.0}, {-4.5, 7.2}}, 0.92, -0.92)
	// Four offset legs and broad dark hooves keep the silhouette legible.
	for side in ([2]f32{-1, 1}) {
		z := side*1.03
		stagger := side*0.28
		for x in ([2]f32{-2.4, 1.8}) {
			b := p+Vec3{x+stagger, 0, z}
			ram_statue_piece(w, b, []Vec2{{-0.46, 2.1}, {-0.59, 3.1}, {-0.75, 4.8}, {0.5, 5.0}, {0.42, 3.1}, {0.26, 2.1}}, 0.43, -0.43)
			ram_block(w, b+Vec3{-0.16, 2.26, 0}, {1.18, 0.34, 1.05}, STYLE_DARK_ROSE, 0.16)
		}
		ram_statue_piece(w, p+Vec3{0, 0, side*0.67}, []Vec2{{-4.3, 8.5}, {-4.05, 10.0}, {-3.35, 8.6}}, 0.28, -0.28)
		// Inset eyes, nostrils and a chisel-cut mouth, on both broad faces.
		for detail in ([3][4]f32{{-4.52, 8.08, 0.20, 1.13}, {-5.62, 7.45, 0.12, 0.93}, {-5.55, 7.10, 0.09, 0.93}}) {
			q := p+Vec3{detail[0], detail[1], side*detail[3]}
			add_decor_beam(w, q-Vec3{detail[2], 0, 0}, q+Vec3{detail[2], 0.035, 0}, detail[2]*0.35, detail[2]*0.25, {60, 34, 48}, 1, 5)
		}
		for crack in ([3][2]Vec2{{{0.3, 6.05}, {0.1, 5.65}}, {{0.1, 5.65}, {0.35, 5.3}}, {{0.1, 5.65}, {-0.2, 5.55}}}) {
			add_decor_beam(w, p+Vec3{crack[0].x, crack[0].y, side*1.455}, p+Vec3{crack[1].x, crack[1].y, side*1.455}, 0.021, 0.012, {117, 65, 80}, 1, 4)
		}
	}
	// The mane and tail are cut into heavy, asymmetric locks, not shiny tubes.
	ram_statue_piece(w, p, []Vec2{{-3.6, 8.8}, {-3.05, 9.2}, {-2.5, 8.6}, {-2.9, 7.65}}, 1.20, -1.20, STYLE_DARK_ROSE)
	ram_statue_piece(w, p, []Vec2{{-3.05, 8.25}, {-2.35, 8.2}, {-1.6, 6.2}, {-2.3, 6.65}}, 1.18, -1.18, STYLE_DARK_ROSE)
	ram_statue_piece(w, p, []Vec2{{-2.3, 6.9}, {-1.60, 6.6}, {-0.65, 5.9}, {-1.2, 5.5}}, 1.52, -1.52, STYLE_DARK_ROSE)
	ram_statue_piece(w, p, []Vec2{{2.3, 5.9}, {3.55, 6.1}, {4.6, 4.5}, {3.55, 4.7}}, 0.65, -0.65, STYLE_DARK_ROSE)
	ram_statue_piece(w, p, []Vec2{{3.8, 4.4}, {4.7, 4.2}, {5.25, 2.4}, {4.25, 2.65}}, 0.76, -0.76, STYLE_DARK_ROSE)
	// A mute royal crest on the pedestal, absurdly solemn for this subject.
	for side in ([2]f32{-1, 1}) {
		for i in 0..<4 {
			q := p+Vec3{side*(0.65+f32(i)*0.13), 0.95+f32(i)*0.13, 3.42}
			add_decor_beam(w, q, q+Vec3{side*0.24, 0.07, 0}, 0.035, 0.015, {161, 129, 69}, 2, 4)
		}
	}
	for i in 0..<3 {
		x := f32(i-1)*0.32
		add_decor_beam(w, p+Vec3{x-0.15, 1.12, 3.42}, p+Vec3{x, 1.62, 3.42}, 0.038, 0.024, {179, 147, 80}, 2, 4)
		add_decor_beam(w, p+Vec3{x, 1.62, 3.42}, p+Vec3{x+0.15, 1.12, 3.42}, 0.024, 0.038, {179, 147, 80}, 2, 4)
	}
	for side in ([2]f32{-1, 1}) {
		q := p+Vec3{side*7.2, 0, 5.0}
		ram_deck_light(w, q, {242, 199, 139})
		append(&w.lamps, p+Vec3{side*3.5, 7.5, 4.7})
		add_decor_beam(w, p+Vec3{side*3.5, 14, 4.7}, p+Vec3{side*3.5, 7.5, 4.7}, 0.07, 0.07, {59, 60, 53}, 2, 6)
	}
}

// Asymmetric cargo screens the hunter from the entry. A generous opposite
// lane stays open, while the pocket's floor and boxes remain ordinary solids.
ram_cargo_ambush :: proc(w: ^World, s: Section_Recipe) {
	for item in ([4][2]Vec3{
		{{-4.6, 1.15, 14}, {6.6, 2.3, 3.6}},
		{{-5.1, 3.15, 14.2}, {4.6, 1.7, 3.0}},
		{{-6.6, 0.8, 8.5}, {2.8, 1.6, 3.3}},
		{{-5.6, 0.9, -14}, {4.0, 1.8, 4.3}},
	}) {
		center, size := item[0], item[1]
		ram_local_block(w, s, center, size, 11, 0.16)
		for side in ([2]f32{-1, 1}) {
			x := center.x+side*size.x*0.30
			ram_local_beam(w, s, {x, center.y-size.y*0.5+0.12, center.z+size.z*0.5+0.015}, {x, center.y+size.y*0.5-0.10, center.z+size.z*0.5+0.015}, 0.065, {52, 59, 57}, 2)
		}
	}
	for point in ([6]Vec3{{2, 0, 34}, {2, 0, 18}, {2, 0, 7}, {-3.0, 0, 7}, {2, 0, -20}, {0, 0, -35}}) { room_nav(w, s, point) }
}
