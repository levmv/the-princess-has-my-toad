package tests

import "core:testing"
import game "../src/game"

@(test)
crab_rush_reaches_midrange_but_a_committed_dodge_or_jump_works :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	for difficulty in game.Difficulty {
		for dodge in 0..<3 {
			g := game.State{world = &w, difficulty = difficulty}
			flat_world(&g)
			game.spawn_enemy(&g, {0, game.enemy_extent(.Crab).y+0.03, -12.5}, 24, 0, .Crab)
			e := &g.enemies[0]
			for _ in 0..<120 {
				game.update_enemies(&g, game.STEP)
				if e.phase == .Windup && e.phase_time <= 0.19 { break }
			}
			testing.expect(t, e.phase == .Windup && e.position.z < -10, "The crab should threaten before reaching melee range")
			locked := e.attack_direction
			jumped := false
			for _ in 0..<100 {
				// Strafe after aim lock; jump as the rushing crab starts moving.
				jump := dodge == 2 && !jumped && e.phase == .Attack
				jumped = jumped || jump
				game.update_player(&g, {move = {1 if dodge == 1 else 0, 0}, jump_pressed = jump, jump_held = jumped}, game.STEP)
				game.update_enemies(&g, game.STEP)
			}
			testing.expectf(t, g.player.health == (100-26*game.difficulty_profile(difficulty).damage if dodge == 0 else f32(100)), "%v crab dodge=%d health=%f", difficulty, dodge, g.player.health)
			testing.expect(t, e.attack_direction == locked && e.phase == .Recover && game.crab_open(e^))
		}
	}
}

@(test)
crab_rush_stops_at_cover_and_exposes_the_plate :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	flat_world(&g)
	game.add_block(&w, {0, 2, -5}, {12, 4, 0.05})
	game.world_commit(&w)
	game.spawn_enemy(&g, {0, game.enemy_extent(.Crab).y+0.03, -12}, 24, 0, .Crab)
	e := &g.enemies[0]
	e.phase, e.phase_time, e.attack_direction, e.alerted = .Attack, 0.5, {0, 0, 1}, true
	testing.expect(t, !game.crab_open(e^))
	for _ in 0..<70 { game.update_enemies(&g, game.STEP) }
	testing.expect(t, e.position.z < -5-game.enemy_extent(.Crab).z && e.phase == .Recover && game.crab_open(e^))
	testing.expect_value(t, g.player.health, f32(100))
}

@(test)
kettle_can_pressure_an_open_lane_and_still_allows_a_late_dodge :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	for dodge in ([2]bool{false, true}) {
		g := game.State{world = &w}
		flat_world(&g)
		game.spawn_enemy(&g, {0, game.enemy_extent(.Kettle).y+0.03, -28}, 28, 0, .Kettle)
		e := &g.enemies[0]
		for _ in 0..<100 {
			game.update_enemies(&g, game.STEP)
			if e.phase == .Windup && e.phase_time <= 0.23 { break }
		}
		testing.expect(t, e.phase == .Windup && e.position.z < -26)
		marked := e.attack_target
		for _ in 0..<180 {
			game.update_player(&g, {move = {1 if dodge else 0, 0}}, game.STEP)
			game.update_enemies(&g, game.STEP)
			if e.phase == .Recover { break }
		}
		testing.expect(t, e.phase == .Recover && e.attack_target == marked && g.hazards[0].life > 0)
		testing.expect_value(t, g.player.health, f32(100 if dodge else 72))
	}
}

@(test)
mixed_courts_have_more_ground_presence_and_fairies_notice_less_far :: proc(t: ^testing.T) {
	w: game.World
	game.world_init_ram(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	for room in ([2]game.Room_ID{1005, 1015}) {
		ground, air := 0, 0
		for e in g.enemies[:g.enemy_count] {
			if w.encounters[e.encounter-1].room != room { continue }
			if game.enemy_grounded_kind(e.kind) { ground += 1 } else { air += 1 }
		}
		expected := 3 if room == 1005 else 4
		testing.expect(t, ground == expected && air == expected)
	}
	for kind in ([2]game.Enemy_Kind{.Sentry, .Interceptor}) {
		flat_world(&g)
		game.spawn_enemy(&g, {0, 2, -85}, 14, 0, kind, awareness = 90)
		for _ in 0..<40 { game.update_enemies(&g, game.STEP) }
		testing.expect(t, !g.enemies[0].alerted)
		g.player.position.z = -10
		for _ in 0..<40 { game.update_enemies(&g, game.STEP) }
		testing.expect(t, g.enemies[0].alerted && g.enemies[0].sees_player)
	}
}

@(test)
nanny_moves_with_a_shielded_ally :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	ally, nanny := support_fixture(&g)
	support := &g.enemies[nanny.slot]
	support.phase, support.phase_time, support.shield, support.support = .Attack, 2.4, 6, ally
	support.alerted, support.last_known = true, g.player.position
	start := support.position
	for _ in 0..<120 {
		g.enemies[ally.slot].position.z -= 4*game.STEP
		support.phase_time -= game.STEP
		game.update_nanny(&g, support, int(nanny.slot), game.STEP)
	}
	testing.expect(t, support.phase == .Attack && support.shield == 6 && game.length(support.position-start) > 2)
}
