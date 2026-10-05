package tests

import "core:testing"
import "core:mem"
import game "../src/game"

@(test)
launcher_pickups_equip_once_and_rare_shells_break_a_heavy_enemy :: proc(t: ^testing.T) {
	w: game.World
	game.world_init_ram(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	guns, rounds := 0, 0
	for pickup in g.pickups[:g.pickup_count] {
		if pickup.kind == .Launcher { guns += 1; rounds += pickup.amount }
	}
	testing.expect(t, guns == 2 && rounds == 12, "Two launchers supply six shells each on Hard")
	flat_world(&g)
	g.pickup_count = 1
	g.pickups[0] = {1, {0.5, 0.75, 0}, .Fragments, 2, false}
	game.update_pickups(&g)
	testing.expect(t, !g.player.fragment_unlocked && g.player.fragment_ammo == 2 && g.player.weapon == .Repeater)
	g.pickups[0] = {2, {0.5, 0.75, 0}, .Launcher, 4, false}
	game.update_pickups(&g)
	testing.expect(t, g.player.fragment_unlocked && g.player.weapon == .Fragmentator && g.player.fragment_ammo == 6)
	g.player.weapon = .Repeater
	g.pickups[0] = {3, {0.5, 0.75, 0}, .Launcher, 4, false}
	game.update_pickups(&g)
	testing.expect(t, g.player.weapon == .Repeater && g.player.fragment_ammo == 10, "Later supplies must not change the selected weapon")
	g.player.position = {12, 0, 0}
	heavy, ok := game.spawn_enemy(&g, {0, game.enemy_extent(.Kettle).y+0.04, 0}, 28, 100, .Kettle)
	testing.expect(t, ok)
	game.explode_fragment(&g, {0, game.enemy_extent(.Kettle).y, -0.7})
	testing.expect(t, game.find_enemy(&g, heavy) == nil && g.kills == 1 && g.player.health == 100, "A close explosive hit must justify a scarce shell against a heavy")
}

@(test)
kick_opens_armour_once_and_sweeps_knockback_against_a_thin_wall :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	flat_world(&g)
	id, ok := game.spawn_enemy(&g, {0, game.enemy_extent(.Crab).y+0.03, -2.2}, 8, 100, .Crab)
	testing.expect(t, ok)
	e := game.find_enemy(&g, id)
	game.add_block(&w, {0, 2, -4}, {10, 4, 0.05})
	game.world_commit(&w)
	for step in 0..<15 { game.update_combat(&g, game.Input{kick_pressed = step < 2}, game.STEP) }
	testing.expect(t, e.health == 6 && game.crab_open(e^) && e.phase == .Recover)
	nearest := e.position.z
	for _ in 0..<60 { game.update_combat(&g, {}, game.STEP); nearest = min(nearest, e.position.z) }
	testing.expect(t, e.health == 6 && nearest < -2.6 && nearest >= -2.926, "A single kick shoves the crab but cannot push it through the wall")
	flat_world(&g)
	id, ok = game.spawn_enemy(&g, {0, game.enemy_extent(.Crab).y+0.03, -2.2}, 8, 100, .Crab)
	testing.expect(t, ok)
	game.add_block(&w, {0, 2, -1}, {10, 4, 0.05})
	game.world_commit(&w)
	for step in 0..<25 { game.update_combat(&g, game.Input{kick_pressed = step == 0}, game.STEP) }
	testing.expect_value(t, game.find_enemy(&g, id).health, 8)
}

