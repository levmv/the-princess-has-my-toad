package tests

import game "../src/game"
import "core:testing"
import "core:mem"

saved_equal :: proc(t: ^testing.T, a, b: ^game.State) {
	x, y: game.Save_Data
	xb, yb: [game.SAVE_LIMIT]u8
	testing.expect_value(t, game.save_capture(&x, a, .Quick, 900), game.Save_Error.None)
	testing.expect_value(t, game.save_capture(&y, b, .Quick, 900), game.Save_Error.None)
	nx, ex := game.save_encode(&x, xb[:])
	ny, ey := game.save_encode(&y, yb[:])
	testing.expect_value(t, ex, game.Save_Error.None)
	testing.expect_value(t, ey, game.Save_Error.None)
	testing.expect(t, nx == ny && string(xb[:nx]) == string(yb[:ny]), "Encoded continuations must retain all gameplay RNG, timers, references and effects")
}

@(test)
save_airborne_battle_restores_exactly_and_continues_deterministically :: proc(t: ^testing.T) {
	w, loaded: game.World
	game.world_init_ram(&w, 42)
	game.world_init(&loaded, 1)
	defer game.world_destroy(&w)
	defer game.world_destroy(&loaded)
	a := game.State{world = &w, difficulty = .Brutal}
	b := game.State{world = &loaded}
	game.init(&a); game.init(&b)
	a.player.position = {126, 0.02, -100}
	a.player.fragment_unlocked, a.player.fragment_ammo = true, 10
	game.mission_checkpoint(&a, 1, w.checkpoints[0].position)
	for i in 0..<120 {
		game.update(&a, {fire = true, jump_pressed = i == 95, jump_held = i >= 95, weapon_select = 2 if i > 100 else 1}, game.STEP)
	}
	game.change_focus(&a, false, true)
	testing.expect(t, !a.player.grounded && a.player.position.y > 1)
	w.gates[0].open, w.gates[0].amount = true, 0.43
	data, decoded: game.Save_Data
	buffer: [game.SAVE_LIMIT]u8
	testing.expect_value(t, game.save_capture(&data, &a, .Quick, 123456789), game.Save_Error.None)
	size, err := game.save_encode(&data, buffer[:])
	testing.expect_value(t, err, game.Save_Error.None)
	testing.expect(t, size > 1000 && size < game.SAVE_LIMIT)
	testing.expect_value(t, game.save_decode(buffer[:size], &decoded), game.Save_Error.None)
	old_revision := loaded.revision
	testing.expect_value(t, game.save_restore(&b, &decoded), game.Save_Error.None)
	testing.expect(t, b.world == &loaded && loaded.revision > old_revision && loaded.index_revision == loaded.revision)
	testing.expect_value(t, decoded.stamp, u64(123456789))
	testing.expect_value(t, loaded.gates[0].amount, f32(0.43))
	testing.expect(t, b.focused)
	saved_equal(t, &a, &b)
	for i in 0..<600 {
		input := game.Input{fire = i%2 == 0, move = {1, 0.3}, look = {f32(i)*0.013, -0.05}, has_look = true, jump_pressed = i%110 == 0, jump_held = i%110 < 30}
		game.update(&a, input, game.STEP); game.update(&b, input, game.STEP)
	}
	saved_equal(t, &a, &b)
	// Disk loading retains the checkpoint that existed before the manual save.
	game.respawn(&a); game.respawn(&b)
	saved_equal(t, &a, &b)
	testing.expect_value(t, b.player.position, w.checkpoints[0].position)
}

@(test)
save_same_sector_preserves_static_cache_but_changed_seed_rebuilds_it :: proc(t: ^testing.T) {
	w: game.World
	game.world_init_ram(&w, 42)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	data: game.Save_Data
	game.save_capture(&data, &g, .Quick, 1)
	revision, blocks := w.revision, raw_data(w.blocks)
	w.gates[0].open, w.gates[0].amount = true, 1
	testing.expect_value(t, game.save_restore(&g, &data), game.Save_Error.None)
	testing.expect(t, w.revision == revision && raw_data(w.blocks) == blocks && !w.gates[0].open)
	game.world_init_ram(&w, 0)
	game.init(&g)
	different_revision := w.revision
	testing.expect_value(t, game.save_restore(&g, &data), game.Save_Error.None)
	testing.expect(t, w.seed == 42 && w.revision > different_revision && w.index_revision == w.revision)
}

