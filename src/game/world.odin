package game

world_destroy :: proc(w: ^World) {
	delete(w.blocks)
	delete(w.decor_blocks)
	delete(w.decor_beams)
	delete(w.vents)
	delete(w.core_spawns)
	delete(w.enemy_spawns)
	delete(w.encounters)
	delete(w.lamps)
	delete(w.nodes)
	delete(w.block_order)
	w^ = {}
}

clear_blocks :: proc(w: ^World) {
	clear(&w.blocks)
	w.revision += 1
}

add_block :: proc(w: ^World, center, size: Vec3, style: int = 0) {
	append(&w.blocks, Block{center = center, size = size, style = style})
	w.revision += 1
}

set_block :: proc(w: ^World, index: int, block: Block) {
	w.blocks[index] = block
	w.revision += 1
}

world_init :: #force_no_inline proc(w: ^World, seed: u32 = DEFAULT_SEED) {
	w.kind = .Arena
	w.sector = {}
	w.room_navigation = {}
	w.gates, w.gate_count = {}, 0
	w.checkpoints, w.checkpoint_count = {}, 0
	w.pickup_spawns, w.pickup_count = {}, 0
	clear(&w.encounters)
	clear_blocks(w)
	clear(&w.vents)
	clear(&w.core_spawns)
	clear(&w.enemy_spawns)
	clear(&w.lamps)
	w.seed = seed
	w.spawn, w.exit = {0, 0.05, 16}, {0, 12, -39}
	add_block(w, {0, -1.5, 10}, {28, 3, 26})
	add_block(w, {18, 1.5, -2}, {14, 3, 16}, 1)
	add_block(w, {-18, 2.5, -5}, {14, 3, 18}, 1)
	add_block(w, {0, 4.5, -19}, {24, 3, 16}, 2)
	add_block(w, {0, 10.5, -39}, {16, 3, 12}, 2)
	// Intermediate stepping stones provide a route without the updrafts.
	add_block(w, {8, 1, -6}, {6, 2, 5})
	add_block(w, {-8, 1, -6}, {6, 2, 5})
	add_block(w, {14, 3.5, -14}, {5, 2, 6})
	add_block(w, {-13, 4.2, -16}, {5, 2, 5})
	add_block(w, {8, 6.75, -29}, {5, 2.5, 5}, 1)
	add_block(w, {5, 9, -33}, {4, 2, 4}, 1)
	// Cover and camera obstructions.
	add_block(w, {-5, 1.6, 8}, {3, 3.2, 3}, 3)
	add_block(w, {7, 1, 12}, {3, 2, 4}, 3)
	add_block(w, {1, 1.2, 1}, {4, 2.4, 2}, 3)
	add_block(w, {17, 4.2, -6}, {2, 2.4, 2}, 3)
	add_block(w, {-20, 5.2, -1}, {2, 2.4, 3}, 3)
	add_block(w, {-4, 7.4, -19}, {2.5, 2.8, 2.5}, 3)
	for &block in w.blocks[:] {
		corner := min(block.size.x, block.size.z)*0.12
		bevel_block(&block, min(corner, 1.4), 0.12 if block.style == 3 else 0.22)
	}
	add_tunnel(w)
	append(&w.vents, Vent{{-9, 0, 3}, 2.6, 11, false}, Vent{{17, 3, -8}, 2.4, 14, false}, Vent{{0, 6, -24}, 2.6, 21, false})
	append(&w.core_spawns, Vec3{21, 3.9, -1}, Vec3{-20, 4.9, -10}, Vec3{3, 6.9, -22})
	append(&w.enemy_spawns, Vec3{-7, 3.4, 0}, Vec3{8, 4.2, -3}, Vec3{22, 6.5, -8}, Vec3{-22, 7, -9}, Vec3{5, 9, -22}, Vec3{-5, 15, -37})
	append(&w.lamps, Vec3{-9, 5.08, 9}, Vec3{-9, 5.08, 15}, Vec3{0, 15.7, -39})
	build_decoration(w)
	world_commit(w)
}

// Reset simulation without rebuilding or allocating the level.
init :: #force_no_inline proc(g: ^State) {
	w, generation, campaign, difficulty, hero := g.world, g.next_enemy_generation, g.campaign, g.difficulty, g.hero
	assert(w != nil)
	g^ = State{world = w, next_enemy_generation = generation, campaign = campaign, difficulty = difficulty, hero = hero}
	if g.campaign.current == .None { g.campaign.seed = w.seed }
	g.campaign.current = w.sector.key
	g.rng = w.seed+0x76A593E1
	if g.rng == 0 { g.rng = 1 }
	g.effect_rng = w.seed+0xC3489A73
	if g.effect_rng == 0 { g.effect_rng = 1 }
	g.weapon_rng = w.seed+0x1BF013
	if g.weapon_rng == 0 { g.weapon_rng = 1 }
	g.checkpoint = w.spawn
	if w.sector.boss.id != 0 { g.boss = Boss_State{id = w.sector.boss.id, health = BOSS_HEALTH} }
	w.boss_exit_amount = 0
	for &gate in w.gates[:w.gate_count] { gate.open, gate.amount = false, 0 }
	g.player = Player{position = g.checkpoint, health = 100, pitch = -0.08}
	g.pickup_count = w.pickup_count
	for pickup, i in w.pickup_spawns[:w.pickup_count] {
		g.pickups[i] = pickup
		profile := difficulty_profile(g.difficulty)
		amount := profile.health_pickup if pickup.kind == .Health else profile.ammo_pickup
		if pickup.kind == .Fragments { amount = max(1, profile.ammo_pickup/2) }
		if pickup.kind == .Shotgun { amount = profile.ammo_pickup*2 }
		g.pickups[i].amount *= amount
	}
	assert(len(w.core_spawns) <= len(g.cores))
	g.core_count = len(w.core_spawns)
	for p, i in w.core_spawns { g.cores[i] = {p, false} }
	for p, i in w.enemy_spawns {
		_, ok := spawn_enemy(g, p, 3+difficulty_profile(g.difficulty).health_bonus, (1.8+f32(i)*0.3)*difficulty_profile(g.difficulty).cooldown, content_id = Object_ID(i+1))
		assert(ok, "Enemy capacity is too small for this level")
	}
	for &encounter, group in w.encounters {
		for spawn, i in encounter.spawns[:encounter.count] {
			profile := difficulty_profile(g.difficulty)
			kind := encounter_kind(w, encounter.room, i, spawn.kind, g.difficulty)
			id, ok := spawn_enemy(g, spawn.position, spawn.health+profile.health_bonus, (0.9+f32(i)*0.2)*profile.cooldown, kind, group+1, spawn.awareness, spawn.id)
			if ok && kind == .Rabbit { g.enemies[id.slot].facing = {1, 0, 0} }
			if ok && (kind == .Rabbit_Young || kind == .Rabbit_Kit) { g.enemies[id.slot].phase = .Dormant }
			assert(ok, "Enemy capacity is too small for this sector")
		}
	}
	g.message, g.message_time = 0 if w.kind == .RAM else 1, 0 if w.kind == .RAM else 8
	if w.sector.key == .RAM_Transfer { g.message_time = 0 }
	capture_checkpoint(g)
}

ground_height :: proc(g: ^State, position: Vec3) -> f32 {
	origin := position+Vec3{0, 0.1, 0}
	distance := world_ray(g, origin, {0, -1, 0}, 100)
	return origin.y-distance if distance < 100 else -100
}
