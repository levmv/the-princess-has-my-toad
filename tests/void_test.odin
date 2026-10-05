package tests

import "core:mem"
import "core:math"
import "core:testing"
import game "../src/game"

@(test)
knocking_a_landing_guard_into_the_void_counts_once_and_settles :: proc(t: ^testing.T) {
	w: game.World
	game.world_init_ram(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	landing := w.sector.sections[game.room_index(&w.sector, 1011)].origin+game.CHARGE_LANDINGS[3]
	for killed_before_falling in ([2]bool{false, true}) {
		game.init(&g)
		guard := -1
		for &e, i in g.enemies[:g.enemy_count] {
			if w.encounters[e.encounter-1].room == 1011 && e.kind == .Crab { guard = i
			} else { e.health, e.phase_time, e.velocity, e.phase = 0, 0, {}, .Recover }
		}
		if !testing.expect(t, guard >= 0) { return }
		e := &g.enemies[guard]
		e.position.x = landing.x+5.2
		g.player.position = e.position-game.Vec3{1.8, game.enemy_extent(.Crab).y, 0}
		g.player.yaw, g.player.invulnerable = math.PI*0.5, 100
		game.kick(&g)
		testing.expect(t, e.health == 22 && e.knockback.x > 14, "The real kick must push a living guard off the landing")
		if killed_before_falling { game.damage_enemy(&g, guard, 100, .Body, e.position, true) }
		{
			context.allocator, context.temp_allocator = mem.panic_allocator(), mem.panic_allocator()
			for _ in 0..<1200 { game.update_enemies(&g, game.STEP) }
		}
		testing.expectf(t, e.position.y < -24 && e.health <= 0 && g.kills == 1, "Falling guard (already dead=%v): y=%f, health=%d, kills=%d", killed_before_falling, e.position.y, e.health, g.kills)
		testing.expect(t, e.velocity == game.Vec3{} && e.knockback == game.Vec3{} && e.phase_time == 0, "An actor below the playable world must stop simulating")
		position, kills := e.position, g.kill_sequence
		for _ in 0..<240 { game.update_enemies(&g, game.STEP) }
		testing.expect(t, e.position == position && g.kill_sequence == kills && g.kills == 1)
		data, decoded: game.Save_Data
		bytes: [game.SAVE_LIMIT]u8
		testing.expect_value(t, game.save_capture(&data, &g, .Quick, 29), game.Save_Error.None)
		n, err := game.save_encode(&data, bytes[:])
		testing.expect_value(t, err, game.Save_Error.None)
		testing.expect_value(t, game.save_decode(bytes[:n], &decoded), game.Save_Error.None)
		testing.expect_value(t, game.save_restore(&g, &decoded), game.Save_Error.None)
		for _ in 0..<240 { game.update_enemies(&g, game.STEP) }
		testing.expect(t, g.enemies[guard].position == position && g.kill_sequence == kills && g.kills == 1)
	}
}
