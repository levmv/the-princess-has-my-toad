package shotgun_bench

import "core:fmt"
import "core:mem"
import "core:slice"
import "core:time"
import game "../../src/game"

main :: proc() {
	w: game.World
	game.world_init_ram(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	court := w.sector.sections[game.room_index(&w.sector, 1005)]
	g.player.position = court.origin+game.Vec3{-19, 0.04, 1}
	game.aim_at(&g, court.origin+game.Vec3{-10, 3, 5}, false)
	fmt.printf("%s / %d pellets / release CPU benchmark\n", game.BUILD_VERSION, game.SHOTGUN_PELLETS)
	fmt.printf("Game build: %s\n", game.BUILD_ID)
	measure(&g, "RAM court")

	game.clear_blocks(&w)
	game.add_block(&w, {0, -1, 0}, {240, 2, 240})
	game.world_commit(&w)
	g.player.position = {}
	g.enemy_count = game.ENEMY_CAPACITY
	g.boss = {}
	for &e, i in g.enemies {
		e = {kind = game.Enemy_Kind(i%5), position = {f32(i%16)*3-22.5, 1.5, -8-f32(i/16)*5}, facing = {0, 0, 1}}
	}
	game.aim_at(&g, {0, 1.5, -18}, false)
	measure(&g, "128 nearby mixed enemies")
	fmt.println("4096 individual shots after 256 warmup shots per scene. Frozen actors, persistent effect pools; allocations prohibited.")
	fmt.println("Includes camera/muzzle rays, damage and effect events. Excludes AI, effect updates, rendering, audio and presentation; native CPU only.")
}

measure :: proc(g: ^game.State, label: string) {
	samples: [4096]f64
	for &e in g.enemies[:g.enemy_count] { e.health = 1000000 }
	g.player.shotgun_unlocked = true
	{
		context.allocator, context.temp_allocator = mem.panic_allocator(), mem.panic_allocator()
		for shot in -256..<len(samples) {
			g.player.shotgun_ammo = 1
			for &e in g.enemies[:g.enemy_count] { e.knockback = {} }
			start := time.tick_now()
			ok := game.fire_shotgun(g, false)
			elapsed := time.duration_seconds(time.tick_since(start))*1e6
			assert(ok)
			if shot >= 0 { samples[shot] = elapsed }
		}
	}
	checksum := 0
	for e in g.enemies[:g.enemy_count] { checksum += 1000000-e.health }
	slice.sort(samples[:])
	fmt.printf("%s: %d solids, %d enemies; median %.3f us/shot, P95 %.3f, P99 %.3f; damage checksum %d\n", label, len(g.world.blocks), g.enemy_count, samples[len(samples)/2], samples[len(samples)*95/100], samples[len(samples)*99/100], checksum)
}
