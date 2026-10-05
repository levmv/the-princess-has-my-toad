package tests

import game "../src/game"
import "core:testing"

@(test)
air_momentum_and_deliberate_glide :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	flat_world(&g)
	for _ in 0..<30 { game.update_player(&g, {move = {0, 1}}, game.STEP) }
	game.update_player(&g, {jump_pressed = true, jump_held = true}, game.STEP)
	for _ in 0..<30 { game.update_player(&g, {jump_held = true}, game.STEP) }
	testing.expect(t, abs(g.player.velocity.z+game.RUN_SPEED) < 0.01, "Airborne release preserves forward momentum")
	testing.expect(t, !g.player.gliding && g.glide_sequence == 0, "Holding takeoff does not accidentally glide")
	for _ in 0..<12 { game.update_player(&g, {move = {1, 0}, jump_held = true}, game.STEP) }
	testing.expect(t, g.player.velocity.x > 2, "The player can steer in the air")
	testing.expect(t, game.length(game.Vec3{g.player.velocity.x, 0, g.player.velocity.z}) <= game.RUN_SPEED+0.01, "Air steering does not amplify diagonal speed")
	game.update_player(&g, {}, game.STEP)
	game.update_player(&g, {jump_pressed = true, jump_held = true}, game.STEP)
	testing.expect(t, g.player.gliding && g.glide_sequence == 1, "Release and press deploys immediately in the air")
	for _ in 0..<10 { game.update_player(&g, {jump_held = true}, game.STEP) }
	testing.expect_value(t, g.glide_sequence, u32(1))
}

@(test)
landing_buffer_and_contact_feedback :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	flat_world(&g)
	g.player.position.y = 0.1
	g.player.grounded, g.player.glide_ready = false, true
	g.player.velocity.y = -12
	game.update_player(&g, {jump_pressed = true, jump_held = true}, game.STEP)
	for _ in 0..<5 { game.update_player(&g, {jump_held = true}, game.STEP) }
	testing.expect(t, g.jump_sequence == 1 && !g.player.gliding, "A press just above the floor buffers a jump instead of preventing landing")
	testing.expect_value(t, g.land_sequence, u32(1))
	flat_world(&g)
	game.add_block(&w, {0, 2, -1}, {20, 4, 0.1})
	for _ in 0..<240 { game.update_player(&g, {move = {0, 1}}, game.STEP) }
	testing.expect(t, g.step_sequence == 0, "Pushing into a wall must not produce a running cadence")
	flat_world(&g)
	for _ in 0..<120 { game.update_player(&g, {move = {0, 1}}, game.STEP) }
	testing.expect(t, g.step_sequence >= 4 && g.step_sequence <= 5, "Footsteps follow travelled distance")
	for _ in 0..<60 { game.update_player(&g, {}, game.STEP) }
	steps := g.step_sequence
	for _ in 0..<120 { game.update_player(&g, {}, game.STEP) }
	testing.expect(t, g.step_sequence == steps, "Standing still is silent")
}

@(test)
glide_landing_and_animation_interpolation :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	flat_world(&g)
	g.player.position.y = 0.03
	g.player.grounded = false
	g.player.gliding = true
	g.player.velocity.y = -2.8
	for _ in 0..<6 { game.update_player(&g, {jump_held = true}, game.STEP) }
	testing.expect(t, g.player.grounded && !g.player.gliding && g.land_sequence == 1, "A glider landing has a single soft contact event")
	testing.expect(t, g.player.land_strength < 0.2)
	flat_world(&g)
	g.player.gait_phase = 6.26
	h: game.Pose_History
	game.capture_poses(&h, &g)
	g.player.gait_phase = 0.02
	v: game.Render_Snapshot
	game.render_snapshot(&v, &g, &h, 0.5)
	testing.expect(t, v.player.gait_phase > 6.26 && v.player.gait_phase < 6.31, "Gait interpolation follows the short path across its wrap")
}

@(test)
backing_up_the_first_bridge_with_fragment_blast_stays_above_the_ramp :: proc(t: ^testing.T) {
	w: game.World
	game.world_init_ram(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	g.enemy_count = 0
	// Reproduced on the rise into 05. Diagonal retreat used to accumulate
	// enough inward rounding to make the next downward blast skip the solid.
	g.player.position = {85.25769, -2.8763614, -119.7723}
	g.player.yaw, g.player.pitch = 6.111013, 0.69052935
	g.player.grounded, g.player.invulnerable = true, 1000
	g.player.fragment_unlocked, g.player.fragment_ammo = true, 4
	extent := game.Vec3{game.PLAYER_RADIUS, game.PLAYER_HEIGHT*0.5, game.PLAYER_RADIUS}
	testing.expect(t, game.world_clear_box(&w, g.player.position+game.Vec3{0, extent.y, 0}, extent))
	for tick in 0..<186 {
		game.update_player(&g, {move = {0.6130513, -1}, focus = true}, game.STEP)
		if tick%96 == 20 { game.fire_fragment(&g, true) }
		game.update_fragments(&g, game.STEP)
	}
	testing.expectf(t, game.world_clear_box(&w, g.player.position+game.Vec3{0, extent.y, 0}, extent), "Retreat drifted into the bridge: %v", g.player.position)
	game.explode_fragment(&g, g.player.position+game.Vec3{0, 3, 2})
	testing.expect(t, g.player.velocity.y < -5 && !g.player.grounded, "The regression must apply a real downward blast")
	for _ in 0..<20 { game.update_player(&g, {}, game.STEP) }
	floor := (g.player.position.x-100)*0.2
	testing.expectf(t, g.player.position.y >= floor && g.player.grounded, "Blast passed through the bridge: %v, ramp height %v", g.player.position, floor)
	testing.expect(t, game.world_clear_box(&w, g.player.position+game.Vec3{0, extent.y, 0}, extent))
}
