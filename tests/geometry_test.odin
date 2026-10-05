package tests

import "core:math"
import "core:testing"
import game "../src/game"

@(test)
slightly_embedded_sweep_blocks_inward_motion_but_allows_escape :: proc(t: ^testing.T) {
	w: game.World
	defer game.world_destroy(&w)
	game.ram_ramp(&w, {85, -3, -114}, {100, 0, -114}, 12)
	game.world_commit(&w)
	extent := game.Vec3{game.PLAYER_RADIUS, game.PLAYER_HEIGHT*0.5, game.PLAYER_RADIUS}
	// Exercise save/rounding recovery independently of movement's slope bias.
	feet := game.Vec3{95, -1+game.PLAYER_RADIUS*0.2-0.0002, -114}
	center := feet+game.Vec3{0, extent.y, 0}
	fraction, normal := game.world_sweep(&w, center, {0, -0.5, 0}, extent)
	testing.expect(t, fraction == 0 && normal.y > 0.9, "An embedded start cannot turn the ramp into a one-way floor")
	away, _ := game.world_sweep(&w, center, {0, 0.5, 0}, extent)
	testing.expect(t, away == 1, "Movement back out of the solid remains possible")
}

@(test)
coplanar_floor_seams_do_not_catch_a_walking_player :: proc(t: ^testing.T) {
	w: game.World
	defer game.world_destroy(&w)
	for i in 0..<8 { game.add_block(&w, {0, -1, -200-f32(i)*6}, {12, 2, 6}) }
	game.world_commit(&w)
	g := game.State{world = &w}
	g.player.position, g.player.health, g.player.grounded = {0, 0.000004, -200}, 100, true
	for _ in 0..<1700 { game.update_player(&g, game.Input{move = {0, 0.25}}, game.STEP) }
	testing.expectf(t, g.player.position.z < -240 && g.player.position.y > -0.001, "Adjacent floor slabs catch a slow walk at %v", g.player.position)
}

@(test)
beveled_corners_do_not_leave_invisible_boxes :: proc(t: ^testing.T) {
	g_world: game.World
	game.world_init(&g_world, game.DEFAULT_SEED)
	defer game.world_destroy(&g_world)
	g := game.State{world = &g_world}
	game.clear_blocks(g.world)
	game.add_block(g.world, {0, 0.5, 0}, {4, 1, 4})
	game.bevel_block(&g.world.blocks[0], 1, 0.2)
	_, hit := game.ray_box({1.95, 3, 1.95}, {0, -1, 0}, g.world.blocks[0], 5)
	testing.expect(t, !hit, "Shots must pass through the removed corner")
	distance, center_hit := game.ray_box({0, 3, 0}, {0, -1, 0}, g.world.blocks[0], 5)
	testing.expect(t, center_hit && abs(distance-2) < 0.001)
	g.player.position = {1.95, 1.5, 1.95}
	g.player.velocity = {0, -10, 0}
	game.move_player(&g, 0.2)
	testing.expect(t, !g.player.grounded && g.player.position.y < 0, "The cut corner cannot support an invisible floor")
	g.player.position = {0, 1.5, 0}
	g.player.velocity = {0, -100, 0}
	game.move_player(&g, 0.1)
	testing.expect(t, g.player.grounded && abs(g.player.position.y-1) < 0.001, "The actual deck must catch a fast fall")
}

@(test)
slopes_tunnel_floor_and_ceiling_have_collision :: proc(t: ^testing.T) {
	g_world: game.World
	game.world_init(&g_world, game.DEFAULT_SEED)
	defer game.world_destroy(&g_world)
	g := game.State{world = &g_world}
	flat_world(&g)
	ramp := [4]game.Vec2{{2, -0.2}, {8, -0.2}, {8, 2}, {2, 0}}
	game.add_prism(g.world, ramp[:], 3, -3, 4)
	g.player.yaw = math.PI*0.5
	highest := f32(0)
	for _ in 0..<100 {
		game.update_player(&g, game.Input{move = {0, 1}}, game.STEP)
		highest = max(highest, g.player.position.y)
	}
	testing.expectf(t, highest > 1.8 && g.player.position.x > 8, "Movement should climb and cross a slope without jumping: highest=%v position=%v", highest, g.player.position)
	reset_fixture(&g)
	g.player.position = {game.TUNNEL_X, 0, 20.5}
	g.player.yaw = 0
	for _ in 0..<140 { game.update_player(&g, game.Input{move = {0, 1}}, game.STEP) }
	testing.expect(t, g.player.position.z < 7 && g.player.position.y < 0.01, "The centre of the passage is walkable from end to end")
	g.player.position = {game.TUNNEL_X, 3.5, 12}
	g.player.velocity = {0, 20, 0}
	game.move_player(&g, 0.2)
	testing.expect(t, g.player.position.y+game.PLAYER_HEIGHT < 5.451 && g.player.velocity.y == 0, "The visible faceted ceiling must stop an upward jump")
	left_edge := game.ground_height(&g, {game.TUNNEL_X-2.5, 2, 12})
	centre := game.ground_height(&g, {game.TUNNEL_X, 2, 12})
	testing.expect(t, left_edge > 0.35 && abs(centre) < 0.001, "The floor rises gently towards its sides")
}

@(test)
explosions_create_lights_that_expire :: proc(t: ^testing.T) {
	g_world: game.World
	game.world_init(&g_world, game.DEFAULT_SEED)
	defer game.world_destroy(&g_world)
	g := game.State{world = &g_world}
	flat_world(&g)
	g.player.pitch = 0
	cam := game.camera(&g)
	g.enemies[0] = game.Enemy{position = cam.position+cam.forward*14, health = 3}
	for _ in 0..<3 { game.fire(&g, false) }
	testing.expect_value(t, g.kills, 1)
	explosion_found := false
	for flash in g.flashes {
		if flash.life > 0 && flash.radius >= 8 && flash.color.x > flash.color.y { explosion_found = true }
	}
	testing.expect(t, explosion_found, "Destroying an enemy should light its surroundings")
	for _ in 0..<90 { game.update(&g, {}, game.STEP) }
	for flash in g.flashes { testing.expect(t, flash.life == 0, "Temporary lighting must decay back to the normal scene") }
}
