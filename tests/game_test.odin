package tests

import game "../src/game"
import "core:testing"
import "core:mem"
import "core:math"

reset_fixture :: proc(g: ^game.State) {
	game.world_init(g.world, g.world.seed)
	game.init(g)
}

flat_world :: proc(g: ^game.State) {
	reset_fixture(g)
	game.clear_blocks(g.world)
	game.add_block(g.world, {0, -1, 0}, {200, 2, 200})
	g.player.position = {0, 0, 0}
	g.player.grounded = true
	for &enemy in g.enemies[:g.enemy_count] { enemy.health = 0 }
	for &vent in g.world.vents { vent.position = {1000, 0, 1000} }
	g.checkpoint = g.player.position
	game.capture_checkpoint(g)
}

@(test)
grounding_and_wall_sweep :: proc(t: ^testing.T) {
	g_world: game.World
	game.world_init(&g_world, game.DEFAULT_SEED)
	defer game.world_destroy(&g_world)
	g := game.State{world = &g_world}
	flat_world(&g)
	game.add_block(g.world, {3, 2, 0}, {0.1, 4, 8})
	g.player.velocity = {100, -20, 0}
	game.move_player(&g, 0.1)
	testing.expect(t, g.player.position.x <= 2.95-game.PLAYER_RADIUS+0.001, "High speed movement must not tunnel through a thin wall")
	testing.expect(t, g.player.grounded && abs(g.player.position.y) < 0.001)
	testing.expect(t, g.player.velocity.x == 0 && g.player.velocity.y == 0)
}

@(test)
jump_glide_and_normalized_movement :: proc(t: ^testing.T) {
	g_world: game.World
	game.world_init(&g_world, game.DEFAULT_SEED)
	defer game.world_destroy(&g_world)
	g := game.State{world = &g_world}
	diagonal_world: game.World
	game.world_init(&diagonal_world, game.DEFAULT_SEED)
	defer game.world_destroy(&diagonal_world)
	diagonal := game.State{world = &diagonal_world}
	flat_world(&g)
	flat_world(&diagonal)
	for _ in 0..<240 {
		game.update_player(&g, game.Input{move = {0, 1}}, game.STEP)
		game.update_player(&diagonal, game.Input{move = {1, 1}}, game.STEP)
	}
	testing.expect(t, abs(game.length(g.player.velocity)-game.length(diagonal.player.velocity)) < 0.01, "Diagonal motion must not be faster")
	flat_world(&g)
	game.update_player(&g, game.Input{jump_pressed = true, jump_held = true}, game.STEP)
	apex := f32(0)
	for _ in 0..<85 {
		game.update_player(&g, game.Input{jump_held = true}, game.STEP)
		apex = max(apex, g.player.position.y)
	}
	testing.expect(t, apex > 2.16 && apex < 2.35, "A normal jump clears a two metre step with some margin")
	testing.expect(t, !g.player.gliding && g.player.grounded, "Holding the original jump must complete an ordinary jump")
	testing.expect_value(t, g.land_sequence, u32(1))
	g.player.position.y = 20
	g.player.grounded = false
	g.player.coyote = 0
	g.player.velocity.y = -30
	game.update_player(&g, {}, game.STEP)
	game.update_player(&g, game.Input{jump_pressed = true, jump_held = true}, game.STEP)
	testing.expect(t, g.player.gliding, "A fresh press in the air deploys the wing")
	game.update_player(&g, game.Input{jump_held = true}, game.STEP)
	testing.expect(t, g.player.velocity.y >= -2.81)
	game.update_player(&g, {}, game.STEP)
	testing.expect(t, !g.player.gliding && g.player.velocity.y < -2.81, "Releasing the wing resumes falling immediately")
}

@(test)
jump_buffer_and_coyote :: proc(t: ^testing.T) {
	g_world: game.World
	game.world_init(&g_world, game.DEFAULT_SEED)
	defer game.world_destroy(&g_world)
	g := game.State{world = &g_world}
	flat_world(&g)
	g.player.grounded = false
	g.player.coyote = 0.08
	game.update_player(&g, game.Input{jump_pressed = true}, game.STEP)
	testing.expect(t, g.player.velocity.y > 12, "Jump remains available just after leaving an edge")
	flat_world(&g)
	g.player.position.y = 0.1
	g.player.grounded = false
	g.player.velocity.y = -8
	game.update_player(&g, game.Input{jump_pressed = true}, game.STEP)
	for _ in 0..<5 { game.update_player(&g, {}, game.STEP) }
	testing.expect(t, g.player.velocity.y > 10 && g.jump_sequence == 1, "A press just before landing is retained")
}

