package main

import "core:fmt"
import "core:time"
import "core:mem"
import game "../src/game"

main :: proc() {
	g_world: game.World
	game.world_init(&g_world, game.DEFAULT_SEED)
	defer game.world_destroy(&g_world)
	g := game.State{world = &g_world}
	game.init(&g)
	iterations :: 120000
	start := time.tick_now()
	{
		context.allocator = mem.panic_allocator()
		context.temp_allocator = mem.panic_allocator()
		for i in 0..<iterations {
			if i%2400 == 0 { game.init(&g) }
			game.update(&g, game.Input{move = {0.2, 1}, jump_pressed = i%150 == 0, jump_held = true, fire = true, dash_pressed = i%240 == 0}, game.STEP)
		}
	}
	ms := time.duration_seconds(time.tick_since(start))*1000
	fmt.printf("%d fixed steps in %.2f ms / %.3f us per step\n", iterations, ms, ms*1000/iterations)
	fmt.printf("Game state: %d bytes. Odin gameplay allocations: 0 (panic allocator enforced).\n", size_of(game.State))
	fmt.printf("Simulation only; excludes rendering, audio, input, GPU and presentation.\n")
	stress_simulation()
	stress_simulation(game.ENEMY_CAPACITY)
	stress_world_rays()
	bench_ram_sector()
	bench_gc()
}
