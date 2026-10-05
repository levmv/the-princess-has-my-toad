package game

lift_cable :: proc(w: ^World) -> [5]Vec3 {
	i := room_index(&w.sector, w.sector.mechanism_room)
	c := w.sector.sections[i].origin
	return {w.lift.button+Vec3{0, -1.4, 0}, c+Vec3{-14.8, 5, -6}, c+Vec3{-14.8, 0.25, -6}, c+Vec3{-14.8, 0.25, -12}, c+Vec3{-3.5, 0.25, -12}}
}

ram_lift_switch :: proc(w: ^World, s: Section_Recipe, vent_index: int) {
	w.lift = {button = s.origin+Vec3{-14.8, 10, -6}, vent_index = vent_index}
	button := w.lift.button
	// A pale bezel frames the shot target on the wall opposite the entrance.
	ram_block(w, button-Vec3{0.6, 0, 0}, {0.6, 3.4, 3.4}, 14, 0.12)
	ram_block(w, button-Vec3{0.20, 0, 0}, {0.2, 2.7, 2.7}, 12, 0.04)
	for side in ([2]f32{-1, 1}) {
		add_decor_beam(w, button+Vec3{-0.06, -1.1, side*1.23}, button+Vec3{-0.06, 1.1, side*1.23}, 0.055, 0.055, {239, 189, 97}, 3, 4)
	}
	cable := lift_cable(w)
	for i in 0..<len(cable)-1 { add_decor_beam(w, cable[i], cable[i+1], 0.13, 0.13, {125, 90, 53}, 2, 8) }
}
