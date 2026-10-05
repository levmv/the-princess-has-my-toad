package tests

import "core:testing"
import game "../src/game"

@(test)
shotgun_near_misses_catch_the_edge_without_full_center_damage :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	flat_world(&g)
	g.player.shotgun_unlocked = true
	for focus in ([2]bool{false, true}) {
		for offset in ([2]f32{-0.7, 0.7}) {
			center, edge, catches := 0, 0, 0
			for seed in u32(1)..=64 {
				for aimed in 0..<2 {
					g.enemies[0] = {position = {0, 1.5, -7}, facing = {0, 0, 1}, health = 1000}
					g.player.shotgun_ammo, g.weapon_rng = 1, seed*7919
					game.aim_at(&g, g.enemies[0].position+game.Vec3{offset if aimed == 1 else 0, 0, 0}, focus)
					if aimed == 1 {
						cam := game.camera(&g, focus)
						_, zone := game.enemy_hit(g.enemies[0], cam.position, cam.forward, 55)
						testing.expect_value(t, zone, game.Hit_Zone.None)
					}
					game.fire_shotgun(&g, focus)
					damage := 1000-g.enemies[0].health
					if aimed == 0 { center += damage
					} else { edge += damage; if damage > 0 { catches += 1 } }
				}
			}
			testing.expectf(t, catches >= 58 && edge > 64 && edge*2 < center, "Shotgun focus=%t offset=%f: edge hits %d/64, edge damage=%d center=%d", focus, offset, catches, edge, center)
		}
	}
}

@(test)
shotgun_camera_visibility_cannot_shoot_through_muzzle_cover :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	flat_world(&g)
	g.player.shotgun_unlocked, g.player.shotgun_ammo = true, 1
	g.enemies[0] = {position = {0, 2.5, -8}, facing = {0, 0, 1}, health = 1000}
	game.add_block(&w, {0, 0.9, -1}, {12, 1.8, 0.1})
	game.world_commit(&w)
	game.aim_at(&g, g.enemies[0].position, false)
	cam := game.camera(&g)
	delta := g.enemies[0].position-cam.position
	testing.expect_value(t, game.world_ray(&w, cam.position, game.normalized(delta), game.length(delta)), game.length(delta))
	game.fire_shotgun(&g, false)
	testing.expect_value(t, g.enemies[0].health, 1000)
}

@(test)
scope_sway_requires_correction_during_distant_sustained_fire :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	counts: [2]int
	for tracking in 0..<2 {
		flat_world(&g)
		g.enemies[0] = {position = {0, 1.5, -80}, health = 10000}
		game.aim_at(&g, g.enemies[0].position, true)
		for shot in 0..<512 {
			g.player.scope_time = f32(shot)*game.SHOT_INTERVAL
			g.player.weapon_bloom = 1
			if tracking == 1 { game.aim_at(&g, g.enemies[0].position, true) }
			game.fire(&g, true)
		}
		counts[tracking] = 10000-g.enemies[0].health
	}
	testing.expectf(t, counts[1] > 350 && counts[0]*2 < counts[1], "Sway should reward active correction: untracked=%d tracked=%d", counts[0], counts[1])
}

burst_hits :: proc(g: ^game.State, distance: f32, scoped, moving: bool) -> int {
	flat_world(g)
	g.player.scope_time = 1.3
	if moving { g.player.velocity.x = game.RUN_SPEED }
	g.enemies[0] = game.Enemy{position = {0, 1.5, -distance}, health = 10000}
	game.aim_at(g, g.enemies[0].position, scoped)
	for _ in 0..<512 {
		g.player.weapon_bloom = 1
		game.fire(g, scoped)
	}
	return 10000-g.enemies[0].health
}

@(test)
angular_spread_penalizes_distance_movement_and_long_bursts :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	close := burst_hits(&g, 8, false, true)
	medium := burst_hits(&g, 20, false, false)
	far := burst_hits(&g, 80, false, false)
	moving := burst_hits(&g, 80, false, true)
	scoped := burst_hits(&g, 80, true, false)
	testing.expectf(t, close >= 425, "Close automatic fire lost reliability: %d/512", close)
	testing.expectf(t, medium >= 225 && medium < close, "Medium range should remain useful: %d/512", medium)
	testing.expectf(t, far > 0 && far < 70, "Distant hip fire must be possible but wasteful: %d/512", far)
	testing.expectf(t, moving < far && scoped >= 350 && scoped > far*6, "Movement/scope should change accuracy: hip=%d moving=%d scoped=%d", far, moving, scoped)
	flat_world(&g)
	tight := game.weapon_spread(&g.player, false)
	for _ in 0..<10 { game.fire(&g, false) }
	testing.expect(t, game.weapon_spread(&g.player, false) > tight*3)
	for _ in 0..<120 { game.update_player(&g, {}, game.STEP) }
	testing.expect(t, g.player.weapon_bloom < 0.01, "Releasing fire settles the weapon")
}

@(test)
scope_sway_moves_the_actual_camera_and_preserves_focus_switches :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	flat_world(&g)
	g.player.scope_time = 1.7
	g.player.yaw, g.player.pitch = 0.3, 0.1
	base := game.forward(g.player.yaw, g.player.pitch)
	cam := game.camera(&g, true)
	testing.expect(t, game.length(base-cam.forward) > 0.001 && game.length(base-cam.forward) < 0.008)
	for i in 0..<12 {
		old_focus := i%2 == 0
		target := game.aim_point(&g, game.camera(&g, old_focus))
		game.change_focus(&g, old_focus, !old_focus)
		cam = game.camera(&g, !old_focus)
		testing.expect(t, game.dot(game.normalized(target-cam.position), cam.forward) > 0.99999)
	}
	h: game.Pose_History
	v: game.Render_Snapshot
	game.capture_poses(&h, &g)
	game.render_snapshot(&v, &g, &h, 1)
	testing.expect_value(t, game.camera(&g, true).forward, game.camera(&v, true).forward, )
}

@(test)
scope_compensation_preserves_input_limits_above_and_below_player :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	flat_world(&g)
	for i in 0..<80 {
		g.player.scope_time = f32(i)*0.2
		for y in ([2]f32{-100, 100}) {
			game.aim_at(&g, g.player.position+game.Vec3{0, y, -1}, true)
			testing.expect(t, g.player.pitch >= -1.2 && g.player.pitch <= 1.15, "Scope compensation escaped the recordable input range")
		}
	}
}
