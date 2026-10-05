package game

GENERATOR_VERSION :: u32(17)

// Geometry, game intent and authored anchors are separate pieces of the recipe.
// Connections name persistent room IDs; storage order has no gameplay meaning.
Region :: enum { RAM, HDD, Bus, CPU }
Section_Role :: enum { Bank, Bus_Passage, Service_Passage, Junction, Capacitor_Court, Air_Lift, Combat_Bay, Stair_Hall, Memory_Gallery, Capacitor_Garden, Branch_Landing, Address_Bridge, Switching_Hall, GC_Chamber, Fracture_Span, Launch_Terrace, Charge_Causeway, Receiver_Terrace }
Room_Variant :: enum u8 { Authored = 0, Auto = 1, Weave = 2, Split = 3 }
Population :: enum { None, Sparse_Sentries, Passage_Hunters, Mixed_Patrol, Crossfire }
Door_Side :: enum { North, South, West, East }
Portal :: struct { side: Door_Side, offset, width, bottom, height: f32 }
Section_Recipe :: struct {
	id: Room_ID,
	intent: Room_Intent,
	role: Section_Role,
	origin: Vec3,
	width, depth, height: f32,
	population: Population,
	variant: Room_Variant,
	open_roof: bool,
	doors: [4]Portal,
	door_count: int,
}
Connection :: struct { a, b: Room_ID, position: Vec3, width, height: f32 }
Sector_Recipe :: struct {
	key: Sector_ID,
	id, title: string,
	region: Region,
	generator_version: u32,
	entry, exit: Location_Def,
	exit_rule: Exit_Rule,
	mechanism: Mechanism_Kind,
	mechanism_room: Room_ID,
	boss: Boss_Def,
	checkpoints: [SECTOR_CHECKPOINT_CAPACITY]Checkpoint_Def,
	checkpoint_count: int,
	pickups: [PICKUP_CAPACITY]Pickup_Def,
	pickup_count: int,
	gates: [GATE_CAPACITY]Gate_Def,
	gate_count: int,
	sections: [SECTOR_ROOM_CAPACITY]Section_Recipe,
	count: int,
	connections: [SECTOR_LINK_CAPACITY]Connection,
	connection_count: int,
}

sector_room :: proc(r: ^Sector_Recipe, id: Room_ID, role: Section_Role, origin: Vec3, width, depth, height: f32, population: Population = .None, open_roof: bool = false, intent: Room_Intent = .Transit) {
	assert(r.count < len(r.sections))
	assert(id != 0 && room_index(r, id) < 0, "Room IDs must be unique and nonzero")
	r.sections[r.count] = {id = id, intent = intent, role = role, origin = origin, width = width, depth = depth, height = height, population = population, open_roof = open_roof}
	r.count += 1
}

sector_link :: proc(r: ^Sector_Recipe, a, b: int, position: Vec3, width: f32 = 6, height: f32 = 4.8) {
	assert(a >= 0 && b >= 0 && a < r.count && b < r.count)
	first, second := &r.sections[a], &r.sections[b]
	delta := second.origin-first.origin
	x_axis := abs(delta.x) > abs(delta.z)
	opening_height := min(height, min(first.origin.y+first.height, second.origin.y+second.height)-position.y-0.15)
	for end in 0..<2 {
		room := first if end == 0 else second
		direction := delta if end == 0 else -delta
		side := (Door_Side.East if direction.x > 0 else Door_Side.West) if x_axis else (Door_Side.South if direction.z > 0 else Door_Side.North)
		offset := position.z-room.origin.z if x_axis else position.x-room.origin.x
		span := room.depth if x_axis else room.width
		bottom := position.y-room.origin.y
		assert(room.door_count < len(room.doors) && abs(offset)+width*0.5 <= span*0.5 && bottom >= 0 && opening_height >= PLAYER_HEIGHT+0.5)
		room.doors[room.door_count] = {side, offset, width, bottom, opening_height}
		room.door_count += 1
	}
	assert(r.connection_count < len(r.connections))
	r.connections[r.connection_count] = {first.id, second.id, position, width, opening_height}
	r.connection_count += 1
}

