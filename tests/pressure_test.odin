package tests

import "core:testing"
import game "../src/game"

@(test)
visible_long_range_sentry_engages_and_leads_a_running_target :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w, difficulty = .Nightmare}
	flat_world(&g)
	id, ok := game.spawn_enemy(&g, {0, 2, -65}, 20, 4, .Sentry, awareness = 90)
	testing.expect(t, ok)
	e := &g.enemies[id.slot]
	g.player.velocity = {10, 0, 0}
	for _ in 0..<90 { game.update_enemies(&g, game.STEP) }
	testing.expect(t, e.sees_player && e.alerted && g.projectile_cursor > 0, "A visible distant enemy must engage before being approached or shot")
	testing.expect(t, g.projectiles[0].velocity.x > 5, "Long shots lead observed movement")
	// A blind corner remains blind despite the longer range.
	flat_world(&g)
	game.add_block(&w, {0, 4, -10}, {30, 8, 0.1})
	game.spawn_enemy(&g, {0, 2, -45}, 20, 0, .Sentry, awareness = 90)
	for _ in 0..<300 { game.update_enemies(&g, game.STEP) }
	testing.expect(t, !g.enemies[0].alerted && g.projectile_cursor == 0)
}

@(test)
interceptor_closes_distance_before_committing_to_a_reachable_rush :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	for difficulty in game.Difficulty {
		g := game.State{world = &w, difficulty = difficulty}
		flat_world(&g)
		game.spawn_enemy(&g, {0, 1, -24}, 20, 0, .Interceptor)
		for _ in 0..<360 { game.update_player(&g, {}, game.STEP); game.update_enemies(&g, game.STEP); if g.player.health < 100 { break } }
		testing.expectf(t, g.player.health < 100, "%v rush started beyond its useful range", difficulty)
	}
}

@(test)
kettle_landing_catches_nearby_players_but_respects_jump_and_cover :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	for scenario in 0..<3 {
		g := game.State{world = &w}
		flat_world(&g)
		g.player.position = {4, 0, 0}
		if scenario == 1 { g.player.position.y = 2.4 }
		if scenario == 2 { game.add_block(&w, {2, 2, 0}, {0.2, 4, 14}) }
		id, _ := game.spawn_enemy(&g, {0, game.enemy_extent(.Kettle).y+0.04, 0}, 28, 0, .Kettle)
		e := &g.enemies[id.slot]
		e.phase, e.phase_time, e.velocity = .Attack, 1, {0, -4, 0}
		for _ in 0..<15 { game.update_enemies(&g, game.STEP) }
		testing.expectf(t, g.player.health == (72 if scenario == 0 else f32(100)), "Incorrect kettle landing damage in scenario %d: %f", scenario, g.player.health)
		testing.expect(t, g.hazards[0].radius == game.KETTLE_RADIUS)
	}
}
