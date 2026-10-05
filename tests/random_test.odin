package tests

import "core:testing"
import game "../src/game"

@(test)
visual_effect_density_does_not_change_enemy_fire :: proc(t: ^testing.T) {
	a_world: game.World
	game.world_init(&a_world, 42)
	defer game.world_destroy(&a_world)
	a := game.State{world = &a_world}
	b_world: game.World
	game.world_init(&b_world, 42)
	defer game.world_destroy(&b_world)
	b := game.State{world = &b_world}
	reset_fixture(&a)
	reset_fixture(&b)
	for &enemy in a.enemies[:a.enemy_count] { enemy.health = 0 }
	for &enemy in b.enemies[:b.enemy_count] { enemy.health = 0 }
	a.enemies[0] = game.Enemy{anchor = {0, 2, 10}, position = {0, 2, 10}, facing = {0, 0, 1}, health = 3}
	b.enemies[0] = a.enemies[0]
	game.emit(&b, {0, 1, 0}, 100, 0)
	for _ in 0..<180 {
		game.update_combat(&a, {}, game.STEP)
		game.update_combat(&b, {}, game.STEP)
	}
	testing.expect(t, a.projectile_cursor == 2 && b.projectile_cursor == 2, "The fixture must exercise a prepared burst and its randomized cooldown")
	testing.expect_value(t, a.enemies[0].fire_timer, b.enemies[0].fire_timer)
	testing.expect_value(t, a.rng, b.rng)
	testing.expect_value(t, a.projectiles[0], b.projectiles[0])
}
