package tests

import "core:testing"
import "core:mem"
import game "../src/game"

@(test)
kettle_commits_to_floor_marker_and_cannot_leap_through_a_wall :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	for wall in 0..<2 {
		flat_world(&g)
		id, ok := game.spawn_enemy(&g, {0, game.enemy_extent(.Kettle).y+0.03, -8}, 7, 0, .Kettle)
		testing.expect(t, ok)
		e := game.find_enemy(&g, id)
		for _ in 0..<4 { game.update_enemies(&g, game.STEP) }
		testing.expect_value(t, e.phase, game.Enemy_Phase.Windup)
		for e.phase_time > 0.23 { game.update_enemies(&g, game.STEP) }
		marked := e.attack_target
		testing.expect(t, abs(marked.y-0.04) < 0.01 && abs(marked.x) < 0.01 && abs(marked.z) < 0.1)
		g.player.position.x = 9
		if wall == 1 { game.add_block(&w, {0, 4, -4}, {12, 8, 0.08}); game.world_commit(&w) }
		for _ in 0..<260 {
			game.update_combat(&g, {}, game.STEP)
			if e.phase == .Recover { break }
		}
		testing.expect(t, e.attack_target == marked && e.phase == .Recover)
		testing.expect(t, g.hazards[0].life > 0, "Landing leaves a temporary hazard on the actual floor")
		testing.expect(t, abs(e.position.y-game.enemy_extent(.Kettle).y) < 0.04)
		if wall == 1 {
			testing.expect(t, e.position.z < -4.7 && g.hazards[0].position.z < -4.7)
		} else { testing.expect(t, abs(g.hazards[0].position.z) < 0.7 && abs(g.hazards[0].position.x) < 0.01) }
		testing.expect_value(t, g.player.health, f32(100))
	}
}

@(test)
hot_floor_has_warning_height_cover_and_pool_limits :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	flat_world(&g)
	testing.expect(t, game.spawn_floor_hazard(&g, {0, 0.04, 0}, 2.8))
	for _ in 0..<18 { game.update_floor_hazards(&g, game.STEP) }
	testing.expect_value(t, g.player.health, f32(100))
	for _ in 0..<12 { game.update_floor_hazards(&g, game.STEP) }
	testing.expect_value(t, g.player.health, f32(88))
	g.player.health, g.player.invulnerable, g.player.position.y = 100, 0, 2
	for _ in 0..<80 { game.update_floor_hazards(&g, game.STEP) }
	testing.expect_value(t, g.player.health, f32(100))
	g.player.position = {2, 0, 0}
	game.add_block(&w, {1, 1, 0}, {0.1, 2, 8})
	game.world_commit(&w)
	for _ in 0..<80 { game.update_floor_hazards(&g, game.STEP) }
	testing.expect_value(t, g.player.health, f32(100))
	for _ in 1..<len(g.hazards) { testing.expect(t, game.spawn_floor_hazard(&g, {0, 0.04, 0}, 2.8)) }
	testing.expect(t, !game.spawn_floor_hazard(&g, {}, 2.8) && g.hazards_refused == 1)
	{
		context.allocator = mem.panic_allocator()
		context.temp_allocator = mem.panic_allocator()
		for _ in 0..<500 { game.update_floor_hazards(&g, game.STEP) }
	}
	for h in g.hazards { testing.expect(t, h.life == 0) }
}

support_fixture :: proc(g: ^game.State) -> (game.Enemy_ID, game.Enemy_ID) {
	flat_world(g)
	ally, ok := game.spawn_enemy(g, {0, 2, -8}, 20, 100, .Sentry)
	assert(ok)
	nanny, spawned := game.spawn_enemy(g, {3, game.enemy_extent(.Nanny).y+0.03, -10}, 6, 0, .Nanny)
	assert(spawned)
	g.enemies[ally.slot].alerted = true
	return ally, nanny
}

