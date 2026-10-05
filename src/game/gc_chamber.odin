package game

import "core:math"

ram_gc_chamber :: proc(w: ^World, s: Section_Recipe) {
	c := s.origin
	p := boss_origin(w)
	// The octagonal reservoir is the actual solid shell. The animated doors,
	// graduation cap, tiny wheels and cleaning arms are attached presentation.
	radius := f32(2.75)
	outer := radius/math.cos(f32(math.PI/8))
	add_block(w, p+Vec3{0, 3.9, 0}, {outer*2, 5.0, outer*2}, 7)
	body := &w.blocks[len(w.blocks)-1]
	for face in 0..<8 {
		a := f32(face)*2*math.PI/8
		n := Vec3{math.cos(a), 0, math.sin(a)}
		clip_block(body, n, p+n*radius)
	}
	// Side decks are comfortably jumpable. Their raised floor protects from
	// low brushes, but leaves an exposed firing position in the last phase.
	for x in ([2]f32{-24, 24}) {
		for z in ([2]f32{-11, 11}) {
			ram_block(w, c+Vec3{x, 0.9, z}, {7.5, 1.8, 9}, 3, 0.65)
			ram_block(w, c+Vec3{x, 0.42, z+5.6}, {5, 0.84, 2.4}, 8, 0.25)
			add_decor_beam(w, c+Vec3{x-3.2, 1.84, z+3.8}, c+Vec3{x+3.2, 1.84, z+3.8}, 0.08, 0.08, DECOR_MINT, 3, 6)
		}
	}
	// Recessed collection rails and a wide overhead gantry give the finale
	// its own silhouette without scattering cubes across the swept floor.
	for x in ([2]f32{-28, 28}) {
		for z in ([2]f32{-24, 24}) {
			ram_column(w, c+Vec3{x, 0, z}, 1.0, 12, 3)
			add_decor_beam(w, c+Vec3{x, 11.8, z}, c+Vec3{0, 14, z}, 0.35, 0.35, {128, 108, 81}, 0, 6)
		}
		for i in 0..<7 {
			z := -21+f32(i)*7
			add_decor_beam(w, c+Vec3{x, 0.1, z}, c+Vec3{x, 0.1, z+4}, 0.10, 0.10, DECOR_ORANGE, 3, 4)
		}
	}
	for x in ([2]f32{-10, 10}) {
		room_nav_world(w, s, c+Vec3{x, 0, 12})
		room_nav_world(w, s, c+Vec3{x, 0, -17})
	}
	append(&w.lamps, c+Vec3{0, 6, 18}, c+Vec3{0, 7, -18})
	// Defeating the collector retracts this real door into the overhead lintel.
	for side in ([2]f32{-1, 1}) { ram_block(w, c+Vec3{side*17.5, 8, -20}, {25, 16, 1.4}, 12, 0.12) }
	ram_block(w, c+Vec3{0, 11, -20}, {10, 10, 1.4}, 12, 0.10)
	w.boss_exit = {center = c+Vec3{0, 3, -20}, size = {10, 6, 0.55}, style = 12}
	for side in ([2]f32{-1, 1}) { ram_deck_light(w, c+Vec3{side*4.2, 0, -18.7}, DECOR_MINT) }
}
