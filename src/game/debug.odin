package game

import "core:math"

// Explicit developer launch only. The native front end disables persistence
// whenever a room jump is requested, so this cannot advance the user's save.
debug_enter_room :: proc(g: ^State, id: Room_ID) -> bool {
	w := g.world
	index := room_index(&w.sector, id)
	if index < 0 { return false }
	s := w.sector.sections[index]
	nav := &w.room_navigation[index]
	extent := Vec3{PLAYER_RADIUS, PLAYER_HEIGHT*0.5, PLAYER_RADIUS}
	position: Vec3
	found := false
	// A downward scan can put a developer above the route, on the tall chip,
	// or below it, on the recovery floor. Start exterior pieces on their entry.
	#partial switch s.role {
	case .Fracture_Span: position = ram_local(s, {0, 10.03, 34}); found = true
	case .Launch_Terrace: position = ram_local(s, {0, 6.03, 27}); found = true
	case .Charge_Causeway: position = s.origin+CHARGE_LANDINGS[0]+Vec3{0, 0.03, 0}; found = true
	case .Receiver_Terrace: position = ram_local(s, {0, 6.03, -28}); found = true
	}
	if found { found = world_clear_box(w, position+Vec3{0, PLAYER_HEIGHT*0.5, 0}, extent) }
	// Prefer authored navigation points, then a bounded scan inside the room.
	for i in 0..<nav.count+25 {
		if found { break }
		candidate: Vec3
		if i < nav.count { candidate = nav.points[i]+Vec3{0, 0.03, 0}
		} else {
			cell := i-nav.count
			from := s.origin+Vec3{f32(cell%5-2)*s.width*0.16, s.height-0.2, f32(cell/5-2)*s.depth*0.16}
			distance := world_ray(w, from, {0, -1, 0}, s.height+0.1)
			if distance >= s.height+0.1 { continue }
			candidate = from-Vec3{0, distance-0.03, 0}
		}
		if world_clear_box(w, candidate+Vec3{0, PLAYER_HEIGHT*0.5, 0}, extent) { position, found = candidate, true; break }
	}
	if !found { return false }
	g.player.position, g.player.velocity, g.player.grounded = position, {}, true
	delta := s.origin-position
	g.player.yaw, g.player.pitch = math.atan2(delta.x, -delta.z), -0.06
	// Use an existing canonical checkpoint, keeping replay/save validation real.
	closest := length(position-w.spawn)
	for c, i in w.checkpoints[:w.checkpoint_count] {
		distance := length(position-c.position)
		if distance < closest {
			g.checkpoint, g.checkpoint_id, g.mission_checkpoint = c.position, c.id, u8(i+1)
			closest = distance
		}
	}
	capture_checkpoint(g)
	return true
}