// Authored connections use IDs so removing a passage cannot silently rewire the map.
sector_connect :: proc(r: ^Sector_Recipe, a, b: Room_ID, position: Vec3, width: f32 = 6, height: f32 = 4.8) {
	sector_link(r, room_index(r, a), room_index(r, b), position, width, height)
}

ram_cold_boot :: proc() -> Sector_Recipe {
	r := sector_recipe(.RAM_Bank_01)
	sector_room(&r, 1001, .Service_Passage, {0, 0, 0}, 22, 36, 5, .Passage_Hunters) // 0 low arrival
	sector_room(&r, 1002, .Memory_Gallery, {0, 0, -57}, 32, 78, 10, .Crossfire)  // 1 lanes between enormous chips
	sector_room(&r, 1003, .Junction, {0, 0, -114}, 32, 36, 8)                    // 2 blind corner
	sector_room(&r, 1004, .Fracture_Span, {58, -10, -114}, 84, 32, 30, .Passage_Hunters, true, .Traversal)
	sector_room(&r, 1005, .Capacitor_Garden, {126, 0, -114}, 52, 52, 18, .Mixed_Patrol, true)
	sector_room(&r, 1006, .Branch_Landing, {126, 0, -164}, 36, 48, 14)           // ramp into the aerial route
	sector_room(&r, 1010, .Launch_Terrace, {180, 0, -164}, 72, 28, 30, .Sparse_Sentries, true, .Traversal)
	sector_room(&r, 1011, .Charge_Causeway, {254, -18, -206}, 76, 100, 50, .Sparse_Sentries, true, .Traversal)
	sector_room(&r, 1012, .Receiver_Terrace, {180, 0, -248}, 72, 28, 20, .Passage_Hunters, true)
	sector_room(&r, 1013, .Junction, {126, 0, -248}, 36, 40, 13)                 // aerial route returns indoors
	sector_room(&r, 1014, .Service_Passage, {126, 0, -310}, 18, 84, 7.5, .Passage_Hunters)
	sector_room(&r, 1015, .Switching_Hall, {126, 0, -378}, 68, 52, 15, .Mixed_Patrol)
	sector_room(&r, 1016, .Service_Passage, {54, 0, -378}, 76, 12, 6, .Sparse_Sentries)
	sector_room(&r, 1017, .Air_Lift, {0, 0, -378}, 32, 36, 20, .Mixed_Patrol) // optional rabbit fight below the shot-controlled lift
	sector_room(&r, 1018, .Memory_Gallery, {0, 8, -438}, 36, 84, 12, .Mixed_Patrol)
	sector_room(&r, 1019, .Service_Passage, {0, 8, -516}, 12, 72, 6, .Passage_Hunters)
	sector_room(&r, 1020, .GC_Chamber, {0, 8, -580}, 60, 56, 16, open_roof = true)
	sector_room(&r, 1021, .Junction, {-28, 0, -124}, 24, 16, 5.5, intent = .Secret)
	sector_room(&r, 1022, .Junction, {26, 8, -438}, 16, 16, 6, intent = .Secret)
	sector_connect(&r, 1001, 1002, {0, 0, -18}, 8)
	sector_connect(&r, 1002, 1003, {0, 0, -96}, 8)
	sector_connect(&r, 1003, 1004, {16, 0, -114})
	sector_connect(&r, 1004, 1005, {100, 0, -114})
	sector_connect(&r, 1005, 1006, {126, 0, -140}, 8)
	sector_connect(&r, 1006, 1010, {144, 6, -164}, 8)
	sector_connect(&r, 1010, 1011, {216, 16, -164}, 8, 7)
	sector_connect(&r, 1011, 1012, {216, 6, -248}, 8)
	sector_connect(&r, 1012, 1013, {144, 6, -248}, 8)
	sector_connect(&r, 1013, 1014, {126, 0, -268}, 9)
	sector_connect(&r, 1014, 1015, {126, 0, -352})
	sector_connect(&r, 1015, 1016, {92, 0, -378})
	sector_connect(&r, 1016, 1017, {16, 0, -378})
	sector_connect(&r, 1017, 1018, {0, 8, -396}, 8, 7)
	sector_connect(&r, 1018, 1019, {0, 8, -480})
	sector_connect(&r, 1019, 1020, {0, 8, -552}, 8)
	sector_connect(&r, 1003, 1021, {-16, 0, -123}, 3, 3)
	sector_connect(&r, 1018, 1022, {18, 8, -438}, 3, 3)
	r.gates[0] = {room_object_id(1021, 0x600), 1003, 1021, {1003, {-15.25, 1.3, -5}}}
	r.gate_count = 1
	r.entry, r.exit = {1001, {0, 0.05, 12}}, {1020, {0, 0.05, -25}}
	r.boss = {room_object_id(1020, 0x700), {1020, {0, 0, -7}}}
	r.mechanism, r.mechanism_room, r.exit_rule = .Shot_Lift, 1017, .Reach
	r.sections[room_index(&r, 1001)].intent = .Arrival
	for id in ([3]Room_ID{1002, 1005, 1015}) { r.sections[room_index(&r, id)].intent = .Combat }
	r.sections[room_index(&r, 1003)].intent = .Ambush
	r.sections[room_index(&r, 1017)].intent, r.sections[room_index(&r, 1018)].intent, r.sections[room_index(&r, 1020)].intent = .Traversal, .Traversal, .Finale
	r.checkpoints[0] = {room_object_id(1003, 0x300), {1003, {0, 0.05, 8}}, 4}
	r.checkpoints[1] = {room_object_id(1006, 0x300), {1006, {0, 0.05, 19}}, 5.5}
	r.checkpoints[2] = {room_object_id(1010, 0x300), {1010, {30, 16.05, 0}}, 12}
	r.checkpoints[3] = {room_object_id(1013, 0x300), {1013, {0, 0.05, -15}}, 6}
	r.checkpoints[4] = {room_object_id(1017, 0x300), {1017, {13, 0.05, 0}}, 6}
	r.checkpoints[5] = {room_object_id(1018, 0x300), {1018, {0, 0.05, 39}}, 5}
	r.checkpoints[6] = {room_object_id(1020, 0x300), {1020, {0, 0.05, 21}}, 5}
	r.checkpoint_count = 7
	// The same doorway contracts admit two different internal layouts. No
	// retries are necessary: each selected form has validated clear lanes.
	for &s in r.sections[:r.count] {
		if s.role == .Memory_Gallery || (s.role == .Service_Passage && s.id != 1001) { s.variant = .Auto }
	}
	// Keep service runs direct; only galleries vary their internal combat lanes.
	for id in ([3]Room_ID{1014, 1016, 1019}) { r.sections[room_index(&r, id)].variant = .Authored }
	for id in ([1]Room_ID{1018}) { r.sections[room_index(&r, id)].variant = .Split }
	sector_pickup(&r, 1001, 0x400, {-2, 0.6, -10}, .Health)
	sector_pickup(&r, 1003, 0x400, {2, 0.6, 0}, .Health)
	// An optional supply fight below the first crossing; offsets are world axes.
	sector_pickup(&r, 1004, 0x400, {25, 0.6, -3}, .Health)
	sector_pickup(&r, 1004, 0x402, {23, 0.6, 3}, .Shells)
	sector_pickup(&r, 1005, 0x400, {0, 6.1, 18}, .Launcher)
	sector_pickup(&r, 1006, 0x400, {11, 0.6, -12.5}, .Health)
	sector_pickup(&r, 1006, 0x401, {15, 0.6, -17}, .Health)
	sector_pickup(&r, 1011, 0x400, {22.5, 28.6, -10.5}, .Health)
	sector_pickup(&r, 1011, 0x402, {22.5, 28.6, -7.5}, .Shells)
	sector_pickup(&r, 1013, 0x400, {0, 0.6, 3}, .Health)
	sector_pickup(&r, 1015, 0x400, {-21, 4.6, -2}, .Health)
	sector_pickup(&r, 1017, 0x400, {9, 0.6, 0}, .Health)
	sector_pickup(&r, 1018, 0x400, {0, 0.6, 38}, .Launcher)
	sector_pickup(&r, 1020, 0x400, {0, 0.6, 17}, .Health)
	sector_pickup(&r, 1021, 0x400, {-6, 0.6, 0}, .Fragments)
	sector_pickup(&r, 1021, 0x401, {-6, 0.6, 3}, .Health)
	sector_pickup(&r, 1022, 0x400, {4, 0.6, -3}, .Fragments)
	sector_pickup(&r, 1003, 0x402, {8, 0.7, 0}, .Shotgun)
	sector_pickup(&r, 1006, 0x402, {2, 0.6, 8}, .Shells)
	sector_pickup(&r, 1013, 0x402, {0, 0.7, -6}, .Shotgun)
	sector_pickup(&r, 1015, 0x402, {-21, 4.6, -2}, .Shells)
	sector_pickup(&r, 1021, 0x402, {-6, 0.6, -3}, .Shells)
	return r
}

