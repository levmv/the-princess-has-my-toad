package game

import "core:math"

RAM_Theme :: enum { Board, Copper, Bridge, Porcelain, Machine, Quarantine }

ram_theme :: proc(s: Section_Recipe) -> RAM_Theme {
	switch s.id {
	case 1001, 1013, 1017, 1021, 1023: return .Porcelain
	case 1004, 1007, 1008, 1009, 1022: return .Copper
	case 1005, 1006, 1010, 1011, 1012: return .Bridge
	case 1014, 1015, 1016: return .Machine
	case 1019, 1020: return .Quarantine
	}
	if s.role == .Service_Passage { return .Copper }
	return .Board
}

ram_theme_accent :: proc(theme: RAM_Theme) -> [3]u8 {
	switch theme {
	case .Board: return {108, 232, 143}
	case .Copper: return {255, 160, 67}
	case .Bridge: return {118, 177, 255}
	case .Porcelain: return {97, 229, 216}
	case .Machine: return {255, 93, 53}
	case .Quarantine: return {205, 134, 255}
	}
	unreachable()
}

ram_theme_styles :: proc(s: Section_Recipe) -> (int, int) {
	switch ram_theme(s) {
	case .Board: return 10, 6
	case .Copper: return 11, 12
	case .Bridge: return 13, 9
	case .Porcelain: return 14, 3
	case .Machine: return 12, 11
	case .Quarantine: return 15, 14
	}
	unreachable()
}

ram_lamp_color :: proc(w: ^World, position: Vec3) -> Vec3 {
	i := room_at(&w.sector, position-Vec3{0, 0.5, 0})
	if i < 0 { return {1, 0.67, 0.35} }
	c := ram_theme_accent(ram_theme(w.sector.sections[i]))
	return {f32(c[0])/255, f32(c[1])/255, f32(c[2])/255}
}

// Numbers belong to the machinery, baked into the wall mesh. No HUD marker or
// instruction is needed to recognise a return to a previously cleared room.
ram_digit :: proc(w: ^World, p, right: Vec3, digit: int, color: [3]u8) {
	segments := [7][2]Vec2{{{0, 1}, {0.6, 1}}, {{0.6, 1}, {0.6, 0.5}}, {{0.6, 0.5}, {0.6, 0}}, {{0, 0}, {0.6, 0}}, {{0, 0.5}, {0, 0}}, {{0, 1}, {0, 0.5}}, {{0, 0.5}, {0.6, 0.5}}}
	masks := [10]u8{0x3f, 0x06, 0x5b, 0x4f, 0x66, 0x6d, 0x7d, 0x07, 0x7f, 0x6f}
	for segment, i in segments {
		if masks[digit] & (u8(1)<<u8(i)) == 0 { continue }
		add_decor_beam(w, p+right*segment[0].x+Vec3{0, segment[0].y, 0}, p+right*segment[1].x+Vec3{0, segment[1].y, 0}, 0.035, 0.035, color, 2, 4)
	}
}

ram_room_badges :: proc(w: ^World, s: Section_Recipe, accent: [3]u8) {
	for index in 0..<s.door_count {
		door := s.doors[index]
		x_wall := door.side == .West || door.side == .East
		half := (s.depth if x_wall else s.width)*0.5
		offset := door.offset+door.width*0.5+1.35
		if offset+1 > half-0.6 { offset = door.offset-door.width*0.5-1.35 }
		if abs(offset)+1 > half-0.6 { continue }
		normal := Vec3{0, 0, 1 if door.side == .North else -1}
		if x_wall { normal = {1 if door.side == .West else -1, 0, 0} }
		right := cross(Vec3{0, 1, 0}, normal)
		p := s.origin+Vec3{(s.width*0.5-0.65)*(-normal.x), door.bottom+1.5, (s.depth*0.5-0.65)*(-normal.z)}
		if x_wall { p.z += offset } else { p.x += offset }
		// The plaque names the room beyond the opening, not this room at every door.
		destination := s.id
		for link in w.sector.connections[:w.sector.connection_count] {
			if link.a != s.id && link.b != s.id { continue }
			rel := link.position-s.origin
			along := rel.z if x_wall else rel.x
			across := rel.x if x_wall else rel.z
			side := -normal.x if x_wall else -normal.z
			if abs(along-door.offset) < 0.05 && across*side > 0 {
				destination = link.b if link.a == s.id else link.a
				break
			}
		}
		for y in ([2]f32{-0.22, 1.25}) { add_decor_beam(w, p-right+Vec3{0, y, 0}, p+right+Vec3{0, y, 0}, 0.045, 0.045, accent, 3, 4) }
		ram_digit(w, p-right*0.75, right, int(destination)%100/10, accent)
		ram_digit(w, p+right*0.15, right, int(destination)%10, accent)
	}
}

