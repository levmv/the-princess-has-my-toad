package game

// These are traversal pieces with explicit landings, not ordinary rooms with
// their ceilings removed. Their empty volumes remain empty in collision too.
exterior_section :: proc(role: Section_Role) -> bool {
	return role == .Fracture_Span || role == .Launch_Terrace || role == .Charge_Causeway || role == .Receiver_Terrace
}

// Return the lower wall pieces so an adjoining ramp can trim its own sill.
ram_facades :: proc(w: ^World, s: Section_Recipe) -> (sills: [Door_Side]int) {
	for &index in sills { index = -1 }
	wall, _ := ram_theme_styles(s)
	for i in 0..<s.door_count {
		door := s.doors[i]
		lo, hi := door.offset-door.width*0.5, door.offset+door.width*0.5
		top := min(s.height, door.bottom+door.height+3)
		room_wall_piece(w, s, door.side, lo-2, lo, 0, top, wall)
		room_wall_piece(w, s, door.side, hi, hi+2, 0, top, wall)
		first := len(w.blocks)
		room_wall_piece(w, s, door.side, lo, hi, 0, door.bottom, wall)
		if len(w.blocks) > first { sills[door.side] = first }
		room_wall_piece(w, s, door.side, lo, hi, door.bottom+door.height, top, wall)
	}
	return
}

ram_deck_light :: proc(w: ^World, p: Vec3, color: [3]u8 = DECOR_MINT) {
	light := p+Vec3{0, 2.8, 0}
	add_decor_beam(w, p, light, 0.09, 0.07, {70, 93, 106}, 0, 6)
	add_decor_beam(w, light-Vec3{0.45, 0, 0}, light+Vec3{0.45, 0, 0}, 0.1, 0.1, color, 3, 6)
	append(&w.lamps, light)
}

// Flat conductors lie inside the landing's bevel. They give the exposed
// platforms a scale and material rhythm without adding a grid or collision.
ram_deck_traces :: proc(w: ^World, feet, size: Vec3) {
	for side in ([2]f32{-1, 1}) {
		for lane in 0..<3 {
			x := side*(size.x*0.5-0.9-f32(lane)*0.32)
			z := size.z*0.5-1.0-f32(lane)*0.35
			a, b, c := feet+Vec3{x, 0.025, z}, feet+Vec3{x, 0.025, 0.2}, feet+Vec3{x-side*0.85, 0.025, -0.65}
			for path in ([2][2]Vec3{{a, b}, {b, c}}) {
				add_decor_beam(w, path[0], path[1], 0.045, 0.025, {192, 144, 69}, 0, 4)
			}
			add_decor_beam(w, c, c+Vec3{0, 0.007, 0}, 0.14, 0.14, {211, 173, 94}, 2, 8)
		}
	}
}

ram_fracture_span :: proc(w: ^World, s: Section_Recipe) {
	sills := ram_facades(w, s)
	// 28 metres between lips; the far lip is three metres lower. A normal
	// jump falls short. Deploying the wing turns the height into useful range.
	ram_local_block(w, s, {0, 9.45, 27}, {20, 1.1, 30}, 12, 0.6)
	ram_local_block(w, s, {0, 6.45, -21.5}, {18, 1.1, 11}, 13, 0.6)
	exit := ram_local(s, {0, 10, -42})
	ram_ramp(w, ram_local(s, {0, 7, -27}), exit, 12, 13)
	// The facade extends 0.6 m into the slope and otherwise leaves a 12 cm
	// vertical lip. Recess its sill under the ramp, including the rendered face.
	// Removing material keeps existing saved positions clear of the geometry.
	sill := sills[.East if s.width > s.depth else .North]
	assert(sill >= 0)
	clip_block(&w.blocks[sill], w.blocks[len(w.blocks)-1].clips[0].normal, exit-Vec3{0, 0.01, 0})
	// The first missed crossing has a real floor and a ramp back to the takeoff
	// lip. It does not teleport the player or silently complete the crossing.
	ram_local_block(w, s, {0, -0.65, 0}, {32, 1.3, 84}, 12, 0.25)
	ram_ramp(w, ram_local(s, {12, 0, -5}), ram_local(s, {12, 10, 32}), 3.8, 12)
	ram_local_block(w, s, {12, 9.45, 34}, {4, 1.1, 4}, 12, 0.25)
	// The far landing is the roof of a maintenance pocket. Tall baffles stop
	// fire from either lip; open flanks admit a player who drops to the floor.
	for z in ([2]f32{-16.4, -28.4}) {
		ram_local_block(w, s, {0, 2.75, z}, {14, 5.5, 1.2}, 13, 0.3)
		for x in ([2]f32{-6.4, 6.4}) {
			ram_local_beam(w, s, {x, 0.3, z-0.63}, {x, 4.7, z-0.63}, 0.07, DECOR_ORANGE, 3)
		}
	}
	for x in ([2]f32{-8.5, 8.5}) {
		ram_column(w, ram_local(s, {x, 0, -26}), 0.45, 5.9, 13)
	}
	ram_deck_light(w, ram_local(s, {-5, 0, -25}), DECOR_MINT)
	for p in ([8]Vec3{{-10, 0, -11}, {10, 0, -11}, {-10, 0, -22}, {10, 0, -22}, {-4, 0, -22}, {4, 0, -22}, {-10, 0, -32}, {10, 0, -32}}) {
		room_nav(w, s, p)
	}
	for side in ([2]f32{-1, 1}) {
		ram_local_block(w, s, {side*15.5, 4.3, 0}, {1, 8.6, 84}, 11, 0.15)
		ram_local_beam(w, s, {side*8.5, 7.08, -16.5}, {side*8.5, 7.08, -26.5}, 0.07, DECOR_MINT, 3)
		ram_deck_light(w, ram_local(s, {side*8, 10, 13}), DECOR_ORANGE)
		ram_deck_light(w, ram_local(s, {side*8, 7, -25}), DECOR_MINT)
		// Severed gold traces expose the two banks of the fracture.
		for pin in 0..<7 {
			x := f32(pin-3)*2.1
			z := 11.4 if side > 0 else f32(-15.4)
			y := 9.5 if side > 0 else f32(6.5)
			ram_local_beam(w, s, {x, y, z}, {x+0.35, y-1.1, z-side*1.4}, 0.15, {205, 143, 58})
		}
	}
	ram_deck_light(w, ram_local(s, {10, 0, -4}), DECOR_ORANGE)
}

