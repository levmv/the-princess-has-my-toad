package tests

import "core:testing"
import "core:mem"
import "core:math"
import game "../src/game"

boss_fixture :: proc(g: ^game.State, w: ^game.World, difficulty: game.Difficulty = .Hard) {
	game.world_init_ram(w)
	g^ = game.State{world = w, difficulty = difficulty}
	game.init(g)
	for &e in g.enemies { e.health, e.phase = 0, .Recover }
	g.lift_started = true
	g.player.position = game.boss_room_origin(w)+game.Vec3{0, 0.05, 21}
	game.update(g, {}, game.STEP)
}

boss_command :: proc(g: ^game.State) -> game.Input {
	b := g.boss
	c := game.boss_room_origin(g.world)
	p := g.player.position-c
	goal := game.Vec3{6*math.sin(g.time*1.8), 0, 12}
	if b.phase == .Mark || b.phase == .Sweep {
		lane := b.lanes[b.pass]
		x_axis := lane.a.x != lane.b.x
		coordinate := lane.a.z-c.z if x_axis else lane.a.x-c.x
		distance := lane.width*0.5+3
		goal = p
		if x_axis {
			goal.z = coordinate+distance if coordinate+distance <= 17 else coordinate-distance
			goal.z = clamp(goal.z, 2, 17)
		} else {
			goal.x = coordinate+distance if coordinate+distance <= 16 else coordinate-distance
			goal.x = clamp(goal.x, -16, 16)
		}
	}
	if b.phase == .Dormant { goal = {0, 0, 14} }
	game.aim_at(g, game.boss_core(g.world), true)
	wish := goal-p
	wish.y = 0
	wish /= max(1, game.length(wish))
	right := game.Vec3{math.cos(g.player.yaw), 0, math.sin(g.player.yaw)}
	return {move = {game.dot(wish, right), game.dot(wish, game.forward(g.player.yaw, 0))}, focus = true, fire = game.boss_open(b), has_look = true, look = {g.player.yaw, g.player.pitch}}
}

@(test)
gc_encounter_is_winnable_by_movement_and_repeater_on_all_difficulties :: proc(t: ^testing.T) {
	for difficulty in game.Difficulty {
		w: game.World
		g: game.State
		boss_fixture(&g, &w, difficulty)
		g.player.health = 65 // The minimum health of a checkpoint retry.
		defer game.world_destroy(&w)
		phases: [3]bool
		{
			context.allocator, context.temp_allocator = mem.panic_allocator(), mem.panic_allocator()
			for _ in 0..<12000 {
				phases[g.boss.stage] = true
				if g.boss.phase == .Dead { break }
				game.update(&g, boss_command(&g), game.STEP)
				if g.deaths > 0 { break }
			}
		}
		if !testing.expectf(t, g.boss.phase == .Dead && g.deaths == 0, "%v fight failed: boss=%v health=%f deaths=%d position=%v", difficulty, g.boss, g.player.health, g.deaths, g.player.position) { return }
		testing.expect(t, phases[0] && phases[1] && phases[2] && g.shot_sequence >= 12)
		testing.expect(t, game.boss_valid(&w, g.boss) && game.boss_defeated(&w, g.boss))
		// Winning is a committed milestone; dying on the way to the exit must
		// not revive the collector or discard the earlier relay solution.
		game.respawn(&g)
		testing.expect(t, g.boss.phase == .Dead && g.lift_started && g.player.position == w.checkpoints[w.checkpoint_count-1].position)
	}
}

@(test)
gc_warning_commits_and_jump_clears_the_actual_brush :: proc(t: ^testing.T) {
	for jump in ([2]bool{false, true}) {
		w: game.World
		g: game.State
		boss_fixture(&g, &w, .Nightmare)
		defer game.world_destroy(&w)
		g.player.position = game.boss_room_origin(&w)+game.Vec3{0, 0.01, 13}
		game.update(&g, {}, game.STEP)
		lane := g.boss.lanes[0]
		testing.expect(t, g.boss.phase == .Mark && g.boss.duration >= 1.1)
		jumped := false
		for _ in 0..<600 {
			input: game.Input
			if jump && !jumped && g.boss.phase == .Sweep && game.length(game.boss_brush_position(g.boss)-game.Vec3{g.player.position.x, lane.a.y, g.player.position.z}) < 7.2 {
				input.jump_pressed, input.jump_held, jumped = true, true, true
			}
			game.update(&g, input, game.STEP)
			if g.boss.phase == .Exposed { break }
		}
		testing.expect_value(t, g.boss.lanes[0], lane)
		testing.expect(t, g.boss.phase == .Exposed)
		if jump { testing.expect(t, jumped && g.jump_sequence == 1 && g.damage_sequence == 0, "A timed real jump clears the low sweep")
		} else { testing.expect(t, g.damage_sequence > 0 && g.player.health < 100, "Ignoring the marked strip is dangerous") }
	}
}

