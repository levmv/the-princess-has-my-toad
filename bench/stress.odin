package main

import "core:fmt"
import "core:math"
import "core:mem"
import "core:slice"
import "core:time"
import game "../src/game"

stress_simulation :: proc(enemy_target: int = 6) {
	// Saturate the actual pools. Fixture setup is outside the timed interval.
	batches :: 128
	steps :: 256
	samples: [batches]f64
	checksum := f32(0)
	for batch in 0..<batches {
		g_world: game.World
		game.world_init(&g_world, game.DEFAULT_SEED)
		defer game.world_destroy(&g_world)
		g := game.State{world = &g_world}
		game.init(&g)
		game.clear_blocks(g.world)
		game.add_block(g.world, {0, -1, 0}, {200, 2, 200})
		for len(g.world.blocks) < 64 {
			index := len(g.world.blocks)
			game.add_block(g.world, {f32(index%8)*8-28, 1, -60-f32(index/8)*8}, {4, 2, 4})
			game.bevel_block(&g.world.blocks[index], 0.5, 0.1)
		}
		for g.enemy_count < enemy_target {
			i := g.enemy_count
			_, ok := game.spawn_enemy(&g, {f32(i%16)*3-23, 4+f32(i%3), -f32(i/16)*4})
			assert(ok)
		}
		for &bullet, i in g.projectiles { bullet = {{f32(i%12)*3-16, 25, -f32(i/12)*4}, {1, 0, -1}, 100, .Fairy} }
		for &fragment, i in g.fragments { fragment = {{f32(i%8)*3-12, 5, -f32(i/8)*8}, {2, 0, -3}, 10} }
		for i in 0..<len(g.hazards) { assert(game.spawn_floor_hazard(&g, {f32(i%6)*3-8, 0.04, -f32(i/6)*4}, 2.8)) }
		for &particle, i in g.particles { particle = {{f32(i), 10, 0}, {0, 1, 0}, 100, 100, 0.08, 0} }
		for &enemy, i in g.enemies[:g.enemy_count] {
			enemy.kind = game.Enemy_Kind(i%5)
			y := game.enemy_extent(enemy.kind).y+0.03 if game.enemy_grounded_kind(enemy.kind) else f32(2.5)
			enemy.position = {f32(i%16)*2.5-19, y, 12-f32(i/16)*3}
			enemy.health, enemy.fire_timer = 10000, 0
			enemy.alerted, enemy.memory_time, enemy.last_known = true, 10, g.player.position+game.Vec3{0, 0.9, 0}
		}
		g.player.invulnerable = 100
		game.world_commit(g.world)
		start := time.tick_now()
		{
			context.allocator = mem.panic_allocator()
			context.temp_allocator = mem.panic_allocator()
			for _ in 0..<steps { game.update(&g, game.Input{fire = true}, game.STEP) }
		}
		samples[batch] = time.duration_seconds(time.tick_since(start))*1e6/steps
		checksum += g.player.position.y+f32(g.shot_sequence)
	}
	slice.sort(samples[:])
	fmt.printf("Saturated simulation: 64 solids / %d enemies of all 5 roles / 96 bolts / 16 fragments / 24 hazards / 384 particles. Median %.3f us/step, batch P95 %.3f, P99 %.3f us/step, checksum %.3f\n", enemy_target, samples[batches/2], samples[batches*95/100], samples[batches*99/100], checksum)
}

stress_world_rays :: proc() {
	counts := [3]int{30, 300, 3000}
	iterations :: 10000
	for count in counts {
		w: game.World
		defer game.world_destroy(&w)
		for i in 0..<count {
			game.add_block(&w, {f32(i%32)*8-128, 2, -f32(i/32)*8}, {4, 4, 4})
			game.bevel_block(&w.blocks[i], 0.5, 0.1)
		}
		game.world_commit(&w)
		for indexed in 0..<2 {
			checksum := f32(0)
			start := time.tick_now()
			{
				context.allocator = mem.panic_allocator()
				context.temp_allocator = mem.panic_allocator()
				for i in 0..<iterations {
					a := f32(i%257)*0.007
					dir := game.normalized(game.Vec3{math.sin(a), 0, -math.cos(a)})
					distance := game.world_ray(&w, {0, 1.5, 6}, dir, 110) if indexed == 1 else game.world_ray_linear(&w, {0, 1.5, 6}, dir, 110)
					checksum += distance
				}
			}
			us := time.duration_seconds(time.tick_since(start))*1e6/iterations
			fmt.printf("Synthetic world ray: %d solids, %s %.3f us/query, checksum %.3f\n", count, "BVH" if indexed == 1 else "linear", us, checksum)
		}
	}
	fmt.println("Ray stress compares identical convex queries; it is not a full large-level or pathfinding benchmark.")
}