@(test)
updraft_and_camera_collision :: proc(t: ^testing.T) {
	g_world: game.World
	game.world_init(&g_world, game.DEFAULT_SEED)
	defer game.world_destroy(&g_world)
	g := game.State{world = &g_world}
	flat_world(&g)
	g.world.vents[0] = {{0, 0, 0}, 3, 15, false}
	game.update_player(&g, game.Input{jump_pressed = true, jump_held = true}, game.STEP)
	for _ in 0..<10 { game.update_player(&g, {}, game.STEP) }
	game.update_player(&g, game.Input{jump_pressed = true, jump_held = true}, game.STEP)
	for _ in 0..<120 { game.update_player(&g, game.Input{jump_held = true}, game.STEP) }
	testing.expect(t, g.player.position.y > 10 && g.player.gliding, "The updraft must carry the player to the upper route")
	flat_world(&g)
	game.add_block(g.world, {0, 2, 3}, {8, 4, 0.4})
	cam := game.camera(&g)
	testing.expect(t, cam.position.z < 2.61, "The camera arm must stop before a wall")
	target := game.aim_point(&g, cam)
	game.change_focus(&g, false, true)
	game.change_focus(&g, true, false)
	cam = game.camera(&g)
	testing.expect(t, cam.position.z < 2.61, "Leaving the scope must respect the wall behind the player")
	testing.expect(t, game.dot(game.normalized(target-cam.position), cam.forward) > 0.99999, "A shortened camera arm must retain the aimed point")
}

@(test)
hitscan_stops_at_cover :: proc(t: ^testing.T) {
	g_world: game.World
	game.world_init(&g_world, game.DEFAULT_SEED)
	defer game.world_destroy(&g_world)
	g := game.State{world = &g_world}
	flat_world(&g)
	g.player.pitch = 0
	cam := game.camera(&g)
	e := cam.position+cam.forward*14
	g.enemies[0] = game.Enemy{position = e, anchor = e, health = 3}
	game.fire(&g, false)
	testing.expect_value(t, g.enemies[0].health, 2)
	game.add_block(g.world, {0, 2, -3}, {10, 4, 0.3})
	game.fire(&g, false)
	testing.expect_value(t, g.enemies[0].health, 2)
	testing.expect_value(t, g.shot_sequence, u32(2))
}

@(test)
elevated_view_and_first_person_scope :: proc(t: ^testing.T) {
	g_world: game.World
	game.world_init(&g_world, game.DEFAULT_SEED)
	defer game.world_destroy(&g_world)
	g := game.State{world = &g_world}
	flat_world(&g)
	g.player.pitch = -0.2
	cam := game.camera(&g)
	target := game.aim_point(&g, cam)
	testing.expect(t, cam.position.y > 3.3, "A raised view should not require steep downward aim")
	testing.expect(t, target.z < -12, "A comfortable downward view must reach ahead of the player's feet")
	testing.expect(t, abs(cam.position.x) < 0.15, "The character belongs almost on the reticle's horizontal axis")
	testing.expect(t, cam.position.z < 4.5, "The chase camera should keep the suit closer")
	game.change_focus(&g, false, true)
	scope := game.camera(&g, true)
	testing.expect_value(t, scope.position, g.player.position+game.Vec3{0, game.EYE_HEIGHT, 0})
	testing.expect(t, scope.scoped && scope.fov < cam.fov*0.5)
	testing.expect(t, game.dot(game.normalized(target-scope.position), scope.forward) > 0.99999, "Zoom must keep the point under the crosshair")
}

@(test)
scope_switch_preserves_targets :: proc(t: ^testing.T) {
	distances := [4]f32{6, 8, 22, 75}
	for distance in distances {
		g_world: game.World
		game.world_init(&g_world, game.DEFAULT_SEED)
		defer game.world_destroy(&g_world)
		g := game.State{world = &g_world}
		flat_world(&g)
		g.player.yaw = 0.4
		g.player.pitch = -0.02
		cam := game.camera(&g)
		g.enemies[0] = game.Enemy{position = cam.position+cam.forward*distance, health = 40}
		for i in 0..<20 {
			was_focused := i%2 != 0
			target := game.aim_point(&g, game.camera(&g, was_focused))
			game.change_focus(&g, was_focused, !was_focused)
			cam = game.camera(&g, !was_focused)
			testing.expectf(t, game.dot(game.normalized(target-cam.position), cam.forward) > 0.99999, "Scope switch moved the target at range %v", distance)
		}
		// Actual accuracy is tested separately: a spread shot may legitimately
		// miss a grazing point on the near surface while the camera stays aligned.
	}
}

