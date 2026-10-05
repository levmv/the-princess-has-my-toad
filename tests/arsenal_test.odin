package tests

import "core:testing"
import "core:mem"
import game "../src/game"

@(test)
shotgun_stagger_cannot_shorten_a_weak_spot_interrupt :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	flat_world(&g)
	g.player.shotgun_unlocked, g.player.shotgun_ammo = true, 2
	id, ok := game.spawn_enemy(&g, {0, game.enemy_extent(.Crab).y+0.04, -8}, 1000, 100, .Crab)
	testing.expect(t, ok)
	e := &g.enemies[id.slot]
	e.phase, e.phase_time = .Windup, 0.3
	weak, _, _ := game.enemy_weak_spot(e^)
	game.aim_at(&g, weak, true)
	game.fire_shotgun(&g, true)
	testing.expect(t, e.health < 1000 && e.health > 0 && e.exposed == 0.9, "The central pellets must interrupt the exposed core")
	testing.expect(t, e.phase == .Recover && e.phase_time >= 0.9, "The ordinary 320 ms shotgun stagger must not replace a longer critical-hit recovery")
	e.phase_time = 0.7
	game.fire_shotgun(&g, true)
	testing.expect(t, e.phase == .Recover && e.phase_time >= 0.7, "Another shot must not accelerate recovery")
}

@(test)
shotgun_gibs_a_close_fairy_and_sweeps_debris_against_cover :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	flat_world(&g)
	game.add_block(&w, {0, 15, -8}, {40, 30, 0.05})
	game.world_commit(&w)
	id, ok := game.spawn_enemy(&g, {0, 1.5, -5}, 12, 100, .Sentry)
	testing.expect(t, ok)
	g.player.shotgun_unlocked, g.player.shotgun_ammo = true, 3
	game.aim_at(&g, g.enemies[id.slot].position, false)
	{
		context.allocator, context.temp_allocator = mem.panic_allocator(), mem.panic_allocator()
		testing.expect(t, game.fire_shotgun(&g, false))
	}
	e := &g.enemies[id.slot]
	testing.expectf(t, e.health <= 0 && e.gibbed && e.velocity.z < -12, "Close blast failed: health=%d gibbed=%t velocity=%v", e.health, e.gibbed, e.velocity)
	testing.expect(t, g.kills == 1 && g.player.shotgun_ammo == 2 && g.gib_cursor == 12)
	for _ in 0..<360 {
		game.update_enemy_death(&g, e, game.STEP)
		game.update_gibs(&g, game.STEP)
		for p in g.gibs[:12] {
			if !testing.expectf(t, p.life > 0 && p.position.z > -7.98 && p.position.y >= 0, "Gib passed through a thin wall or floor: %v", p) { return }
		}
	}
	// Sparks and a second explosion never replace the bounded debris pool.
	game.emit(&g, {}, 600, 0)
	for p in g.gibs[:12] { testing.expect(t, p.life > 0) }
}

@(test)
shotgun_respects_cover_armour_and_finite_support_shields :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	flat_world(&g)
	g.player.shotgun_unlocked, g.player.shotgun_ammo = true, 3
	id, _ := game.spawn_enemy(&g, {0, 1.5, -5}, 100, 100, .Sentry)
	game.add_block(&w, {0, 3, -2}, {40, 6, 0.04})
	game.world_commit(&w)
	game.aim_at(&g, g.enemies[id.slot].position, true)
	game.fire_shotgun(&g, true)
	testing.expect_value(t, g.enemies[id.slot].health, 100)
	flat_world(&g)
	victim, _ := game.spawn_enemy(&g, {0, 1.5, -5}, 100, 100, .Sentry)
	support, _ := game.spawn_enemy(&g, {4, 1.5, -5}, 100, 100, .Nanny)
	nanny := &g.enemies[support.slot]
	nanny.phase, nanny.shield, nanny.support = .Attack, 6, victim
	testing.expect_value(t, game.damage_enemy(&g, int(victim.slot), 20, .Body, g.enemies[victim.slot].position), 14)
	testing.expect(t, nanny.shield == 0 && g.enemies[victim.slot].health == 86)
	testing.expect_value(t, game.damage_enemy(&g, int(victim.slot), 20, .Armour, g.enemies[victim.slot].position), 0)
}

