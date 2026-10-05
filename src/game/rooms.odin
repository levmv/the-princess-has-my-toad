package game

// A wall is split around its actual portals. The same solids provide collision,
// line of sight and rendered surfaces, including the space above each doorway.
room_wall_piece :: proc(w: ^World, room: Section_Recipe, side: Door_Side, from, to, bottom, top: f32, style: int) {
	if to-from < 0.001 || top-bottom < 0.001 { return }
	c := room.origin+Vec3{0, (top+bottom)*0.5, 0}
	size := Vec3{to-from, top-bottom, 0.6}
	if side == .North || side == .South {
		c.x += (from+to)*0.5
		c.z += (room.depth*0.5-0.3)*(1 if side == .South else -1)
	} else {
		c.z += (from+to)*0.5
		c.x += (room.width*0.5-0.3)*(1 if side == .East else -1)
		size = {0.6, top-bottom, to-from}
	}
	add_block(w, c, size, style)
}

room_roof :: proc(w: ^World, room: Section_Recipe, style: int) {
	along_x := room.width > room.depth
	half := (room.depth if along_x else room.width)*0.5
	across := room.origin.z if along_x else room.origin.x
	along := room.origin.x if along_x else room.origin.z
	span := room.width if along_x else room.depth
	h := room.origin.y+room.height
	profile := [4]Vec2{{across-half, h-0.2}, {across-half*0.5, h+1}, {across+half*0.5, h+1}, {across+half, h-0.2}}
	for i in 0..<3 {
		a, b := profile[i], profile[i+1]
		points := [4]Vec2{a, b, b+Vec2{0, 0.4}, a+Vec2{0, 0.4}}
		add_prism(w, points[:], along+span*0.5, along-span*0.5, style)
		if along_x {
			// Swap X and Z in the solid and all its planes. Faces are subsequently
			// derived from those planes, so the reflected basis needs no mesh hack.
			block := &w.blocks[len(w.blocks)-1]
			block.center.x, block.center.z = block.center.z, block.center.x
			block.size.x, block.size.z = block.size.z, block.size.x
			for &plane in block.clips[:block.clip_count] { plane.normal.x, plane.normal.z = plane.normal.z, plane.normal.x }
		}
	}
}

room_shell :: proc(w: ^World, room: Section_Recipe, wall_style, floor_style: int) {
	add_block(w, room.origin-Vec3{0, 1, 0}, {room.width, 2, room.depth}, floor_style)
	height := room.height+(0 if room.open_roof else 1.4)
	for side in Door_Side {
		side_height := height
		if room.role == .Capacitor_Garden && (side == .South || side == .East) { side_height = min(height, 7.5) }
		doors: [4]Portal
		count := 0
		for i in 0..<room.door_count {
			p := room.doors[i]
			if p.side == side { doors[count] = p; count += 1 }
		}
		for i in 1..<count {
			p := doors[i]
			j := i-1
			for j >= 0 && doors[j].offset > p.offset { doors[j+1] = doors[j]; j -= 1 }
			doors[j+1] = p
		}
		half := (room.width if side == .North || side == .South else room.depth)*0.5
		cursor := -half
		for p in doors[:count] {
			lo, hi := p.offset-p.width*0.5, p.offset+p.width*0.5
			assert(lo >= cursor-0.01, "Overlapping room portals")
			room_wall_piece(w, room, side, cursor, lo, 0, side_height, wall_style)
			room_wall_piece(w, room, side, lo, hi, 0, p.bottom, wall_style)
			room_wall_piece(w, room, side, lo, hi, p.bottom+p.height, side_height, wall_style)
			cursor = hi
		}
		room_wall_piece(w, room, side, cursor, half, 0, side_height, wall_style)
	}
	if !room.open_roof { room_roof(w, room, wall_style) }
}