@(test)
barrel_cannot_reach_through_cover :: proc(t: ^testing.T) {
	g_world: game.World
	game.world_init(&g_world, game.DEFAULT_SEED)
	defer game.world_destroy(&g_world)
	g := game.State{world = &g_world}
	flat_world(&g)
	g.player.pitch = 0
	cam := game.camera(&g)
	g.enemies[0] = game.Enemy{position = cam.position+cam.forward*16, health = 3}
	// The raised camera sees over this ledge, but the barrel would pass through it.
	game.add_block(g.world, {0, 0.8, -0.48}, {4, 1.6, 0.1})
	game.fire(&g, false)
	testing.expect_value(t, g.enemies[0].health, 3)
	testing.expect(t, g.traces[0].end.z >= -0.431, "Cover at the muzzle must stop the shot even when the camera has a clear view")
}

@(test)
automatic_fire_has_steady_cadence :: proc(t: ^testing.T) {
	g_world: game.World
	game.world_init(&g_world, game.DEFAULT_SEED)
	defer game.world_destroy(&g_world)
	g := game.State{world = &g_world}
	flat_world(&g)
	previous_shot := -5
	for i in 0..<240 {
		before := g.shot_sequence
		game.update_combat(&g, game.Input{fire = true, focus = i >= 90 && i < 150}, game.STEP)
		if g.shot_sequence != before {
			testing.expectf(t, i-previous_shot >= 4 && i-previous_shot <= 6, "Automatic fire stalled at tick %d", i)
			previous_shot = i
		}
	}
	testing.expectf(t, g.shot_sequence == 44, "Two seconds of held fire should produce 44 shots, got %d", g.shot_sequence)
	for _ in 0..<600 { game.update_combat(&g, {}, game.STEP) }
	testing.expect_value(t, g.shot_sequence, u32(44))
	game.update_combat(&g, game.Input{fire = true}, game.STEP)
	testing.expect(t, g.shot_sequence == 45, "Firing resumes immediately without storing an idle burst")
}

@(test)
movement_accelerates_and_brakes_promptly :: proc(t: ^testing.T) {
	g_world: game.World
	game.world_init(&g_world, game.DEFAULT_SEED)
	defer game.world_destroy(&g_world)
	g := game.State{world = &g_world}
	flat_world(&g)
	for _ in 0..<16 { game.update_player(&g, game.Input{move = {0, 1}}, game.STEP) }
	testing.expect(t, game.length(g.player.velocity) > 12, "Running reaches full speed within about 130 ms")
	for _ in 0..<16 { game.update_player(&g, {}, game.STEP) }
	testing.expect(t, game.length(g.player.velocity) < 0.01, "Releasing movement should brake promptly")
	for _ in 0..<60 { game.update_player(&g, game.Input{move = {0, 0.5}}, game.STEP) }
	testing.expect(t, abs(game.length(g.player.velocity)-game.RUN_SPEED*0.5) < 0.01, "Small movement inputs retain their magnitude")
}

@(test)
checkpoints_and_completion :: proc(t: ^testing.T) {
	g_world: game.World
	game.world_init(&g_world, game.DEFAULT_SEED)
	defer game.world_destroy(&g_world)
	g := game.State{world = &g_world}
	reset_fixture(&g)
	for &enemy in g.enemies[:g.enemy_count] { enemy.health = 0 }
	for i in 0..<g.core_count {
		g.player.position = g.cores[i].position-game.Vec3{0, 0.9, 0}
		g.player.velocity = {}
		game.update(&g, {}, game.STEP)
	}
	testing.expect_value(t, g.collected, g.core_count)
	checkpoint := g.checkpoint
	g.player.position.y = -100
	game.update(&g, {}, game.STEP)
	testing.expect(t, game.length(g.player.position-checkpoint) < 0.01)
	g.player.position = g.world.exit
	game.update(&g, {}, game.STEP)
	testing.expect(t, g.won)
}

