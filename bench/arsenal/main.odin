package arsenal_balance

import "core:fmt"
import game "../../src/game"

main :: proc() {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	game.clear_blocks(&w)
	game.add_block(&w, {0, -1, 0}, {240, 2, 240})
	game.world_commit(&w)
	fmt.printf("%s / stationary fairy, sustained fire, 2048 shots per sample\n", game.BUILD_VERSION)
	fmt.println("range,hip_hit_pct,scope_tracked_hit_pct,scope_untracked_hit_pct,shotgun_mean_damage")
	for distance in ([4]f32{8, 20, 40, 80}) {
		values: [4]f32
		for mode in 0..<4 {
			g := game.State{world = &w}
			game.init(&g)
			g.player.position = {}
			g.enemy_count = 1
			g.enemies[0] = {position = {0, 1.5, -distance}, health = 100000, kind = .Sentry}
			game.aim_at(&g, g.enemies[0].position, mode == 1 || mode == 2)
			for shot in 0..<2048 {
				g.player.scope_time = f32(shot)*game.SHOT_INTERVAL
				g.player.weapon_bloom = 1
				if mode != 2 { game.aim_at(&g, g.enemies[0].position, mode == 1) }
				if mode == 3 {
					when #config(ARSENAL_SHOTGUN, true) {
						g.player.shotgun_unlocked, g.player.shotgun_ammo = true, 1
						game.fire_shotgun(&g, false)
					}
				} else { game.fire(&g, mode != 0) }
			}
			values[mode] = f32(100000-g.enemies[0].health)/2048*(1 if mode == 3 else f32(100))
		}
		fmt.printf("%.0f,%.2f,%.2f,%.2f,%.2f\n", distance, values[0], values[1], values[2], values[3])
	}
}
