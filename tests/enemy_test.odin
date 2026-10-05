package tests

import "core:testing"
import game "../src/game"

@(test)
sentry_warns_locks_aim_and_fires_a_short_burst :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	flat_world(&g)
	g.enemies[0] = game.Enemy{anchor = {0, 2, -12}, position = {0, 2, -12}, health = 5, facing = {0, 0, 1}, alerted = true}
	for _ in 0..<56 { game.update_enemies(&g, game.STEP) }
	testing.expect(t, g.enemies[0].phase == .Windup && g.enemies[0].phase_time < 0.2)
	testing.expect(t, g.projectile_cursor == 0, "The warning must precede the shot")
	direction := g.enemies[0].attack_direction
	g.player.position.x = 7
	for _ in 0..<90 { game.update_enemies(&g, game.STEP) }
	testing.expect_value(t, g.projectile_cursor, 2)
	testing.expect(t, game.dot(game.normalized(g.projectiles[0].velocity), direction) > 0.99999, "The committed first shot preserves the dodge window")
	testing.expect(t, game.normalized(g.projectiles[1].velocity).x > 0.3, "Later rounds reacquire the visible target instead of repeating a stale miss")
	testing.expect(t, g.enemies[0].phase != .Attack)
	flat_world(&g)
	g.enemies[0] = game.Enemy{anchor = {0, 2, -12}, position = {0, 2, -12}, health = 5}
	game.add_block(&w, {0, 3, -6}, {20, 6, 0.1})
	for _ in 0..<300 { game.update_enemies(&g, game.STEP) }
	testing.expect(t, g.projectile_cursor == 0, "An occluded sentry does not shoot through cover")
}

@(test)
interceptor_charge_can_be_dodged_and_stops_at_walls :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	flat_world(&g)
	e := &g.enemies[0]
	e^ = game.Enemy{anchor = {0, 1, -8}, position = {0, 1, -8}, health = 5, kind = .Interceptor, phase = .Attack, phase_time = 0.55, attack_direction = {0, 0, 1}, alerted = true}
	game.add_block(&w, {0, 2, -3}, {12, 4, 0.05})
	for _ in 0..<55 { game.update_enemies(&g, game.STEP) }
	testing.expect(t, e.position.z < -3-game.enemy_extent(.Interceptor).z && e.phase == .Recover, "A charge sweeps against a thin wall")
	testing.expect_value(t, g.player.health, f32(100))
	flat_world(&g)
	e^ = game.Enemy{anchor = {0, 1, -8}, position = {0, 1, -8}, health = 5, kind = .Interceptor, phase = .Windup, phase_time = 0.15, attack_direction = {0, 0, 1}, alerted = true}
	g.player.position.x = 5
	for _ in 0..<100 { game.update_enemies(&g, game.STEP) }
	testing.expect(t, e.position.z > 2 && abs(e.position.x) < 0.001 && e.phase == .Recover)
	testing.expect(t, g.player.health == f32(100), "A dodge after aim lock avoids contact")
	flat_world(&g)
	e^ = game.Enemy{anchor = {0, 1, -8}, position = {0, 1, -8}, health = 5, kind = .Interceptor, phase = .Attack, phase_time = 0.55, attack_direction = {0, 0, 1}, alerted = true}
	for _ in 0..<65 { game.update_enemies(&g, game.STEP) }
	testing.expect(t, g.player.health == f32(78), "A charge applies contact damage once")
}

@(test)
interceptor_contact_respects_thin_cover_but_hits_before_a_wall :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	for step in ([2]f32{game.STEP, 0.5}) { for cover in 0..<3 {
		flat_world(&g)
		if cover != 0 { game.add_block(&w, {-0.45 if cover == 1 else f32(3), 2, 0}, {0.05, 4, 6}) }
		game.world_commit(&w)
		id, ok := game.spawn_enemy(&g, {-3, 0.9, 0}, 5, 100, .Interceptor)
		testing.expect(t, ok)
		e := &g.enemies[id.slot]
		e.phase, e.phase_time, e.attack_direction, e.alerted = .Attack, 0.55, {1, 0, 0}, true
		// A long step also checks contact along the swept path, before the
		// hunter reaches the wall behind the player.
		for _ in 0..<90 {
			game.update_enemies(&g, step)
			if e.phase == .Recover { break }
		}
		testing.expectf(t, g.player.health == f32(100 if cover == 1 else 78), "Hunter contact with cover=%d dealt the wrong damage: %f", cover, g.player.health)
	} }
}