@(test)
shotgun_supplies_selection_and_cooldown_survive_weapon_toggling :: proc(t: ^testing.T) {
	w: game.World
	game.world_init_ram(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	guns := 0
	for p in g.pickups[:g.pickup_count] { if p.kind == .Shotgun { guns += 1 } }
	testing.expect_value(t, guns, 2)
	flat_world(&g)
	game.update_weapons(&g, {weapon_select = 3}, game.STEP)
	testing.expect_value(t, g.player.weapon, game.Weapon.Repeater)
	g.pickup_count = 1
	g.pickups[0] = {1, {0, 0.7, 0}, .Shotgun, 12, false}
	game.update_pickups(&g)
	testing.expect(t, g.player.shotgun_unlocked && g.player.shotgun_ammo == 12 && g.player.weapon == .Shotgun)
	testing.expect_value(t, game.cycle_weapon(&g.player, 1), 1)
	g.player.weapon = .Repeater
	testing.expect_value(t, game.cycle_weapon(&g.player, 1), 3)
	g.player.fragment_unlocked = true
	testing.expect_value(t, game.cycle_weapon(&g.player, 1), 3)
	testing.expect_value(t, game.cycle_weapon(&g.player, -1), 2)
	g.player.weapon = .Shotgun
	testing.expect_value(t, game.cycle_weapon(&g.player, 1), 2)
	g.player.weapon = .Repeater
	for _ in 0..<240 { game.update_weapons(&g, {fire = true, weapon_select = 3}, game.STEP) }
	testing.expect_value(t, g.player.shotgun_ammo, 9)
	for tick in 0..<48 { game.update_weapons(&g, {fire = true, weapon_select = 1 if tick < 24 else 3}, game.STEP) }
	testing.expect(t, g.player.shotgun_ammo == 9 && g.shot_sequence > 0)
	g.player.shotgun_ammo = 0
	testing.expect(t, !game.fire_shotgun(&g, true))
	for _ in 0..<60 { game.update_weapons(&g, {fire = true, weapon_select = 1}, game.STEP) }
	testing.expect(t, g.player.weapon == .Repeater && g.shot_sequence > 5)
}

@(test)
launcher_shell_reaches_a_distant_target_without_a_rainbow_arc :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	flat_world(&g)
	g.player.position = {0, 12, 0}
	g.player.fragment_unlocked, g.player.fragment_ammo = true, 2
	game.aim_at(&g, {0, 13.28, -60}, true)
	testing.expect(t, game.fire_fragment(&g, true))
	for _ in 0..<120 { game.update_fragments(&g, game.STEP) }
	f := g.fragments[0]
	testing.expectf(t, f.life > 0 && f.position.z < -53 && f.position.y > 10, "Shell falls short: %v", f.position)
}

@(test)
shotgun_and_gibs_save_and_continue_deterministically :: proc(t: ^testing.T) {
	w, other: game.World
	game.world_init_ram(&w)
	game.world_init(&other)
	defer game.world_destroy(&w)
	defer game.world_destroy(&other)
	a, b := game.State{world = &w}, game.State{world = &other}
	game.init(&a); game.init(&b)
	a.player.shotgun_unlocked, a.player.shotgun_ammo, a.player.shotgun_cooldown, a.player.weapon = true, 11, 0.6, .Shotgun
	game.damage_enemy(&a, 0, 100, .Body, a.enemies[0].position, true, true)
	data, decoded: game.Save_Data
	bytes: [game.SAVE_LIMIT]u8
	testing.expect_value(t, game.save_capture(&data, &a, .Quick, 1), game.Save_Error.None)
	n, err := game.save_encode(&data, bytes[:])
	testing.expect_value(t, err, game.Save_Error.None)
	testing.expect_value(t, game.save_decode(bytes[:n], &decoded), game.Save_Error.None)
	testing.expect_value(t, game.save_restore(&b, &decoded), game.Save_Error.None)
	saved_equal(t, &a, &b)
	for _ in 0..<240 { game.update(&a, {}, game.STEP); game.update(&b, {}, game.STEP) }
	saved_equal(t, &a, &b)
}

@(test)
combat_feedback_matches_material_death_and_actual_pickup :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	flat_world(&g)
	id, _ := game.spawn_enemy(&g, {0, 1.5, -5}, 20, 100, .Sentry)
	game.damage_enemy(&g, int(id.slot), 1, .Body, g.enemies[id.slot].position)
	testing.expect_value(t, g.sound_events[(g.sound_sequence-1)%128].cue, game.Sound_Cue.FleshHit)
	game.damage_enemy(&g, int(id.slot), 1, .Armour, g.enemies[id.slot].position)
	testing.expect_value(t, g.sound_events[(g.sound_sequence-1)%128].cue, game.Sound_Cue.Ricochet)
	game.damage_enemy(&g, int(id.slot), 100, .Body, g.enemies[id.slot].position)
	testing.expect_value(t, g.sound_events[(g.sound_sequence-1)%128].cue, game.Sound_Cue.FaeDeath)
	flat_world(&g)
	id, _ = game.spawn_enemy(&g, {0, 1.5, -5}, 6, 100, .Sentry)
	g.player.shotgun_unlocked, g.player.shotgun_ammo = true, 3
	game.aim_at(&g, g.enemies[id.slot].position, false)
	game.fire_shotgun(&g, false)
	gib := false
	for event in g.sound_events {
		if event.sequence == 0 { continue }
		testing.expect(t, event.cue != .FaeDeath, "A dismembered fairy cannot play its ordinary death scream")
		if event.cue == .GibImpact { gib = true }
	}
	testing.expect(t, gib)
	flat_world(&g)
	g.pickup_count = 1
	g.pickups[0] = {1, {0, 0.7, 0}, .Shotgun, 6, false}
	game.update_pickups(&g)
	testing.expect_value(t, g.sound_events[(g.sound_sequence-1)%128].cue, game.Sound_Cue.EquipShotgun)
	before := g.sound_sequence
	game.update_pickups(&g)
	game.update_weapons(&g, {weapon_select = 3}, game.STEP)
	testing.expect_value(t, g.sound_sequence, before)
	game.update_weapons(&g, {weapon_select = 1}, game.STEP)
	testing.expect_value(t, g.sound_events[(g.sound_sequence-1)%128].cue, game.Sound_Cue.EquipRepeater)
	g.pickups[0] = {2, {0, 0.7, 0}, .Shells, 6, false}
	game.update_pickups(&g)
	testing.expect_value(t, g.sound_events[(g.sound_sequence-1)%128].cue, game.Sound_Cue.AmmoPickup)
	g.player.shotgun_ammo = game.SHOTGUN_AMMO_MAX
	g.pickups[0].collected = false
	before = g.sound_sequence
	game.update_pickups(&g)
	testing.expect(t, !g.pickups[0].collected && g.sound_sequence == before, "A full inventory leaves ammo and emits no pickup")
}