sector_recipe :: proc(key: Sector_ID) -> Sector_Recipe {
	def := sector_definition(key)
	assert(key != .None)
	return Sector_Recipe{key = key, id = def.path, title = def.title, region = def.region, generator_version = GENERATOR_VERSION}
}

ram_transfer :: proc() -> Sector_Recipe {
	r := sector_recipe(.RAM_Transfer)
	sector_room(&r, 2001, .Junction, {0, 0, 0}, 18, 20, 6, intent = .Arrival)
	sector_room(&r, 2002, .Service_Passage, {0, 0, -22}, 10, 24, 5)
	sector_room(&r, 2003, .Junction, {0, 0, -42}, 18, 16, 8, intent = .Finale)
	sector_link(&r, 0, 1, {0, 0, -10})
	sector_link(&r, 1, 2, {0, 0, -34})
	r.entry, r.exit = {2001, {0, 0.05, 4}}, {2003, {0, 0, -3}}
	return r
}

world_load_sector :: proc(w: ^World, key: Sector_ID, seed: u32 = DEFAULT_SEED) {
	switch key {
	case .RAM_Bank_01: world_build_ram(w, ram_cold_boot(), seed)
	case .RAM_Transfer: world_build_ram(w, ram_transfer(), seed)
	case .RAM_Combat_Lab: world_build_ram(w, ram_combat_lab(), seed)
	case .None: world_init(w, seed)
	}
}

