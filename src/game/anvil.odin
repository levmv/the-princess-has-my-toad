package game

Anvil_Phase :: enum u8 { Idle = 0, Warning = 1, Falling = 2, Rest = 3 }
Anvil_State :: struct { phase: Anvil_Phase, target, position: Vec3, timer, speed: f32, struck: bool }
ANVIL_EXTENT :: Vec3{0.9, 0.6, 0.55}

// Recognition is presentation input, but this small state machine is also
// usable by command playback and tests. Menus never feed it keystrokes.
Cheat_Entry :: struct { count: int, age: f32 }
cheat_key :: proc(entry: ^Cheat_Entry, pressed: u8, elapsed: f32) -> bool {
	key := pressed
	entry.age += elapsed
	if entry.age > 3 { entry.count = 0 }
	entry.age = 0
	word := "IDDQD"
	if key >= 'a' && key <= 'z' { key = key-'a'+'A' }
	if key != word[entry.count] { entry.count = 1 if key == 'I' else 0; return false }
	entry.count += 1
	if entry.count == len(word) { entry.count = 0; return true }
	return false
}

drop_anvil :: proc(g: ^State) -> bool {
	if g.anvil.phase != .Idle { return false }
	from := g.player.position+Vec3{0, 0.2, 0}
	down := world_ray(g.world, from, {0, -1, 0}, 25)
	if down >= 25 { return false }
	floor := from+Vec3{0, -down+0.02, 0}
	bottom := floor+Vec3{0, ANVIL_EXTENT.y+0.03, 0}
	if !world_clear_box(g.world, bottom, ANVIL_EXTENT) { return false }
	fraction, _ := world_sweep(g.world, bottom, {0, 8, 0}, ANVIL_EXTENT)
	start := bottom+Vec3{0, max(0, 8*fraction-0.03), 0}
	if start.y-bottom.y < 1.8 { return false }
	g.anvil = {.Warning, floor, start, 1.2, 0, false}
	g.message, g.message_time = 12, 3
	sound_event(g, .AnvilFall, floor+Vec3{0, 2, 0})
	return true
}

update_anvil :: proc(g: ^State, input: Input, dt: f32) {
	if input.anvil_pressed { drop_anvil(g) }
	a := &g.anvil
	if a.phase == .Idle { return }
	a.timer = max(0, a.timer-dt)
	switch a.phase {
	case .Warning: if a.timer <= 0 { a.phase = .Falling }
	case .Falling:
		a.speed += 52*dt
		delta := Vec3{0, -a.speed*dt, 0}
		fraction, _ := world_sweep(g.world, a.position, delta, ANVIL_EXTENT)
		end := a.position+delta*fraction
		player := g.player.position
		if !a.struck && abs(player.x-a.position.x) < ANVIL_EXTENT.x+PLAYER_RADIUS && abs(player.z-a.position.z) < ANVIL_EXTENT.z+PLAYER_RADIUS && player.y < a.position.y+ANVIL_EXTENT.y && player.y+PLAYER_HEIGHT > end.y-ANVIL_EXTENT.y {
			a.struck = true
			damage(g, 35, .Anvil)
			// This is one falling object, never a repeated damage volume.
			if g.respawn_pending { return }
		}
		a.position = end
		if fraction < 1 {
			a.phase, a.timer = .Rest, 1.2
			sound_event(g, .AnvilHit, a.position)
			light_flash(g, a.position, {1, 0.72, 0.2}, 6, 3, 0.18)
			emit(g, a.position, 24, 2)
		}
	case .Rest: if a.timer <= 0 { a^ = {} }
	case .Idle:
	}
}

anvil_valid :: proc(a: Anvil_State) -> bool {
	return a.phase >= .Idle && a.phase <= .Rest && a.timer >= 0 && a.timer <= 1.21 && a.speed >= 0 && a.speed < 60 && length(a.position-a.target) < 12
}
