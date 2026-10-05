package main

import "core:fmt"
import "core:time"
import "core:mem"
import "core:slice"
import game "../src/game"

bench_ram_sector :: proc() {
	w: game.World
	begin := time.tick_now()
	game.world_init_ram(&w)
	defer game.world_destroy(&w)
	fmt.printf("RAM world generation + BVH + room paths: %.3f ms; %d static collision solids, %d dynamic gates, %d decor blocks, %d beams, %d rooms\n", time.duration_seconds(time.tick_since(begin))*1000, len(w.blocks), w.gate_count, len(w.decor_blocks), len(w.decor_beams), w.sector.count)
	bytes := size_of(game.World)+size_of(game.State)
	bytes += cap(w.blocks)*size_of(game.Block)+cap(w.decor_blocks)*size_of(game.Decor_Block)+cap(w.decor_beams)*size_of(game.Decor_Beam)
	bytes += cap(w.vents)*size_of(game.Vent)+(cap(w.core_spawns)+cap(w.enemy_spawns)+cap(w.lamps))*size_of(game.Vec3)
	bytes += cap(w.encounters)*size_of(game.Encounter)+cap(w.nodes)*size_of(game.BVH_Node)+cap(w.block_order)*size_of(int)
	fmt.printf("RAM simulation and world container capacity: %d bytes (excludes GPU, assets and allocator bookkeeping)\n", bytes)
	g := game.State{world = &w}
	samples: [120]f64
	checksum := f32(0)
	for &sample, batch in samples {
		game.init(&g)
		room := w.sector.sections[batch%w.sector.count]
		g.player.position = room.origin+game.Vec3{0, 0.05, 0}
		nav := &w.room_navigation[batch%w.sector.count]
		if nav.count > 0 { g.player.position = nav.points[0]+game.Vec3{0, 0.05, 0} }
		if room.id == 1022 { g.player.position = room.origin+game.Vec3{4, 0.05, -3} }
		g.player.invulnerable = 1000
		g.lift_started = true
		start := time.tick_now()
		{
			context.allocator = mem.panic_allocator()
			context.temp_allocator = mem.panic_allocator()
			for tick in 0..<1000 {
				game.update(&g, game.Input{move = {0.4, 0.3}, jump_pressed = tick%180 == 0, fire = true}, game.STEP)
				g.won = false
			}
		}
		sample = time.duration_seconds(time.tick_since(start))*1000
		checksum += g.player.position.x+g.player.position.y+f32(g.shot_sequence)
	}
	slice.sort(samples[:])
	fmt.printf("RAM %d actors, 120000 ticks through %d room starts: median %.3f us/tick, batch P95 %.3f, P99 %.3f; checksum %.3f\n", g.enemy_count, w.sector.count, samples[len(samples)/2], samples[len(samples)*95/100], samples[len(samples)*99/100], checksum)
	fmt.println("Batch timings cover 1000 real simulation steps each; initialization and room placement are outside measurement. No graphics/audio/input, Odin tick allocations=0.")
}