ram_launch_terrace :: proc(w: ^World, s: Section_Recipe) {
	ram_facades(w, s)
	ram_local_block(w, s, {0, 5.45, 26}, {20, 1.1, 20}, 13, 0.6)
	ram_ramp(w, ram_local(s, {0, 6, 16}), ram_local(s, {0, 11, -4}), 10, 13)
	ram_local_block(w, s, {0, 10.45, -8}, {16, 1.1, 8}, 13, 0.6)
	ram_ramp(w, ram_local(s, {0, 11, -12}), ram_local(s, {0, 16, -28}), 10, 13)
	ram_local_block(w, s, {0, 15.45, -32}, {20, 1.1, 8}, 13, 0.6)
	for p in ([3]Vec3{{0, 6, 26}, {0, 11, -8}, {0, 16, -32}}) {
		for side in ([2]f32{-1, 1}) {
			ram_column(w, ram_local(s, {side*6.5, -16, p.z}), 0.7, p.y+15, 3)
			ram_deck_light(w, ram_local(s, p+Vec3{side*6.5, 0, 0}), {118, 177, 255})
		}
	}
}

// Local feet positions, shared by the physical platforms and traversal tools.
// The bent route wraps a tall memory package; one straight glide is obstructed.
@(rodata) CHARGE_LANDINGS := [6]Vec3{
	{-31, 34, 42}, {-17, 32, 25}, {4, 30, 9},
	{20, 28, -9}, {0, 26, -26}, {-27, 24, -42},
}

ram_charge_causeway :: proc(w: ^World, s: Section_Recipe) {
	ram_facades(w, s)
	for p, i in CHARGE_LANDINGS {
		end := i == 0 || i == len(CHARGE_LANDINGS)-1
		size := Vec3{7.2, 0.8, 7.2}
		if i == 0 { size = {14, 1.2, 16} }
		if i == len(CHARGE_LANDINGS)-1 { size = {22, 1.2, 16} }
		if i == 3 { size = {11, 0.8, 10} }
		ram_column(w, s.origin+Vec3{p.x, 0, p.z}, 2.4 if end else f32(2.8), p.y-size.y, 13)
		ram_block(w, s.origin+p-Vec3{0, size.y*0.5, 0}, size, 13 if end else 12, 0.7)
		ram_deck_traces(w, s.origin+p, size)
		for side in ([2]f32{-1, 1}) {
			q := s.origin+p+Vec3{side*(size.x*0.5-0.25), 0.04, 0}
			add_decor_beam(w, q-Vec3{0, 0, size.z*0.5-0.4}, q+Vec3{0, 0, size.z*0.5-0.4}, 0.08, 0.08, {118, 177, 255}, 3, 4)
		}
		ram_deck_light(w, s.origin+p+Vec3{size.x*0.5-0.5, 0, size.z*0.5-0.6}, {118, 177, 255})
	}
	// A monumental vertical chip interrupts the direct firing / flight line.
	// Its east edge is eight metres away from the middle landing's centre.
	ram_block(w, s.origin+Vec3{-20, 22.5, 0}, {36, 45, 6}, 10, 1.2)
	for side in ([2]f32{-1, 1}) {
		ram_block(w, s.origin+Vec3{-20, 23, side*3.5}, {23, 24, 1.1}, 3, 0.4)
		for pin in 0..<9 {
			x := -35+f32(pin)*3.6
			add_decor_beam(w, s.origin+Vec3{x, 4, side*3.2}, s.origin+Vec3{x, 38, side*3.2}, 0.19, 0.19, {128, 167, 116}, 0, 6)
			add_decor_beam(w, s.origin+Vec3{x, 38, side*3.2}, s.origin+Vec3{x+1, 41, side*3.2}, 0.19, 0.19, {209, 167, 68}, 2, 6)
		}
	}
}

ram_receiver_terrace :: proc(w: ^World, s: Section_Recipe) {
	ram_facades(w, s)
	ram_local_block(w, s, {0, 5.45, 0}, {22, 1.1, 72}, 13, 0.6)
	for z in ([3]f32{-27, 0, 27}) {
		for side in ([2]f32{-1, 1}) {
			ram_local_block(w, s, {side*10.5, 6.6, z}, {1, 1.2, 12}, 13, 0.15)
			ram_column(w, ram_local(s, {side*8, -16, z}), 0.85, 21, 3)
			ram_deck_light(w, ram_local(s, {side*9.5, 6, z}), {118, 177, 255})
		}
	}
	// The receiver's awning compresses the view before the enclosed rejoin.
	ram_local_block(w, s, {0, 14, 25}, {28, 0.7, 22}, 13, 0.5)
	for side in ([2]f32{-1, 1}) {
		ram_local_block(w, s, {side*10.5, 10, 17}, {0.9, 8, 0.9}, 13, 0.15)
		ram_local_block(w, s, {side*7, 7.2, 0}, {3, 2.4, 7}, 3, 0.5)
	}
}
