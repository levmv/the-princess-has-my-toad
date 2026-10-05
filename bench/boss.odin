package main

import "core:fmt"
import "core:mem"
import "core:slice"
import "core:time"
import game "../src/game"

bench_gc :: proc() {
	w: game.World
	game.world_init_ram(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w, difficulty = .Nightmare}
	samples: [4096]f64
	checksum := f32(0)
	for &sample, i in samples {
		if i%128 == 0 {
			game.init(&g)
			g.lift_started = true
			g.player.position = game.boss_room_origin(&w)+game.Vec3{0, 0.02, 14}
			g.player.invulnerable = 1000
			g.boss.health, g.boss.stage = 12, 2
			game.boss_plan(&g)
			game.boss_phase(&g.boss, .Sweep if i/128%2 == 0 else .Mark, 1.5)
			for &p, j in g.particles { p = {g.player.position+game.Vec3{f32(j%16), 2, f32(j/16)}, {0, 1, 0}, 3, 3, 0.04, 0} }
			game.drop_anvil(&g)
		}
		start := time.tick_now()
		{
			context.allocator, context.temp_allocator = mem.panic_allocator(), mem.panic_allocator()
			game.update(&g, {move = {0.2, 0}, fire = true}, game.STEP)
		}
		sample = time.duration_seconds(time.tick_since(start))*1e6
		checksum += g.player.position.x+f32(g.boss.health)
	}
	slice.sort(samples[:])
	fmt.printf("GC Nightmare + 384 particles + anvil, 4096 individual steps: median %.3f us, P95 %.3f, P99 %.3f, max %.3f; checksum %.3f\n", samples[len(samples)/2], samples[len(samples)*95/100], samples[len(samples)*99/100], samples[len(samples)-1], checksum)
	fmt.println("GC samples include two clock reads per individual step; fixture reset is outside timing. No render/audio/input, Odin tick allocations=0.")
}