@(test)
weapon_selection_ammo_and_saturated_pool_preserve_the_infinite_repeater :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	flat_world(&g)
	game.update_weapons(&g, game.Input{weapon_select = 2}, game.STEP)
	testing.expect_value(t, g.player.weapon, game.Weapon.Repeater)
	g.player.fragment_unlocked, g.player.fragment_ammo = true, 8
	for tick in 0..<144 { game.update_weapons(&g, game.Input{fire = true, weapon_select = 2 if tick == 0 else 0}, game.STEP) }
	testing.expect(t, g.player.weapon == .Fragmentator && g.player.fragment_ammo == 6 && g.shot_sequence == 0)
	for tick in 0..<24 { game.update_weapons(&g, game.Input{fire = true, weapon_select = 1 if tick == 0 else 0}, game.STEP) }
	testing.expect(t, g.shot_sequence > 0 && g.player.fragment_cooldown > 0, "The repeater becomes usable while the launcher is still recovering")
	for tick in 0..<24 { game.update_weapons(&g, game.Input{fire = true, weapon_select = 2 if tick == 0 else 0}, game.STEP) }
	testing.expect(t, g.player.fragment_ammo == 6, "Weapon toggling must not bypass the launcher cooldown")
	for &fragment in g.fragments { fragment.life = 10 }
	testing.expect(t, !game.fire_fragment(&g, false) && g.player.fragment_ammo == 6 && g.fragments_refused == 1)
	g.player.fragment_ammo = 0
	for tick in 0..<144 { game.update_weapons(&g, game.Input{fire = true, weapon_select = 1 if tick == 0 else 0}, game.STEP) }
	testing.expect(t, g.player.weapon == .Repeater && g.shot_sequence > 10 && g.player.fragment_ammo == 0)
}

@(test)
blast_cover_and_muzzle_clearance_block_damage_through_walls :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	flat_world(&g)
	protected, ok := game.spawn_enemy(&g, {0, 1.1, -5}, 100, 100, .Sentry)
	testing.expect(t, ok)
	open, spawned := game.spawn_enemy(&g, {2, 1.1, -1}, 100, 100, .Sentry)
	testing.expect(t, spawned)
	game.add_block(&w, {0, 3, -3}, {12, 6, 0.05})
	game.world_commit(&w)
	g.player.position = {10, 0, 0}
	game.explode_fragment(&g, {0, 1.1, -1.5})
	testing.expect_value(t, game.find_enemy(&g, protected).health, 100)
	testing.expect(t, game.find_enemy(&g, open).health < 100)
	// With the player flush against the wall the larger muzzle still starts
	// outside it. A high speed projectile must hit the front, never the far side.
	g.player.position = {0, 0, -2.60}
	g.player.fragment_unlocked, g.player.fragment_ammo = true, 2
	game.aim_at(&g, {0, 1.1, -5}, true)
	testing.expect(t, game.fire_fragment(&g, true))
	testing.expect(t, g.fragments[0].position.z > -2.835)
	g.fragments[0].velocity *= 40
	game.update_fragments(&g, game.STEP)
	testing.expect(t, g.fragments[0].life == 0 && g.fragments[0].position.z > -2.84)
	testing.expect_value(t, game.find_enemy(&g, protected).health, 100)
}

@(test)
fragment_jump_costs_health_and_cannot_break_the_ceiling :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	flat_world(&g)
	game.add_block(&w, {0, 4, 0}, {20, 0.1, 20})
	game.world_commit(&w)
	g.player.fragment_unlocked, g.player.fragment_ammo, g.player.weapon = true, 3, .Fragmentator
	game.aim_at(&g, {0, 0.04, -0.6}, true)
	maximum, peak_velocity := f32(0), f32(0)
	{
		context.allocator = mem.panic_allocator()
		context.temp_allocator = mem.panic_allocator()
		for tick in 0..<150 {
			game.update(&g, game.Input{fire = tick == 0, focus = true, jump_pressed = tick == 0}, game.STEP)
			maximum, peak_velocity = max(maximum, g.player.position.y), max(peak_velocity, g.player.velocity.y)
			cam := game.camera(&g)
			if abs(cam.position.x) < 10 && abs(cam.position.z) < 10 {
				testing.expectf(t, cam.position.y < 3.95, "Boost pushed the camera through the ceiling: %v", cam.position)
			}
		}
	}
	testing.expectf(t, peak_velocity > 18 && g.player.health < 100 && g.deaths == 0 && g.player.fragment_ammo == 2, "Boost did not reach the player: speed=%f health=%f ammo=%d", peak_velocity, g.player.health, g.player.fragment_ammo)
	testing.expectf(t, maximum+game.PLAYER_HEIGHT <= 3.951, "Blast broke the ceiling: feet=%f", maximum)
}
