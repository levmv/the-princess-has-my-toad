package game

import "core:math"

// Large equipment is solid; contacts, windings and cables are baked trim.
// Each installation stays out of the walking lanes and has its own silhouette.
ram_patch_cabinet :: proc(w: ^World, s: Section_Recipe) {
	p := s.origin+Vec3{-8.9, 0, -1}
	ram_block(w, p+Vec3{0, 0.25, 0}, {3.7, 0.5, 8.2}, 12, 0.25)
	ram_block(w, p+Vec3{0, 2.2, 0}, {3.4, 3.9, 7.6}, 12, 0.24)
	// A pale frame surrounds five exposed circuit cards on a recessed dark face.
	for z in ([2]f32{-3.9, 3.9}) {
		ram_block(w, p+Vec3{0.05, 2.2, z}, {3.5, 4.3, 0.28}, 14, 0.06)
	}
	for y in ([2]f32{0.38, 4.22}) {
		ram_block(w, p+Vec3{1.75, y, 0}, {0.32, 0.28, 7.7}, 14, 0.04)
	}
	for card in 0..<5 {
		z := f32(card-2)*1.38
		ram_block(w, p+Vec3{1.73, 2.15, z}, {0.12, 3.0, 1.12}, 10, 0.02)
		for socket in 0..<4 {
			y := 1.03+f32(socket)*0.68
			q := p+Vec3{1.83, y, z}
			add_decor_beam(w, q, q+Vec3{0.12, 0, 0}, 0.19, 0.16, {53, 58, 48}, 1, 6)
			for side in ([2]f32{-1, 1}) {
				add_decor_beam(w, q+Vec3{0, -0.17, side*0.38}, q+Vec3{0, 0.18, side*0.38}, 0.038, 0.038, {171, 132, 70}, 2, 4)
			}
		}
		// Patch cords sag unevenly between cards; muted rubber, no neon outlines.
		if card < 4 {
			a := p+Vec3{2.02, 2.38, z}
			b := p+Vec3{2.15, 1.25+f32(card%2)*0.32, z+0.62}
			c := p+Vec3{2.02, 3.06, z+1.38}
			add_decor_beam(w, a, b, 0.065, 0.065, {121, 86, 51}, 1, 6)
			add_decor_beam(w, b, c, 0.065, 0.065, {121, 86, 51}, 1, 6)
		}
		q := p+Vec3{1.86, 3.35, z}
		add_decor_beam(w, q, q+Vec3{0.03, 0, 0}, 0.055, 0.055, {163, 214, 118}, 3, 6)
	}
	// A displaced service panel and two bundles make this a worked-on machine.
	ram_block(w, p+Vec3{0.85, 2.25, 4.95}, {0.28, 4.1, 1.9}, 14, 0.08)
	for bundle in 0..<2 {
		z := -3+f32(bundle)*4
		path := [5]Vec3{{-7.2, 4.28, z}, {-6.6, 4.65, z}, {-3, 4.72, z}, {5.8, 4.72, z-1}, {9.9, 3.85, z-1}}
		for i in 0..<len(path)-1 {
			add_decor_beam(w, s.origin+path[i], s.origin+path[i+1], 0.17, 0.17, {57, 62, 54}, 1, 8)
		}
	}
	append(&w.lamps, p+Vec3{2.4, 3.9, 0})
}

ram_induction_coil :: proc(w: ^World, s: Section_Recipe) {
	p := s.origin+Vec3{5, 0, -13.8}
	ram_block(w, p+Vec3{0, 0.42, 0}, {11.2, 0.84, 4.4}, 12, 0.5)
	for side in ([2]f32{-1, 1}) {
		ram_column(w, p+Vec3{side*4.3, 0.84, 0}, 0.78, 3.5, 14)
		// Broad ceramic sheds interrupt the narrow supporting neck.
		for flange in 0..<5 {
			q := p+Vec3{side*4.3, 1.25+f32(flange)*0.52, 0}
			add_decor_beam(w, q, q+Vec3{0, 0.17, 0}, 1.04, 0.85, {159, 161, 136}, 1, 10)
		}
		add_decor_beam(w, p+Vec3{side*4.3, 4.3, 0}, p+Vec3{side*5.1, 5.8, -0.4}, 0.20, 0.20, {114, 85, 52}, 2, 8)
		add_decor_beam(w, p+Vec3{side*5.1, 5.8, -0.4}, p+Vec3{side*5.1, 7.6, -2.3}, 0.20, 0.20, {55, 62, 51}, 1, 8)
	}
	center := p+Vec3{0, 4.15, 0}
	// An octagonal iron core along X, with matching collision planes.
	add_block(w, center, {7.8, 3.2, 3.2}, 12)
	core := &w.blocks[len(w.blocks)-1]
	for side in 0..<8 {
		a := f32(side)*math.PI/4
		n := Vec3{0, math.cos(a), math.sin(a)}
		clip_block(core, n, center+n*1.45)
	}
	// One continuous helix, rather than a stack of luminous rings.
	turns, segments := 10, 12
	for i in 0..<turns*segments {
		u, v := f32(i)/f32(turns*segments), f32(i+1)/f32(turns*segments)
		a, b := u*f32(turns)*2*math.PI, v*f32(turns)*2*math.PI
		from := center+Vec3{(u-0.5)*7.2, math.cos(a)*1.63, math.sin(a)*1.63}
		to := center+Vec3{(v-0.5)*7.2, math.cos(b)*1.63, math.sin(b)*1.63}
		add_decor_beam(w, from, to, 0.19, 0.19, {151, 96, 59}, 1, 6)
	}
	for side in ([2]f32{-1, 1}) {
		q := p+Vec3{side*4, 0.84, 1.8}
		ram_deck_light(w, q, {241, 178, 105})
	}
}
