package tests

import "core:testing"
import "core:mem"
import game "../src/game"

@(test)
fatal_projectile_keeps_its_cause_through_save_and_checkpoint_restore :: proc(t: ^testing.T) {
 w: game.World
 game.world_init_ram(&w)
 defer game.world_destroy(&w)
 g := game.State{world = &w}
 game.init(&g)
 g.player.invulnerable = 0
 game.damage(&g, 30, .Crab)
 testing.expect(t, g.player.hurt_strength > 0.8 && g.player.hurt_time > 0)
 health, sequence := g.player.health, g.damage_sequence
 game.damage(&g, 500, .Kettle)
 testing.expect(t, g.player.health == health && g.damage_sequence == sequence && g.deaths == 0)
 g.player.health, g.player.invulnerable = 1, 0
 g.projectiles[0] = {g.player.position+game.Vec3{0, 0.8, 0}, {}, 1, .Nanny}
 data, decoded: game.Save_Data
 bytes: [game.SAVE_LIMIT]u8
 testing.expect_value(t, game.save_capture(&data, &g, .Quick, 1), game.Save_Error.None)
 n, err := game.save_encode(&data, bytes[:])
 testing.expect_value(t, err, game.Save_Error.None)
 testing.expect_value(t, game.save_decode(bytes[:n], &decoded), game.Save_Error.None)
 testing.expect_value(t, game.save_restore(&g, &decoded), game.Save_Error.None)
 game.update(&g, {}, game.STEP)
 testing.expect(t, g.deaths == 1 && g.last_death == .Nanny && g.player.health >= 65)
 testing.expect(t, g.player.hurt_time == 0 && g.player.hurt_strength == 0)
 g.player.position.y = -100
 game.update(&g, {}, game.STEP)
 testing.expect(t, g.deaths == 2 && g.last_death == .Void)
}

@(test)
dead_enemies_stop_attacking_and_sweep_against_the_world :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	for kind in game.Enemy_Kind {
		flat_world(&g)
		game.add_block(&w, {3, 3, 0}, {0.05, 6, 20})
		id, ok := game.spawn_enemy(&g, {0, 2, -4}, 1, 0, kind)
		testing.expect(t, ok)
		e := &g.enemies[id.slot]
		e.phase, e.phase_time, e.rounds = .Attack, 0.01, 3
		e.knockback = {70, 0, 0}
		game.damage_enemy(&g, int(id.slot), 1, .Body, e.position, true)
		testing.expect(t, e.health <= 0 && e.phase_time == game.enemy_death_duration(kind))
		shots, sounds, kills := g.projectile_cursor, g.sound_sequence, g.kills
		for _ in 0..<480 {
			{
				context.allocator, context.temp_allocator = mem.panic_allocator(), mem.panic_allocator()
				game.update_enemies(&g, game.STEP)
			}
			testing.expect(t, e.position.x <= 2.975-game.enemy_extent(kind).x && e.position.y >= game.enemy_extent(kind).y-0.001)
		}
		testing.expect(t, g.projectile_cursor == shots && g.sound_sequence == sounds && g.kills == kills && g.player.health == 100)
		testing.expect_value(t, e.phase_time, f32(0))
		last := e.position
		game.update_enemies(&g, game.STEP)
		testing.expect_value(t, e.position, last)
		replacement, spawned := game.spawn_enemy(&g, {0, 2, -8}, 5, 1, kind)
		testing.expect(t, spawned && replacement.slot == id.slot && replacement.generation != id.generation)
		testing.expect(t, g.enemies[replacement.slot].phase == .Patrol && g.enemies[replacement.slot].velocity == (game.Vec3{}))
	}
}

@(test)
save_during_death_animation_and_player_hit_preserves_continuation :: proc(t: ^testing.T) {
	w, other: game.World
	game.world_load_sector(&w, .RAM_Combat_Lab, 42)
	game.world_load_sector(&other, .RAM_Combat_Lab, 42)
	defer game.world_destroy(&w)
	defer game.world_destroy(&other)
	a, b := game.State{world = &w}, game.State{world = &other}
	game.init(&a); game.init(&b)
	a.player.invulnerable = 0
	game.damage(&a, 10)
	game.damage_enemy(&a, 0, 100, .Body, a.enemies[0].position, true)
	for _ in 0..<8 { game.update(&a, {}, game.STEP) }
	testing.expect(t, a.player.hurt_time > 0 && a.enemies[0].phase_time > 0)
	data, decoded: game.Save_Data
	bytes: [game.SAVE_LIMIT]u8
	testing.expect_value(t, game.save_capture(&data, &a, .Quick, 17), game.Save_Error.None)
	n, err := game.save_encode(&data, bytes[:])
	testing.expect_value(t, err, game.Save_Error.None)
	testing.expect_value(t, game.save_decode(bytes[:n], &decoded), game.Save_Error.None)
	testing.expect_value(t, game.save_restore(&b, &decoded), game.Save_Error.None)
	saved_equal(t, &a, &b)
	for _ in 0..<480 { game.update(&a, {}, game.STEP); game.update(&b, {}, game.STEP) }
	saved_equal(t, &a, &b)
	game.respawn(&b)
	testing.expect_value(t, b.player.hurt_time, f32(0))
}
