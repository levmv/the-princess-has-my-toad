package game

// Spatial groups set the pace; every actor exists from level load.
ram_encounter :: proc(w: ^World, s: Section_Recipe, seed: ^u32) {
	if s.population == .None { return }
	e := Encounter{room = s.id}
	if w.sector.key != .RAM_Bank_01 || !ram_authored_encounter(&e, s) {
		ram_population(&e, w, s)
	}
	for &spawn, i in e.spawns[:e.count] {
		// The whole visible lane is dangerous. Health buys time for a readable
		// attack; valve/core hits still cut it by three instead of making sponges.
		spawn.awareness = 90 if spawn.kind == .Sentry else 75
		switch spawn.kind {
		case .Sentry: spawn.health = 14
		case .Interceptor: spawn.health = 12
		case .Crab: spawn.health = 24
		case .Kettle: spawn.health = 28
		case .Nanny: spawn.health = 18
		case .Rabbit: spawn.health, spawn.awareness = 84, 24
		case .Rabbit_Young: spawn.health = 42
		case .Rabbit_Kit: spawn.health = 20
		}
		if w.sector.key == .RAM_Bank_01 {
			// The arrival gives time to take control. Later rooms retain their
			// full reach; early pacing comes from composition and real cover.
			if s.id == 1001 { spawn.health, spawn.awareness = 8, 14 }
			if s.id == 1002 { spawn.awareness = 28 }
		}
		if enemy_grounded_kind(spawn.kind) {
			floor := CHARGE_LANDINGS[3].y if s.role == .Charge_Causeway else f32(0)
			spawn.position.y = floor+enemy_extent(spawn.kind).y+0.04
		}
		spawn.position = ram_local(s, spawn.position+Vec3{(random_stream(seed)-0.5)*0.35, 0, 0})
		spawn.id = room_object_id(s.id, u16(0x100+i))
	}
	append(&w.encounters, e)
}