@(test)
nanny_visible_link_matches_the_actual_shield_range_and_cover :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	ally, nanny := support_fixture(&g)
	support, victim := &g.enemies[nanny.slot], &g.enemies[ally.slot]
	h: game.Pose_History
	v: game.Render_Snapshot
	for distance, i in ([4]f32{12, 15, 17, 15}) {
		support.position = victim.position+game.Vec3{distance, 0, 0}
		support.phase, support.phase_time, support.shield, support.support = .Attack, 2, 6, ally
		if i == 3 { game.add_block(&w, {7.5, 3, -8}, {0.1, 6, 10}); game.world_commit(&w) }
		game.capture_poses(&h, &g)
		game.render_snapshot(&v, &g, &h, 1)
		protected := i < 2
		testing.expectf(t, v.enemies[nanny.slot].shielding == protected, "Shield visibility at distance %f (cover=%t)", distance, i == 3)
		dealt := game.damage_enemy(&g, int(ally.slot), 1, .Body, victim.position)
		testing.expect_value(t, dealt, 0 if protected else 1)
	}
}

@(test)
aimed_base_weapon_cancels_the_kettle_leap_at_its_valve :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	flat_world(&g)
	id, ok := game.spawn_enemy(&g, {0, game.enemy_extent(.Kettle).y+0.03, -9}, 7, 0, .Kettle)
	testing.expect(t, ok)
	e := game.find_enemy(&g, id)
	for _ in 0..<4 { game.update_enemies(&g, game.STEP) }
	testing.expect_value(t, e.phase, game.Enemy_Phase.Windup)
	valve, _, _ := game.enemy_weak_spot(e^)
	game.aim_at(&g, valve, true)
	game.fire(&g, true)
	testing.expect(t, e.health == 4 && e.phase == .Recover, "The visible valve must be hittable with the real scoped weapon")
	e.fire_timer = 100
	for _ in 0..<240 { game.update_combat(&g, {}, game.STEP) }
	for h in g.hazards { testing.expect(t, h.life == 0, "An interrupted jump must not leave invisible hot floor") }
}

@(test)
nanny_shield_can_be_broken_interrupted_and_occluded :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	ally, nanny := support_fixture(&g)
	for _ in 0..<150 { game.update_enemies(&g, game.STEP) }
	support, victim := game.find_enemy(&g, nanny), game.find_enemy(&g, ally)
	testing.expect(t, support.phase == .Attack && support.support == ally && support.shield == 6)
	for _ in 0..<6 { testing.expect_value(t, game.damage_enemy(&g, int(ally.slot), 1, .Body, victim.position), 0) }
	testing.expect_value(t, game.damage_enemy(&g, int(ally.slot), 1, .Body, victim.position), 1)
	testing.expect_value(t, victim.health, 19)
	support.shield = 6
	testing.expect_value(t, game.damage_enemy(&g, int(ally.slot), 1, .Weak, victim.position), 3)
	point, _, exposed := game.enemy_weak_spot(support^)
	_, zone := game.enemy_hit(support^, point+game.Vec3{0, 0, 8}, {0, 0, -1}, 20)
	testing.expect(t, exposed && zone == .Weak)
	game.damage_enemy(&g, int(nanny.slot), 1, zone, point)
	testing.expect(t, support.phase == .Recover && support.shield == 0)

	ally, nanny = support_fixture(&g)
	support, victim = game.find_enemy(&g, nanny), game.find_enemy(&g, ally)
	support.phase, support.phase_time, support.shield, support.support = .Attack, 2, 6, ally
	game.add_block(&w, {1.5, 3, -9}, {0.12, 6, 10})
	game.world_commit(&w)
	testing.expect_value(t, game.damage_enemy(&g, int(ally.slot), 1, .Body, victim.position), 1)
	game.update_enemies(&g, game.STEP)
	testing.expect(t, support.phase == .Recover && support.shield == 0, "A physical obstruction breaks the support channel")
	// Reusing the ally's slot must not transfer the old shield to a new actor.
	game.clear_blocks(&w)
	game.world_commit(&w)
	victim.health = 0
	replacement, ok := game.spawn_enemy(&g, victim.position, 10)
	testing.expect(t, ok && replacement.slot == ally.slot && replacement.generation != ally.generation)
	support.phase, support.phase_time, support.shield, support.support = .Attack, 2, 6, ally
	testing.expect_value(t, game.damage_enemy(&g, int(replacement.slot), 1, .Body, victim.position), 1)
}
