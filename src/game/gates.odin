package game

GATE_CAPACITY :: 4
Gate_Def :: struct { id: Object_ID, a, b: Room_ID, control: Location_Def }
// Static gate definitions compile into a small dynamic collision layer. Opening
// a door never invalidates the static BVH or rebakes the architecture meshes.
Gate :: struct {
	id: Object_ID,
	a, b: Room_ID,
	closed: Block,
	control: Vec3,
	open: bool,
	amount: f32,
}

gate_shape :: proc(gate: Gate) -> Block {
	b := gate.closed
	b.center.y += (b.size.y+0.3)*gate.amount
	return b
}

build_gates :: proc(w: ^World) {
	w.gates, w.gate_count = {}, w.sector.gate_count
	for def, i in w.sector.gates[:w.gate_count] {
		for c in w.sector.connections[:w.sector.connection_count] {
			if !((c.a == def.a && c.b == def.b) || (c.a == def.b && c.b == def.a)) { continue }
			s := w.sector.sections[room_index(&w.sector, c.a)]
			x_side := abs(abs(c.position.x-s.origin.x)-s.width*0.5) < 0.05
			size := Vec3{c.width, c.height, 0.35}
			if x_side { size.x, size.z = size.z, size.x }
			control, _ := resolve_location(&w.sector, def.control)
			w.gates[i] = {def.id, def.a, def.b, {center = c.position+Vec3{0, c.height*0.5, 0}, size = size, style = 3}, control, false, 0}
			break
		}
	}
}

gate_target :: proc(w: ^World, player: ^Player) -> int {
	eye := player.position+Vec3{0, 1.3, 0}
	look := forward(player.yaw, 0)
	for gate, i in w.gates[:w.gate_count] {
		if gate.open { continue }
		delta := gate.control-eye
		distance := length(delta)
		if distance > 2.6 || dot(normalized(Vec3{delta.x, 0, delta.z}), look) < 0.35 { continue }
		if world_ray(w, eye, normalized(delta), distance) < distance-0.1 { continue }
		return i
	}
	return -1
}

update_gates :: proc(g: ^State, input: Input, dt: f32) {
	if input.interact_pressed {
		if index := gate_target(g.world, &g.player); index >= 0 {
			g.world.gates[index].open = true
			sound_event(g, .GateSlide, g.world.gates[index].closed.center)
			checkpoint_changed(g)
			light_flash(g, g.world.gates[index].control, {0.2, 1, 0.65}, 3, 2, 0.3)
		}
	}
	for &gate in g.world.gates[:g.world.gate_count] {
		if !gate.open || gate.amount >= 1 { continue }
		candidate := gate
		candidate.amount = min(1, gate.amount+dt*1.8)
		shape := gate_shape(candidate)
		if overlap(g.player.position, shape) { continue }
		blocked := false
		for e in g.enemies[:g.enemy_count] {
			if !enemy_active(e) { continue }
			half := shape.size*0.5+enemy_extent(e.kind)
			delta := e.position-shape.center
			if abs(delta.x) < half.x && abs(delta.y) < half.y && abs(delta.z) < half.z { blocked = true; break }
		}
		if !blocked { gate.amount = candidate.amount }
	}
}

gate_blocks_link :: proc(w: ^World, c: Connection, kind: Enemy_Kind) -> bool {
	for gate in w.gates[:w.gate_count] {
		if !((gate.a == c.a && gate.b == c.b) || (gate.a == c.b && gate.b == c.a)) { continue }
		if gate.amount*(gate.closed.size.y+0.3) < enemy_extent(kind).y*2+0.2 { return true }
	}
	return false
}

update_secrets :: proc(g: ^State) {
	i := room_at(&g.world.sector, g.player.position)
	if i < 0 || g.world.sector.sections[i].intent != .Secret { return }
	id := room_object_id(g.world.sector.sections[i].id, 0x500)
	for found in g.secrets[:g.secret_count] { if found == id { return } }
	assert(g.secret_count < len(g.secrets))
	g.secrets[g.secret_count] = id
	g.secret_count += 1
	g.message, g.message_time = 11, 2.4
	g.pickup_sequence += 1
	checkpoint_changed(g)
}
