package tests

import "core:testing"
import "core:mem"
import game "../src/game"

ai_corner_world :: proc(w: ^game.World) {
	r := game.sector_recipe(.RAM_Transfer)
	game.sector_room(&r, 301, .Junction, {0, 0, 0}, 12, 16, 6)
	game.sector_room(&r, 302, .Junction, {0, 0, -16}, 12, 16, 6)
	game.sector_room(&r, 303, .Junction, {16, 0, -16}, 20, 16, 6)
	game.sector_link(&r, 0, 1, {0, 0, -8})
	game.sector_link(&r, 1, 2, {6, 0, -16})
	r.entry, r.exit = {301, {0, 0.05, 4}}, {303, {6, 0, 0}}
	game.world_build_ram(w, r, 42)
}

@(test)
ground_roles_get_around_convex_cover_without_tracking_through_it :: proc(t: ^testing.T) {
	for kind in ([3]game.Enemy_Kind{.Crab, .Kettle, .Nanny}) {
		w: game.World
		ai_corner_world(&w)
		defer game.world_destroy(&w)
		game.add_block(&w, {0, 2, -15}, {3.2, 4, 4})
		game.world_commit(&w)
		g := game.State{world = &w}
		game.init(&g)
		g.player.position = {22, 0, -16}
		id, ok := game.spawn_enemy(&g, {0, game.enemy_extent(kind).y+0.03, 3}, 10, 100, kind)
		testing.expect(t, ok)
		e := game.find_enemy(&g, id)
		e.alerted, e.memory_time, e.last_known = true, 30, g.player.position+game.Vec3{0, 0.9, 0}
		for _ in 0..<2100 { game.update_enemies(&g, game.STEP); g.time += game.STEP }
		testing.expectf(t, e.position.x > 7 && e.position.z < -8, "%v stuck behind cover: %v", kind, e.position)
	}
}

@(test)
ground_enemy_follows_real_portals_around_a_blind_corner :: proc(t: ^testing.T) {
	w: game.World
	ai_corner_world(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	g.player.position = {19, 0, -16}
	id, ok := game.spawn_enemy(&g, {0, game.enemy_extent(.Crab).y+0.03, 3}, 8, 100, .Crab)
	testing.expect(t, ok)
	e := game.find_enemy(&g, id)
	e.alerted, e.memory_time, e.last_known = true, 30, g.player.position+game.Vec3{0, 0.9, 0}
	goal, found := game.enemy_route_goal(&w, e.position, e.last_known, e.kind)
	testing.expect(t, found && abs(goal.x) < 0.01 && goal.z < -8)
	{
		context.allocator = mem.panic_allocator()
		context.temp_allocator = mem.panic_allocator()
		for _ in 0..<1800 {
			game.update_enemies(&g, game.STEP)
			g.time += game.STEP
		}
	}
	testing.expectf(t, game.length(e.position-g.player.position) < 3.5, "Enemy did not clear the corner: %v", e.position)
	testing.expect(t, abs(e.position.y-game.enemy_extent(.Crab).y) < 0.04, "A ground enemy stays on the floor")
	// The eight metre fan opening is not a walking connection.
	game.world_init_ram(&w)
	_, found = game.enemy_route_goal(&w, w.checkpoints[4].position, w.checkpoints[5].position, .Crab)
	testing.expect(t, !found)
	_, found = game.enemy_route_goal(&w, w.checkpoints[4].position, w.checkpoints[5].position, .Sentry)
	testing.expect(t, found)
}

@(test)
enemy_loses_hidden_player_and_hears_a_nearby_shot :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	flat_world(&g)
	id, ok := game.spawn_enemy(&g, {0, 2, -12}, 10, 100)
	testing.expect(t, ok)
	e := game.find_enemy(&g, id)
	for _ in 0..<15 { game.update_enemies(&g, game.STEP) }
	testing.expect(t, e.sees_player)
	known := e.last_known
	game.add_block(&w, {0, 4, -2}, {200, 8, 0.25})
	game.world_commit(&w)
	g.player.position = {9, 0, 8}
	for _ in 0..<180 { game.update_enemies(&g, game.STEP) }
	testing.expect(t, !e.sees_player && e.last_known == known, "A hidden player must not update the enemy's target")
	for _ in 0..<1500 { game.update_enemies(&g, game.STEP) }
	testing.expect(t, !e.alerted)
	// A nearby weapon report is a separate source of information through a wall.
	e.position, e.anchor = {0, 2, -6}, {0, 2, -6}
	game.player_noise(&g, {0, 1, 0}, 32)
	for _ in 0..<15 { game.update_enemies(&g, game.STEP) }
	testing.expect(t, e.alerted && !e.sees_player && e.last_known == game.Vec3{0, 1, 0})
}

@(test)
crab_armour_flank_and_exposed_insert_change_actual_hits :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	flat_world(&g)
	e := &g.enemies[0]
	e^ = game.Enemy{kind = .Crab, position = {0, game.enemy_extent(.Crab).y+0.03, -8}, facing = {0, 0, 1}, health = 8}
	_, front := game.enemy_hit(e^, {0, game.enemy_extent(.Crab).y+0.03, 0}, {0, 0, -1}, 20)
	_, rear := game.enemy_hit(e^, {0, game.enemy_extent(.Crab).y+0.03, -16}, {0, 0, 1}, 20)
	testing.expect_value(t, front, game.Hit_Zone.Armour)
	testing.expect_value(t, rear, game.Hit_Zone.Body)
	_, flank := game.enemy_hit(e^, e.position+game.Vec3{8, 0, 8}, game.normalized(game.Vec3{-1, 0, -1}), 20)
	testing.expect(t, flank == .Body, "A ray missing the actual front plate must hit the visible flank")
	testing.expect_value(t, game.damage_enemy(&g, 0, 1, front, e.position), 0)
	testing.expect_value(t, e.health, 8)
	e.phase, e.phase_time = .Windup, 0.35
	point, _, exposed := game.enemy_weak_spot(e^)
	testing.expect(t, exposed)
	_, part := game.enemy_hit(e^, point+game.Vec3{0, 0, 8}, {0, 0, -1}, 20)
	testing.expect_value(t, part, game.Hit_Zone.Weak)
	testing.expect_value(t, game.damage_enemy(&g, 0, 1, part, point), 3)
	testing.expect(t, e.health == 5 && e.phase == .Recover, "Hitting the open insert interrupts the attack")
	// Rays through empty space above the body must not hit the old sphere.
	_, empty := game.enemy_hit(e^, {0, 2.2, 0}, {0, 0, -1}, 20)
	testing.expect_value(t, empty, game.Hit_Zone.None)
}