ram_identity :: proc(w: ^World, s: Section_Recipe) {
	theme := ram_theme(s)
	accent := ram_theme_accent(theme)
	ram_room_badges(w, s, accent)
	if exterior_section(s.role) { return }
	span, half := max(s.width, s.depth), min(s.width, s.depth)*0.5
	// Deep wall ribs break up the blank shell. Each family has a different
	// rhythm and cross-section; all protrusions stay against the solid wall.
	count := max(2, int(span/(6 if theme == .Machine else f32(13))))
	for i in 0..<count {
		z := (f32(i)+0.5)*span/f32(count)-span*0.5
		for side in ([2]f32{-1, 1}) {
			x := side*(half-0.64)
			top := s.height-0.35
			if s.role == .Capacitor_Garden && side > 0 { top = min(top, 7.15) }
			if theme == .Copper {
				ram_local_beam(w, s, {x, top, z-1.6}, {x, top-1.1, z-1.6}, 0.25, {159, 91, 44})
				ram_local_beam(w, s, {x, top-1.1, z-1.6}, {x, top-1.1, z+1.6}, 0.25, {159, 91, 44})
				ram_local_beam(w, s, {x, top-1.1, z+1.6}, {x, top, z+1.6}, 0.25, {159, 91, 44})
			} else {
				color := [3]u8{67, 81, 91} if theme != .Porcelain else [3]u8{142, 163, 154}
				ram_local_beam(w, s, {x, 2.9, z}, {x, top, z}, 0.17, color)
				if theme == .Bridge || theme == .Quarantine {
					ram_local_beam(w, s, {x, top, z}, {x-side*min(2, half*0.2), top+0.6, z}, 0.17, color)
				}
				ram_local_beam(w, s, {x-side*0.1, top-1.8, z}, {x-side*0.1, top-0.7, z}, 0.055, accent, 3)
			}
		}
	}
	// A huge broken clock identifies the return from the aerial route; the
	// switching hall instead has a stack of glowing transformer hoops.
	if s.id == 1013 || s.id == 1015 {
		if s.id == 1013 { ram_deck_light(w, s.origin+Vec3{6.2, 0, -16}, DECOR_ORANGE) }
		center := s.origin+Vec3{0, s.height-2, 0}
		if s.id == 1013 { center.y -= 2 }
		for ring in 0..<(1 if s.id == 1013 else 3) {
			radius := f32(3.6)-f32(ring)*0.6
			p := center+Vec3{0, f32(ring)*0.65, 0}
			for i in 0..<16 {
				a, b := f32(i)*math.PI/8, f32(i+1)*math.PI/8
				from, to := Vec3{math.cos(a)*radius, math.sin(a)*radius, 0}, Vec3{math.cos(b)*radius, math.sin(b)*radius, 0}
				if s.id == 1015 { from.y, from.z = 0, from.y; to.y, to.z = 0, to.y }
				add_decor_beam(w, p+from, p+to, 0.16, 0.16, accent, 2, 6)
			}
		}
		if s.id == 1013 {
			add_decor_beam(w, center, center+Vec3{-1.3, 2.0, 0}, 0.16, 0.07, accent, 3, 6)
			add_decor_beam(w, center, center+Vec3{2.6, -0.5, 0}, 0.16, 0.08, {210, 201, 158}, 2, 6)
		}
	}
}
