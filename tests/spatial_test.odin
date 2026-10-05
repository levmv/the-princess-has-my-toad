package tests

import "core:testing"
import "core:mem"
import game "../src/game"

@(test)
bvh_matches_linear_rays_and_sweeps :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	for i in 0..<300 {
		game.add_block(&w, {f32(i%20)*5-50, 1, -50-f32(i/20)*6}, {3, 2, 4})
		game.bevel_block(&w.blocks[len(w.blocks)-1], 0.4, 0.1)
	}
	game.world_commit(&w)
	seed := u32(71323)
	context.allocator = mem.panic_allocator()
	context.temp_allocator = mem.panic_allocator()
	for i in 0..<4000 {
		origin := game.Vec3{game.random_stream(&seed)*120-60, game.random_stream(&seed)*12, 30-game.random_stream(&seed)*180}
		direction := game.normalized(game.Vec3{game.random_stream(&seed)-0.5, game.random_stream(&seed)-0.5, game.random_stream(&seed)-0.5})
		if i%5 == 0 { direction = {0, -1, 0} }
		if i%7 == 0 { direction = game.normalized({0.0000001, -1, 0}) }
		padding := game.CAMERA_CLEARANCE if i%2 == 0 else f32(0)
		linear := game.world_ray_linear(&w, origin, direction, 130, padding)
		indexed := game.world_ray(&w, origin, direction, 130, padding)
		if !testing.expectf(t, abs(linear-indexed) < 0.0001, "Ray %d: linear=%v BVH=%v", i, linear, indexed) { return }
		delta := direction*(game.random_stream(&seed)*10)
		extent := game.Vec3{game.PLAYER_RADIUS, game.PLAYER_HEIGHT*0.5, game.PLAYER_RADIUS}
		a, na := game.world_sweep(&w, origin, delta, extent)
		w.index_revision = 0
		b, nb := game.world_sweep(&w, origin, delta, extent)
		w.index_revision = w.revision
		if !testing.expectf(t, a == b && na == nb, "Sweep %d: indexed=%v/%v linear=%v/%v", i, a, na, b, nb) { return }
	}
}

@(test)
world_edits_invalidate_index_without_stale_collisions :: proc(t: ^testing.T) {
	w: game.World
	defer game.world_destroy(&w)
	game.add_block(&w, {0, 0, -5}, {2, 2, 2})
	game.world_commit(&w)
	testing.expect_value(t, game.world_ray(&w, {}, {0, 0, -1}, 20), f32(4))
	game.set_block(&w, 0, game.Block{center = {0, 0, -10}, size = {2, 2, 2}})
	testing.expect_value(t, game.world_ray(&w, {}, {0, 0, -1}, 20), f32(9))
	game.world_commit(&w)
	testing.expect_value(t, game.world_ray(&w, {}, {0, 0, -1}, 20), f32(9))
	game.clear_blocks(&w)
	game.world_commit(&w)
	testing.expect_value(t, game.world_ray(&w, {}, {0, 0, -1}, 20), f32(20))
}

@(test)
projectile_exhaustion_and_enemy_handles_are_explicit :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	for &p in g.projectiles { p = {{1, 2, 3}, {4, 5, 6}, 7, .Unknown} }
	before := g.projectiles
	testing.expect(t, !game.spawn_projectile(&g, {{8, 8, 8}, {}, 10, .Unknown}))
	testing.expect_value(t, g.projectiles, before)
	g.projectiles[31].life = 0
	testing.expect(t, game.spawn_projectile(&g, {{8, 8, 8}, {}, 10, .Unknown}))
	testing.expect_value(t, g.projectiles[31].position, game.Vec3{8, 8, 8})
	id, ok := game.spawn_enemy(&g, {})
	testing.expect(t, ok)
	game.find_enemy(&g, id).health = 0
	replacement, replaced := game.spawn_enemy(&g, {})
	testing.expect(t, replaced && replacement.slot == id.slot && replacement.generation != id.generation)
	testing.expect(t, game.find_enemy(&g, id) == nil && game.find_enemy(&g, replacement) != nil)
	game.init(&g)
	testing.expect(t, game.find_enemy(&g, replacement) == nil)
}

@(test)
snapshot_borrows_world_and_does_not_interpolate_reused_slots :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	h: game.Pose_History
	game.capture_poses(&h, &g)
	start := g.player.position
	g.player.position.x += 2
	g.player.yaw = 0.75
	g.enemies[0].health = 0
	_, ok := game.spawn_enemy(&g, {30, 2, 4})
	testing.expect(t, ok)
	v: game.Render_Snapshot
	game.render_snapshot(&v, &g, &h, 0.5)
	testing.expect(t, v.world == &w && raw_data(v.particles) == &g.particles[0])
	testing.expect_value(t, v.player.position, start+game.Vec3{1, 0, 0})
	testing.expect_value(t, v.player.yaw, f32(0.75))
	testing.expect_value(t, v.enemies[0].position, game.Vec3{30, 2, 4})
}