@(test)
gc_shell_weak_node_and_cover_use_the_weapon_ray :: proc(t: ^testing.T) {
	w: game.World
	g: game.State
	boss_fixture(&g, &w)
	defer game.world_destroy(&w)
	g.player.position = game.boss_room_origin(&w)+game.Vec3{0, 0.05, 8}
	game.aim_at(&g, game.boss_core(&w), true)
	game.fire(&g, true)
	testing.expect_value(t, g.boss.health, game.BOSS_HEALTH)
	game.boss_plan(&g)
	game.boss_phase(&g.boss, .Exposed, 3)
	g.boss.timer = 2.7
	for _ in 0..<4 { game.aim_at(&g, game.boss_core(&w), true); game.fire(&g, true) }
	testing.expect(t, g.boss.health == 24 && g.boss.stage == 1 && g.boss.phase == .Stagger)
	game.boss_phase(&g.boss, .Exposed, 3); g.boss.timer = 2.7
	game.add_block(&w, game.boss_room_origin(&w)+game.Vec3{0, 3, 3}, {7, 6, 1})
	game.aim_at(&g, game.boss_core(&w), true)
	game.fire(&g, true)
	testing.expect_value(t, g.boss.health, 24)
	game.explode_fragment(&g, game.boss_room_origin(&w)+game.Vec3{0, 3, 4})
	testing.expect_value(t, g.boss.health, 24)
}

@(test)
gc_save_mid_sweep_and_death_restore_the_same_fight :: proc(t: ^testing.T) {
	w, restored: game.World
	g, other: game.State
	boss_fixture(&g, &w)
	defer game.world_destroy(&w)
	game.world_init_ram(&restored)
	defer game.world_destroy(&restored)
	other.world = &restored; game.init(&other)
	for _ in 0..<1200 {
		game.update(&g, boss_command(&g), game.STEP)
		if g.boss.phase == .Sweep && g.boss.timer < g.boss.duration*0.7 { break }
	}
	testing.expect_value(t, g.boss.phase, game.Boss_Phase.Sweep)
	data, decoded: game.Save_Data
	bytes: [game.SAVE_LIMIT]u8
	game.save_capture(&data, &g, .Quick, 8)
	size, err := game.save_encode(&data, bytes[:])
	testing.expect_value(t, err, game.Save_Error.None)
	testing.expect_value(t, game.save_decode(bytes[:size], &decoded), game.Save_Error.None)
	testing.expect_value(t, game.save_restore(&other, &decoded), game.Save_Error.None)
	for _ in 0..<500 {
		input := boss_command(&g)
		game.update(&g, input, game.STEP); game.update(&other, input, game.STEP)
	}
	saved_equal(t, &g, &other)
	game.respawn(&other)
	testing.expect(t, other.boss.phase == .Dormant && other.boss.health == game.BOSS_HEALTH && other.lift_started && other.player.health >= 65)
	decoded.live.state.boss.stage = 4
	testing.expect_value(t, game.save_restore(&other, &decoded), game.Save_Error.Content)
}

@(test)
flying_into_gc_commits_a_safe_short_retry :: proc(t: ^testing.T) {
	w: game.World
	game.world_init_ram(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	g.lift_started = true
	g.player.position = game.boss_room_origin(&w)+game.Vec3{0, 10, 14}
	g.player.gliding = true
	game.update(&g, {jump_held = true}, game.STEP)
	testing.expect(t, g.boss.phase == .Mark && g.checkpoint_id == w.checkpoints[w.checkpoint_count-1].id)
	game.respawn(&g)
	testing.expect(t, g.boss.phase == .Dormant && g.player.position == w.checkpoints[w.checkpoint_count-1].position && g.lift_started)
}