@(test)
solving_a_mechanism_and_dying_in_one_tick_keeps_the_solution :: proc(t: ^testing.T) {
	w: game.World
	game.world_init_ram(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	g.player.health = 31
	game.mission_checkpoint(&g, 4, w.checkpoints[3].position)
	g.player.position = w.checkpoints[4].position
	g.mission_checkpoint = 5
	game.aim_at(&g, w.lift.button, true)
	g.player.health, g.player.invulnerable = 1, 0
	g.projectiles[0] = {g.player.position+game.Vec3{0, 0.8, 0}, {}, 1, .Fairy}
	game.update(&g, {fire = true, focus = true}, game.STEP)
	testing.expect(t, g.deaths == 1 && g.lift_started && g.restart.run.lift_started)
	testing.expect(t, g.player.health == 65 && g.player.position == w.checkpoints[3].position)
}

@(test)
checkpoint_rolls_back_combat_and_rewards_without_losing_committed_mechanisms :: proc(t: ^testing.T) {
	w: game.World
	game.world_init_ram(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	g.player.health, g.player.fragment_ammo, g.player.fragment_unlocked = 31, 4, true
	game.capture_checkpoint(&g)
	g.player.fragment_ammo = 0
	g.enemies[0].health = 0
	g.kills += 1
	g.pickups[0].collected = true
	g.player.position = {0, -40, 0}
	{
		context.allocator, context.temp_allocator = mem.panic_allocator(), mem.panic_allocator()
		game.update(&g, {}, game.STEP)
	}
	testing.expect(t, g.deaths == 1 && g.player.health == 65 && g.player.fragment_ammo == 4)
	testing.expect(t, g.enemies[0].health > 0 && g.kills == 0 && !g.pickups[0].collected)
	g.lift_started = true
	g.pickups[0].collected = true
	g.player.fragment_ammo = 8
	w.gates[0].open, w.gates[0].amount = true, 0.2
	g.secrets[0], g.secret_count = game.room_object_id(1021, 0x500), 1
	game.checkpoint_changed(&g)
	g.player.fragment_ammo = 2
	game.respawn(&g)
	testing.expect(t, g.deaths == 2 && g.lift_started && w.gates[0].open && w.gates[0].amount == 1)
	testing.expect(t, g.secret_count == 1 && g.pickups[0].collected && g.player.fragment_ammo == 8)
}

@(test)
checkpoint_and_respawn_clear_transient_pose_and_weapon_state :: proc(t: ^testing.T) {
	w: game.World
	g := game.State{world = &w, checkpoint = {4, 2, 8}, focused = true}
	g.player = {position = {1, 4, 3}, health = 30, yaw = 1, pitch = 0.3, velocity = {1, 4, 3}, recoil = 1, land_time = 0.5, scope_time = 7, shotgun_cooldown = 0.8, dash_cooldown = 1, in_current = true, weapon = .Shotgun, shotgun_unlocked = true, shotgun_ammo = 7, fragment_unlocked = true, fragment_ammo = 3}
	game.capture_checkpoint(&g)
	for saved in ([2]bool{true, false}) {
		if !saved { game.respawn(&g) }
		p := &g.restart.run.player if saved else &g.player
		testing.expect(t, p.position == g.checkpoint && p.velocity == game.Vec3{} && p.health == 65 && p.invulnerable >= 1.25)
		testing.expect(t, p.recoil == 0 && p.land_time == 0 && p.scope_time == 0 && !p.in_current, "A checkpoint must not replay a shot, landing or glide pose")
		testing.expect(t, p.shotgun_cooldown == 0 && p.dash_cooldown == 0, "All weapons and movement restart ready")
		testing.expect(t, p.yaw == 1 && p.pitch == 0.3 && p.weapon == .Shotgun && p.shotgun_unlocked && p.shotgun_ammo == 7 && p.fragment_unlocked && p.fragment_ammo == 3, "Keep the chosen weapon, ammunition and view direction")
	}
}

@(test)
save_rejects_damage_versions_unknown_ids_and_duplicate_ids_transactionally :: proc(t: ^testing.T) {
	w: game.World
	game.world_init_ram(&w, 0)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	data, decoded: game.Save_Data
	buffer: [game.SAVE_LIMIT]u8
	game.save_capture(&data, &g, .Quick, 1)
	size, err := game.save_encode(&data, buffer[:])
	testing.expect_value(t, err, game.Save_Error.None)
	decoded.stamp = 777
	for n in 0..<size/100 {
		testing.expect(t, game.save_decode(buffer[:n*100], &decoded) != .None)
		testing.expect_value(t, decoded.stamp, u64(777))
	}
	buffer[size-7] ~= 0x40
	testing.expect_value(t, game.save_decode(buffer[:size], &decoded), game.Save_Error.Checksum)
	buffer[size-7] ~= 0x40
	buffer[4] = 100
	testing.expect_value(t, game.save_decode(buffer[:size], &decoded), game.Save_Error.Version)
	buffer[4] = u8(game.SAVE_VERSION-1)
	testing.expect_value(t, game.save_decode(buffer[:size], &decoded), game.Save_Error.Version)
	buffer[4] = u8(game.SAVE_VERSION)
	revision, position, health := w.revision, g.player.position, g.enemies[0].health
	data.generator += 1
	testing.expect_value(t, game.save_restore(&g, &data), game.Save_Error.Generator)
	data.generator -= 1
	data.generator -= 1
	testing.expect_value(t, game.save_restore(&g, &data), game.Save_Error.Generator)
	data.generator += 1
	data.variants[1].id = data.variants[0].id
	testing.expect_value(t, game.save_restore(&g, &data), game.Save_Error.Content)
	game.save_capture(&data, &g, .Quick, 1)
	data.live.state.enemies[1].content_id = data.live.state.enemies[0].content_id
	testing.expect_value(t, game.save_restore(&g, &data), game.Save_Error.Content)
	game.save_capture(&data, &g, .Quick, 1)
	data.live.state.pickups[0].id = 0x12345678
	testing.expect_value(t, game.save_restore(&g, &data), game.Save_Error.Content)
	testing.expect(t, w.revision == revision && g.player.position == position && g.enemies[0].health == health)
	data.live.state.player.velocity.x = transmute(f32)u32(0x7fc00000)
	_, invalid := game.save_encode(&data, buffer[:])
	testing.expect_value(t, invalid, game.Save_Error.Value)
	data.live.state.enemy_count = game.ENEMY_CAPACITY+1
	_, overflow := game.save_encode(&data, buffer[:])
	testing.expect_value(t, overflow, game.Save_Error.Value)
}

@(test)
save_support_references_use_content_ids_when_actor_storage_order_changes :: proc(t: ^testing.T) {
	w: game.World
	game.world_init_ram(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	nanny := -1
	for e, i in g.enemies[:g.enemy_count] { if e.kind == .Nanny { nanny = i; break } }
	testing.expect(t, nanny >= 0)
	g.enemies[nanny].support = {0, g.enemies[0].generation}
	g.enemies[nanny].support_time, g.enemies[nanny].shield = 1.7, 4
	data: game.Save_Data
	game.save_capture(&data, &g, .Quick, 1)
	r := &data.live
	r.state.enemies[0], r.state.enemies[1] = r.state.enemies[1], r.state.enemies[0]
	r.encounter_rooms[0], r.encounter_rooms[1] = r.encounter_rooms[1], r.encounter_rooms[0]
	r.support_targets[0], r.support_targets[1] = r.support_targets[1], r.support_targets[0]
	testing.expect_value(t, game.save_restore(&g, &data), game.Save_Error.None)
	support := game.find_enemy(&g, g.enemies[nanny].support)
	testing.expect(t, support != nil && support.content_id == r.support_targets[nanny])
	testing.expect(t, g.enemies[nanny].support.slot == 1 && g.enemies[nanny].shield == 4)
}

@(test)
save_completion_and_sector_transition_keep_inventory_and_campaign :: proc(t: ^testing.T) {
	w: game.World
	game.world_init_ram(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	g.player.fragment_unlocked, g.player.fragment_ammo = true, 7
	// This fixture starts after the separately exercised boss encounter.
	g.boss.phase, g.boss.health, g.boss.stage = .Dead, 0, 2
	g.lift_started, g.player.position = true, w.exit
	game.update(&g, {}, game.STEP)
	testing.expect(t, g.won)
	data: game.Save_Data
	game.save_capture(&data, &g, .Checkpoint, 2)
	testing.expect_value(t, game.save_restore(&g, &data), game.Save_Error.None)
	testing.expect(t, game.advance_campaign(&g) && g.player.fragment_ammo == 7)
	game.save_capture(&data, &g, .Quick, 3)
	testing.expect_value(t, game.save_restore(&g, &data), game.Save_Error.None)
	testing.expect(t, w.sector.key == .RAM_Transfer && g.campaign.completed == 2 && g.player.fragment_ammo == 7)
}
