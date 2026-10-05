package tests

import "core:testing"
import game "../src/game"

@(test)
combat_fragment_has_walkable_cover_corner_and_climb :: proc(t: ^testing.T) {
	w: game.World
	game.world_load_sector(&w, .RAM_Combat_Lab, 42)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	testing.expect_value(t, g.enemy_total, 14)
	for &e in g.enemies { e.health = 0 }
	// Pass behind the first console before taking its side exit. These are
	// ordinary control inputs; neither position nor collisions are bypassed.
	route := []game.Vec3{{0, 0, -14}, {0, 0, -22}, {8.5, 0, -22}, {8.5, 0, -27}, {18, 0, -27}, {29, 0, -27}, {44, 0, -27}, {44, 0, -43}, {44, 0, -51}, {44, 0, -58}, {44, 3.6, -73}, w.exit}
	for target in route {
		if !testing.expectf(t, fly_to(&g, target), "Combat fragment blocked: target=%v player=%v", target, g.player.position) { return }
	}
	testing.expect(t, g.won && g.deaths == 0 && g.kills == 0)
	// The courtyard and raised final platform cannot be sniped from arrival.
	from := w.spawn+game.Vec3{0, 3.8, 0}
	for target in ([]game.Vec3{{44, 2, -27}, {44, 5.6, -76}}) {
		delta := target-from
		testing.expect(t, game.world_ray(&w, from, game.normalized(delta), game.length(delta)) < game.length(delta)-1)
	}
}

@(test)
crab_strike_can_be_jumped_or_interrupted_but_punishes_standing :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	for jump in 0..<2 {
		flat_world(&g)
		_, ok := game.spawn_enemy(&g, {0, game.enemy_extent(.Crab).y+0.03, -2.2}, 8, 0, .Crab)
		testing.expect(t, ok)
		e := &g.enemies[0]
		e.phase, e.phase_time, e.attack_direction, e.alerted = .Windup, 0.30, {0, 0, 1}, true
		e.last_known, e.memory_time = {0, 0.9, 0}, 7
		for step in 0..<65 {
			game.update_player(&g, game.Input{jump_pressed = jump == 1 && step == 0, jump_held = jump == 1}, game.STEP)
			game.update_enemies(&g, game.STEP)
		}
		testing.expect_value(t, g.player.health, f32(100 if jump == 1 else 74))
	}
}