// Reusable populations choose lanes and roles. Health and perception are set
// once by ram_encounter, after all authored placement decisions.
ram_population :: proc(e: ^Encounter, w: ^World, s: Section_Recipe) {
	span := max(s.width, s.depth)
	width := min(s.width, s.depth)
	switch s.population {
	case .None: return
	case .Sparse_Sentries:
		e.count = 3
		for &spawn, i in e.spawns[:e.count] {
			spawn = {position = {f32(i%2*2-1)*min(2.7, width*0.18), min(s.height-1.2, 2.4+f32(i)*0.7), f32(1-i)*span*0.3}, kind = .Sentry}
		}
	case .Passage_Hunters:
		e.count = 2
		e.spawns[0] = {position = {-1.0, 2.0, span*0.22}, kind = .Interceptor}
		e.spawns[1] = {position = {1.0, 2.8, -span*0.22}, kind = .Interceptor}
	case .Mixed_Patrol:
		e.count = 6
		if w.sector.key == .RAM_Bank_01 && s.role == .Switching_Hall { e.count = 8 }
		kinds := [8]Enemy_Kind{.Sentry, .Interceptor, .Crab, .Kettle, .Nanny, .Sentry, .Sentry, .Interceptor}
		for &spawn, i in e.spawns[:e.count] {
			spawn.position = {f32(i%2*2-1)*min(width*0.16, 5.5), min(s.height-1.2, 3+f32(i%2)*1.3), f32(i/2-1)*span*0.27}
			spawn.kind = kinds[i]
			if enemy_grounded_kind(spawn.kind) { spawn.position.x, spawn.position.y = f32(i%2*2-1)*min(width*0.08, 3), enemy_extent(spawn.kind).y+0.03 }
		}
	case .Crossfire:
		e.count = 3
		e.spawns[0] = {position = {-min(2.8, width*0.16), 2.5, span*0.28}, kind = .Sentry}
		e.spawns[1] = {position = {min(2.8, width*0.16), 2.0, 0}, kind = .Interceptor}
		e.spawns[2] = {position = {0, 0.68, -span*0.30}, kind = .Crab}
		if s.role == .Stair_Hall {
			e.spawns[0].position = {0, 5.6, -13}
			e.spawns[1].position = {-5, 4.5, -10}
			e.spawns[2].position = {6, 0.68, 6}
		}
	}
	if s.role == .Memory_Gallery {
		if s.population == .Crossfire { e.count = 6 }
		for &spawn, i in e.spawns[:e.count] {
			lane := f32(1 if i%2 == 0 else -1)*(s.width*0.25+2)
			z := (0.39-f32(i/2)*0.36)*s.depth
			if s.variant == .Weave {
				row := min(2, i/2)
				sign := f32(1 if row%2 == 0 else -1)
				lane = -sign*s.width*0.26
				z = f32(1-row)*s.depth*0.29+(5.8 if i%2 == 0 else -5.8)
			}
			kind := spawn.kind
			if s.population == .Crossfire {
				kinds := [6]Enemy_Kind{.Sentry, .Interceptor, .Crab, .Sentry, .Interceptor, .Crab}
				kind = kinds[i]
			}
			y := enemy_extent(kind).y+0.04 if enemy_grounded_kind(kind) else min(s.height-1.1, f32(2.3))
			spawn = {position = {lane, y, z}, kind = kind}
		}
	}
	if s.role == .Service_Passage && s.variant != .Authored {
		for &spawn, i in e.spawns[:e.count] {
			// End pockets precede/follow a bend, leaving a real reaction window.
			spawn.position = {f32(i%2*2-1)*0.7, 2.0, (0.43 if i == 0 else -0.43)*span}
		}
	}
	if s.role == .Address_Bridge {
		for &spawn in e.spawns[:e.count] { spawn.position.y = 8.4 }
	}
	if s.role == .Fracture_Span {
		e.count = 5
		e.spawns[0] = {position = {-6, 13, 17}, kind = .Sentry}
		e.spawns[1] = {position = {-6, 9, -22}, kind = .Sentry}
		e.spawns[2] = {position = {-4, 0, -22}, kind = .Crab}
		e.spawns[3] = {position = {4, 0, -22}, kind = .Crab}
		e.spawns[4] = {position = {0, 0, -26}, kind = .Crab}
	}
	if s.role == .Launch_Terrace {
		points := [3]Vec3{{-4, 10, 19}, {4, 15, -8}, {-5, 19, -32}}
		for &spawn, i in e.spawns[:e.count] { spawn.position = points[i] }
	}
	if s.role == .Charge_Causeway {
		points := [3]Vec3{{4, 34, 17}, {26, 32, -9}, {-3, 29, -30}}
		for &spawn, i in e.spawns[:e.count] { spawn.position = points[i] }
		// One fairy becomes a landing guard. Adjacent columns remain reachable
		// by a longer glide; supplies reward taking the close-range fight.
		e.spawns[1].position, e.spawns[1].kind = CHARGE_LANDINGS[3], .Crab
	}
	if s.role == .Receiver_Terrace {
		e.spawns[0].position, e.spawns[1].position = {-5, 8.4, 12}, {5, 8.4, -12}
	}
	if s.role == .Capacitor_Garden || s.role == .Switching_Hall {
		positions := [8]Vec3{{-11, 2.8, 13}, {11, 2.3, 12}, {-12, 0.69, -9}, {14, 0.94, -9}, {13, 1.14, -16}, {-9, 4.2, -17}, {18, 4, 0}, {-17, 6, -6}}
		for &spawn, i in e.spawns[:e.count] {
			spawn.position = positions[i]
			if s.role == .Switching_Hall { spawn.position = {positions[i].z, positions[i].y, -positions[i].x} }
		}
	}
	if s.role == .Capacitor_Garden {
		positions := [8]Vec3{{-10, 3, 5}, {9, 3.5, 14}, {-12, 0, -9}, {9, 0, -11}, {-8, 0, -18}, {18, 6, -5}, {-6, 8, 18}, {-16, 3.4, -4}}
		for &spawn, i in e.spawns[:e.count] { spawn.position = positions[i] }
	}
	// The later hall has an extra ground flanker under the flying crossfire.
	if w.sector.key == .RAM_Bank_01 && s.role == .Switching_Hall {
		e.spawns[6].kind, e.spawns[6].position = .Crab, {0, 0, -18}
	}
	if w.sector.key == .RAM_Bank_01 && s.id == 1014 && s.variant == .Authored {
		e.spawns[0].kind, e.spawns[0].position = .Crab, {-3.2, 0, 8.5}
		e.spawns[1].position = {1.5, 2.5, -24}
	}
}

// Bank 01 introduces attacks in space, without wave timers or announcements.
// These authored beats override the reusable room populations; the geometry
// variant only changes the safe lanes used by the second encounter.
ram_authored_encounter :: proc(e: ^Encounter, s: Section_Recipe) -> bool {
	switch s.id {
	case 1001:
		e.count = 1
		e.spawns[0] = {position = {0, 2.2, -8}, kind = .Interceptor}
	case 1002:
		e.count = 2
		e.spawns[0] = {position = {-10, 2.3, 14}, kind = .Interceptor}
		e.spawns[1] = {position = {10, 0, -4}, kind = .Crab}
		if s.variant == .Weave {
			e.spawns[0].position = {s.width*0.26, 2.3, 6.5}
			e.spawns[1].position = {9, 0, -8.5}
		}
	case 1005:
		e.count = 6
		e.spawns[0] = {position = {-10, 3, 5}, kind = .Sentry}
		e.spawns[1] = {position = {9, 3.5, 14}, kind = .Interceptor}
		e.spawns[2] = {position = {-12, 0, -9}, kind = .Crab}
		e.spawns[3] = {position = {9, 0, -11}, kind = .Kettle}
		e.spawns[4] = {position = {18, 6, -5}, kind = .Sentry}
		e.spawns[5] = {position = {-20, 0, -9}, kind = .Crab}
	case 1017:
		e.count = 7
		for &spawn, i in e.spawns[:e.count] {
			spawn = {position = {-6, 0, 5}, kind = .Rabbit if i == 0 else (.Rabbit_Young if i < 3 else .Rabbit_Kit)}
		}
	case: return false
	}
	return true
}
