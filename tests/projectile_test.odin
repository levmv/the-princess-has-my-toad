package tests

import "core:mem"
import "core:testing"
import game "../src/game"

@(test)
enemy_bolts_sweep_the_player_and_resolve_the_nearest_collision :: proc(t: ^testing.T) {
	w: game.World
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	for wall in 0..<3 {
		game.clear_blocks(&w)
		if wall != 0 { game.add_block(&w, {1.4 if wall == 1 else -1.0, 1, 0}, {0.1, 4, 4}) }
		game.world_commit(&w)
		g.player = {health = 100}
		g.projectiles[0] = {{-2, 0.8, 0}, {480, 0, 0}, 1, .Fairy}
		{
			context.allocator, context.temp_allocator = mem.panic_allocator(), mem.panic_allocator()
			game.update_combat(&g, {}, game.STEP)
		}
		testing.expect(t, g.player.health == f32(100 if wall == 2 else 85), "A bolt crosses the player before a wall behind them; a wall in front stops it")
		testing.expect_value(t, g.projectiles[0].life, f32(0))
		expected_x := f32(-1.05 if wall == 2 else -0.55)
		testing.expect(t, abs(g.projectiles[0].position.x-expected_x) < 0.0001, "Impacts belong at the collision point, not at the start or end of the tick")
	}
}

@(test)
enemy_bolt_lifetime_limits_travel_but_stationary_overlap_still_hits :: proc(t: ^testing.T) {
	w: game.World
	g := game.State{world = &w, player = {health = 100}}
	g.projectiles[0] = {{-2, 0.8, 0}, {240, 0, 0}, game.STEP*0.25, .Hunter}
	game.update_combat(&g, {}, game.STEP)
	testing.expect(t, g.player.health == 100 && g.projectiles[0].life == 0)
	testing.expect(t, abs(g.projectiles[0].position.x+1.5) < 0.0001, "An expiring bolt only travels for its remaining lifetime")
	g.projectiles[0] = {{0, 0.8, 0}, {}, 1, .Hunter}
	game.update_combat(&g, {}, game.STEP)
	testing.expect(t, g.player.health == 85 && g.projectiles[0].life == 0)
}

@(test)
forgiving_player_hit_volume_cannot_protrude_through_thin_cover :: proc(t: ^testing.T) {
	w: game.World
	defer game.world_destroy(&w)
	g := game.State{world = &w, player = {health = 100}}
	// The physical player fits behind the wall; only the extra hit margin
	// extends in front of it. That margin must not make cover transparent.
	game.add_block(&w, {-0.4, 1, 0}, {0.05, 4, 4})
	game.world_commit(&w)
	g.projectiles[0] = {{-2, 0.8, 0}, {480, 0, 0}, 1, .Fairy}
	game.update_projectiles(&g, game.STEP)
	testing.expect(t, g.player.health == 100 && g.projectiles[0].life == 0)
	testing.expect(t, abs(g.projectiles[0].position.x+0.425) < 0.0001)
	game.clear_blocks(&w)
	game.add_block(&w, {0, game.PLAYER_HEIGHT+0.03, 0}, {4, 0.04, 4})
	game.world_commit(&w)
	g.projectiles[0] = {{0, 3, 0}, {0, -480, 0}, 1, .Fairy}
	game.update_projectiles(&g, game.STEP)
	testing.expect(t, g.player.health == 100 && g.projectiles[0].life == 0)
	testing.expect(t, abs(g.projectiles[0].position.y-(game.PLAYER_HEIGHT+0.05)) < 0.0001)
	game.clear_blocks(&w)
	game.add_block(&w, {-0.45, 0.8, -0.38}, {0.03, 2, 0.006})
	game.world_commit(&w)
	// Here cover hides the nearest point behind the padded corner, but the
	// actual trajectory goes around its edge and then enters the physical body.
	direction := game.Vec3{0.8, 0, 0.6}
	g.projectiles[0] = {game.Vec3{-0.55, 0.8, -0.4}-direction*2, direction*480, 1, .Fairy}
	game.update_projectiles(&g, game.STEP)
	testing.expect(t, g.player.health == 85 && g.projectiles[0].life == 0, "Occluded padding cannot swallow an unobstructed hit on the actual body")
}

@(test)
lethal_bolt_ends_combat_before_later_projectiles_advance :: proc(t: ^testing.T) {
	w: game.World
	g := game.State{world = &w, player = {health = 1}, in_step = true}
	g.projectiles[0] = {{0, 0.8, 0}, {}, 1, .Fairy}
	g.projectiles[1] = {{10, 1, 0}, {0, 0, 20}, 1, .Hunter}
	game.update_combat(&g, {}, game.STEP)
	testing.expect(t, g.respawn_pending && g.last_death == .Fairy)
	testing.expect(t, g.projectiles[1].position == game.Vec3{10, 1, 0} && g.projectiles[1].life == 1, "Do not mutate the rest of a dead run before its deferred checkpoint restore")
}

@(test)
fragment_lifetime_and_lethal_blast_stop_at_the_same_simulation_boundary :: proc(t: ^testing.T) {
	w: game.World
	g := game.State{world = &w, player = {health = 100}}
	g.fragments[0] = {{-20, 0.8, 0}, {240, 0, 0}, game.STEP*0.25}
	game.update_fragments(&g, game.STEP)
	testing.expect(t, g.fragments[0].life == 0 && abs(g.fragments[0].position.x+19.5) < 0.0001)
	g.player.health, g.player.invulnerable, g.in_step = 1, 0, true
	g.fragments[0] = {{0, 0.7, 0}, {}, game.STEP*0.5}
	g.fragments[1] = {{20, 1, 0}, {0, 0, 20}, 1}
	game.update_fragments(&g, game.STEP)
	testing.expect(t, g.respawn_pending && g.last_death == .Fragment && g.player.velocity == game.Vec3{}, "A lethal blast cannot apply a posthumous impulse")
	testing.expect(t, g.fragments[1].position == game.Vec3{20, 1, 0} && g.fragments[1].life == 1)
}