ram_combat_lab :: proc() -> Sector_Recipe {
	r := sector_recipe(.RAM_Combat_Lab)
	sector_room(&r, 3001, .Service_Passage, {0, 0, 0}, 12, 20, 5, intent = .Arrival)
	sector_room(&r, 3002, .Combat_Bay, {0, 0, -22}, 20, 24, 7, .Crossfire, intent = .Combat)
	sector_room(&r, 3003, .Service_Passage, {18, 0, -27}, 16, 6, 4.5, .Passage_Hunters, intent = .Ambush)
	sector_room(&r, 3004, .Capacitor_Court, {44, 0, -27}, 36, 36, 10, .Mixed_Patrol, true, .Combat)
	sector_room(&r, 3005, .Stair_Hall, {44, 0, -63}, 24, 36, 10, .Crossfire, intent = .Traversal)
	sector_link(&r, 0, 1, {0, 0, -10}, 5)
	sector_link(&r, 1, 2, {10, 0, -27}, 4.5, 3.7)
	sector_link(&r, 2, 3, {26, 0, -27}, 4.5, 3.7)
	sector_link(&r, 3, 4, {44, 0, -45}, 6)
	r.entry, r.exit = {3001, {0, 0.05, 5}}, {3005, {0, 3.6, -13}}
	r.checkpoints[0] = {room_object_id(3004, 0x300), {3004, {-13, 0.05, 0}}, 4}
	r.checkpoint_count = 1
	sector_pickup(&r, 3001, 0x400, {0, 0.6, -5}, .Launcher)
	sector_pickup(&r, 3002, 0x400, {8, 0.6, 0}, .Health)
	sector_pickup(&r, 3004, 0x400, {0, 0.6, 0}, .Fragments)
	sector_pickup(&r, 3004, 0x401, {0, 0.6, -9}, .Health)
	sector_pickup(&r, 3001, 0x402, {2, 0.7, -5}, .Shotgun)
	return r
}