@(test)
reproducible_allocation_free_simulation :: proc(t: ^testing.T) {
	a_world: game.World
	game.world_init(&a_world, game.DEFAULT_SEED)
	defer game.world_destroy(&a_world)
	a := game.State{world = &a_world}
	b_world: game.World
	game.world_init(&b_world, game.DEFAULT_SEED)
	defer game.world_destroy(&b_world)
	b := game.State{world = &b_world}
	reset_fixture(&a)
	reset_fixture(&b)
	shots := u32(0)
	{
		// Any accidental Odin heap allocation in the game loop now fails immediately.
		context.allocator = mem.panic_allocator()
		context.temp_allocator = mem.panic_allocator()
		for i in 0..<3600 {
			input := game.Input{
				move = {math.sin(f32(i)*0.01), 1},
				look = {math.sin(f32(i)*0.003), -0.05},
				has_look = true,
				jump_pressed = i%170 == 0,
				jump_held = i%240 < 200,
				fire = i%3 == 0,
				dash_pressed = i%300 == 0,
			}
			before := a.shot_sequence
			game.update(&a, input, game.STEP)
			game.update(&b, input, game.STEP)
			if a.shot_sequence > before { shots += a.shot_sequence-before }
		}
	}
	testing.expect_value(t, a.player.position, b.player.position)
	testing.expect_value(t, a.rng, b.rng)
	testing.expect_value(t, a.shot_sequence, b.shot_sequence)
	testing.expect(t, shots > 100)
}

// Exercise the actual movement controller across the complete authored route.
// No teleports, velocity overrides, or collision bypasses are used by this pilot.
fly_to :: proc(g: ^game.State, target: game.Vec3) -> bool {
	for _ in 0..<1800 {
		if g.won { return game.length(target-g.world.exit) < 0.1 }
		delta := target-g.player.position
		distance := math.sqrt(delta.x*delta.x+delta.z*delta.z)
		if distance < 0.65 && abs(delta.y) < 0.45 { return true }
		if distance > 0.15 { g.player.yaw = math.atan2(delta.x, -delta.z) }
		input := game.Input{
			move = {0, min(1, distance*0.22) if distance > 0.5 else 0},
			jump_pressed = g.player.grounded && (delta.y > 0.6 || distance > 3),
		}
		wants_wing := distance > 1.6 || delta.y > 0.5
		input.jump_held = input.jump_pressed || (g.player.gliding && wants_wing)
		if !g.player.grounded && !g.player.gliding && g.player.glide_ready && g.player.air_time > 0.09 && wants_wing {
			input.jump_pressed, input.jump_held = true, true
		}
		if !g.player.grounded && !g.player.gliding {
			// With preserved air momentum, actively countersteer to brake.
			forward := game.forward(g.player.yaw, 0)
			right := game.Vec3{math.cos(g.player.yaw), 0, math.sin(g.player.yaw)}
			desired := forward*min(game.RUN_SPEED, distance*2)
			steering := (desired-game.Vec3{g.player.velocity.x, 0, g.player.velocity.z})*0.2
			input.move = {game.dot(steering, right), game.dot(steering, forward)}
		}
		game.update(g, input, game.STEP)
		if g.deaths > 0 { return false }
	}
	return false
}

@(test)
arena_is_traversable :: proc(t: ^testing.T) {
	g_world: game.World
	game.world_init(&g_world, game.DEFAULT_SEED)
	defer game.world_destroy(&g_world)
	g := game.State{world = &g_world}
	reset_fixture(&g)
	for &enemy in g.enemies[:g.enemy_count] { enemy.health = 0 }
	route := []game.Vec3{
		{-9, 0, 21}, {-9, 0, 14}, {-9, 0, 3}, {-9, 10, 3},
		{-20, 4, -10}, {-13, 5.2, -16}, {3, 6, -22},
		{21, 3, -8}, {21, 3, -1},
		{17, 3, -8}, {17, 14, -8},
		{0, 6, -24}, {0, 18, -24}, {0, 12, -39},
	}
	for target, i in route {
		if !testing.expectf(t, fly_to(&g, target), "Route failed at waypoint %d: target=%v player=%v", i, target, g.player.position) { return }
	}
	testing.expect_value(t, g.collected, g.core_count)
	testing.expect(t, g.won)
	testing.expect_value(t, g.deaths, 0)
}
