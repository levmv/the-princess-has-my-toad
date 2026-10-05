package tests

import "core:testing"
import "core:mem"
import game "../src/game"

rabbit_slot :: proc(g: ^game.State, ordinal: int) -> int {
	id := game.room_object_id(1017, u16(0x100+ordinal))
	for e, i in g.enemies[:g.enemy_count] { if e.content_id == id { return i } }
	panic("Missing authored rabbit")
}

@(test)
rabbit_pack_spreads_out_while_chasing_a_runner :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	flat_world(&g)
	game.world_commit(&w)
	ids: [4]game.Enemy_ID
	for &id in ids {
		// Births beside cover can place siblings in exactly the same spot.
		id, _ = game.spawn_enemy(&g, {0, game.enemy_extent(.Rabbit_Kit).y+0.04, -60}, 20, 100, .Rabbit_Kit)
	}
	g.player.velocity = {0, 0, game.RUN_SPEED}
	{
		context.allocator, context.temp_allocator = mem.panic_allocator(), mem.panic_allocator()
		for tick in 0..<360 {
			g.time = f32(tick)*game.STEP
			g.player.position = {0, 0.04, -25+g.time*game.RUN_SPEED}
			game.update_enemies(&g, game.STEP)
		}
	}
	left, right := f32(100), f32(-100)
	for id, i in ids {
		e := g.enemies[id.slot]
		left, right = min(left, e.position.x), max(right, e.position.x)
		testing.expectf(t, e.position.z > -28 && e.position.y > 0.5, "Rabbit %d keeps pursuing while making room: %v", i, e.position)
		for j in i+1..<len(ids) {
			delta := e.position-g.enemies[ids[j].slot].position
			delta.y = 0
			testing.expectf(t, game.length(delta) > 1.6, "Rabbits %d and %d overlap during a distant chase: gap=%f", i, j, game.length(delta))
		}
	}
	testing.expectf(t, right-left > 4, "The pack should use separate approaches, width=%f", right-left)
}

@(test)
smaller_rabbits_close_the_distance_faster :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	travel: [3]f32
	for kind, i in ([3]game.Enemy_Kind{.Rabbit, .Rabbit_Young, .Rabbit_Kit}) {
		g = game.State{world = &w} // Compare the same individual temperament at each size.
		flat_world(&g)
		g.player.position = {0, 0.04, 60}
		id, _ := game.spawn_enemy(&g, {0, game.enemy_extent(kind).y+0.04, 0}, 100, 100, kind)
		for tick in 0..<240 {
			g.time = f32(tick)*game.STEP
			game.update_enemies(&g, game.STEP)
		}
		travel[i] = g.enemies[id.slot].position.z
	}
	testing.expectf(t, travel[0] > 26 && travel[1] > travel[0]*1.1 && travel[2] > travel[1]*1.1, "Successive generations should gain noticeably on the runner: %v", travel)
}

@(test)
rabbit_offspring_use_narrow_routes_that_the_adult_cannot_fit :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	flat_world(&g)
	w.sector.count = 1
	for side in ([2]f32{-1, 1}) { game.add_block(&w, {side*2.25, 3, 0}, {1.5, 6, 8}) }
	w.room_navigation[0].count = 2
	w.room_navigation[0].points[0], w.room_navigation[0].points[1] = {0, 0, -7}, {0, 0, 7}
	game.world_commit(&w)
	game.build_room_navigation(&w)
	for kind in ([2]game.Enemy_Kind{.Rabbit, .Rabbit_Kit}) {
		y := game.enemy_extent(kind).y+0.04
		_, found := game.enemy_room_goal(&w, 0, {0, y, -7}, {0, y, 7}, kind)
		testing.expectf(t, found == (kind == .Rabbit_Kit), "%v uses its own physical clearance", kind)
	}
}

@(test)
rabbit_family_is_finite_and_newborns_survive_the_parent_blast :: proc(t: ^testing.T) {
	w: game.World
	game.world_init_ram(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	root := rabbit_slot(&g, 0)
	for ordinal in 1..<7 {
		e := g.enemies[rabbit_slot(&g, ordinal)]
		testing.expect(t, e.phase == .Dormant && !game.enemy_active(e))
		_, zone := game.enemy_hit(e, e.position+game.Vec3{0, 0, 5}, {0, 0, -1}, 10)
		testing.expect_value(t, zone, game.Hit_Zone.None)
	}
	parent := g.enemies[root]
	_, head_zone := game.enemy_hit(parent, parent.position+(game.Vec3{0, 0.55, 0}+parent.facing*3)*game.enemy_scale(parent.kind), -parent.facing, 10)
	testing.expect_value(t, head_zone, game.Hit_Zone.Body)
	g.enemies[root].health = 1
	{
		context.allocator, context.temp_allocator = mem.panic_allocator(), mem.panic_allocator()
		game.explode_fragment(&g, g.enemies[root].position)
	}
	testing.expect(t, g.enemies[root].health <= 0 && g.enemies[root].gibbed)
	for ordinal in 1..<3 {
		e := &g.enemies[rabbit_slot(&g, ordinal)]
		testing.expect(t, e.phase == .Hatching && e.health > 0)
		health := e.health
		testing.expect_value(t, game.damage_enemy(&g, rabbit_slot(&g, ordinal), 500, .Body, e.position), 0)
		testing.expect_value(t, e.health, health)
	}
	for generation in 0..<2 {
		for _ in 0..<44 { game.update_enemies(&g, game.STEP) }
		first, last := 1 if generation == 0 else 3, 3 if generation == 0 else 7
		for ordinal in first..<last {
			i := rabbit_slot(&g, ordinal)
			game.damage_enemy(&g, i, 500, .Body, g.enemies[i].position, true)
		}
	}
	testing.expect(t, g.kills == 7 && g.enemy_total == 50)
	game.damage_enemy(&g, root, 500, .Body, g.enemies[root].position)
	for ordinal in 0..<7 { testing.expect(t, g.enemies[rabbit_slot(&g, ordinal)].health <= 0) }
}

@(test)
rabbit_birth_positions_and_saved_family_survive_near_a_wall :: proc(t: ^testing.T) {
	w, loaded: game.World
	game.world_init_ram(&w)
	game.world_init_ram(&loaded)
	defer game.world_destroy(&w)
	defer game.world_destroy(&loaded)
	g, restored := game.State{world = &w}, game.State{world = &loaded}
	game.init(&g)
	root := rabbit_slot(&g, 0)
	e := &g.enemies[root]
	e.position.x, e.facing = -14.3, {0, 0, 1}
	game.damage_enemy(&g, root, 200, .Body, e.position, true)
	for ordinal in 1..<3 {
		child := g.enemies[rabbit_slot(&g, ordinal)]
		fraction, _ := game.world_sweep(&w, child.position, {0, 0.01, 0}, game.enemy_extent(child.kind))
		testing.expect(t, fraction == 1, "Newborn hull is outside the wall and floor")
	}
	data, decoded: game.Save_Data
	buffer: [game.SAVE_LIMIT]u8
	game.save_capture(&data, &g, .Quick, 1)
	size, err := game.save_encode(&data, buffer[:])
	testing.expect_value(t, err, game.Save_Error.None)
	testing.expect_value(t, game.save_decode(buffer[:size], &decoded), game.Save_Error.None)
	testing.expect_value(t, game.save_restore(&restored, &decoded), game.Save_Error.None)
	for _ in 0..<90 {
		game.update_enemies(&g, game.STEP)
		game.update_enemies(&restored, game.STEP)
	}
	for ordinal in 0..<7 { testing.expect_value(t, g.enemies[rabbit_slot(&g, ordinal)], restored.enemies[rabbit_slot(&restored, ordinal)]) }
}

@(test)
rabbit_lift_escape_works_with_live_teeth_below :: proc(t: ^testing.T) {
	for difficulty in game.Difficulty {
		w: game.World
		game.world_init_ram(&w)
		defer game.world_destroy(&w)
		g := game.State{world = &w, difficulty = difficulty}
		game.init(&g)
		g.player.position = w.checkpoints[4].position
		g.player.invulnerable = 0
		game.mission_checkpoint(&g, 5, g.player.position)
		// Keep ordinary combat active: the pilot only steers, jumps and glides.
		shoot_lift(&g)
		vent := w.vents[w.lift.vent_index].position
		for point in ([4]game.Vec3{vent+{2.4, 0, 5}, vent, vent+{0, 12, 0}, w.checkpoints[5].position}) {
			if !testing.expectf(t, fly_to(&g, point), "%v escape stalled at %v", difficulty, g.player.position) { return }
		}
		testing.expectf(t, g.deaths == 0 && g.kills == 0 && g.enemies[rabbit_slot(&g, 0)].health > 0, "%v: escaping does not require killing the family", difficulty)
	}
}

@(test)
rabbit_bite_is_committed_and_cannot_reach_through_a_wall :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	for wall in ([2]bool{false, true}) {
		flat_world(&g)
		g.player.position, g.player.invulnerable = {0, 0.04, 2}, 0
		if wall { game.add_block(&w, {0, 2, 0.8}, {8, 4, 0.1}) }
		id, _ := game.spawn_enemy(&g, {0, game.enemy_extent(.Rabbit).y+0.04, -2}, 80, 0, .Rabbit)
		e := &g.enemies[id.slot]
		e.phase, e.phase_time, e.attack_direction, e.velocity = .Attack, 0.48, {0, 0, 1}, {0, 0, 21}
		for _ in 0..<45 { game.update_enemies(&g, game.STEP) }
		testing.expect(t, (g.player.health < 100) != wall, "Teeth hit an exposed player but not one behind thin cover")
	}
}

@(test)
gc_exit_has_real_collision_and_needs_no_fan :: proc(t: ^testing.T) {
	w: game.World
	game.world_init_ram(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	c := game.boss_room_origin(&w)
	g.player.position = c+game.Vec3{0, 0.04, 16}
	game.update_boss(&g, game.STEP)
	testing.expect(t, !g.lift_started && g.boss.phase != .Dormant)
	origin := c+game.Vec3{0, 1, -18}
	testing.expect(t, game.world_ray(&w, origin, {0, 0, -1}, 7) < 3)
	fraction, _ := game.world_sweep(&w, origin, {0, 0, -7}, {0.4, 0.8, 0.4})
	testing.expect(t, fraction < 0.3)
	g.boss.health, g.boss.stage = 1, 2
	game.boss_phase(&g.boss, .Exposed, 1)
	g.boss.timer = 0.5
	game.damage_boss(&g, 1, game.boss_core(&w))
	game.boss_exit_sync(&g)
	testing.expect_value(t, w.boss_exit_amount, f32(0))
	for _ in 0..<180 { game.update_boss(&g, game.STEP) }
	game.boss_exit_sync(&g)
	testing.expect_value(t, game.world_ray(&w, origin, {0, 0, -1}, 7), f32(7))
	fraction, _ = game.world_sweep(&w, origin, {0, 0, -7}, {0.4, 0.8, 0.4})
	testing.expect_value(t, fraction, f32(1))
}

@(test)
shot_switch_accepts_all_weapons_and_wind_stops_at_a_roof :: proc(t: ^testing.T) {
	w: game.World
	game.world_init_ram(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	for weapon in game.Weapon {
		game.init(&g)
		g.player.position = w.lift.button+game.Vec3{9, -8, 0}
		for &e in g.enemies[:g.enemy_count] { e.health = 0 }
		g.player.fragment_unlocked, g.player.shotgun_unlocked = true, true
		g.player.fragment_ammo, g.player.shotgun_ammo = 12, 12
		game.aim_at(&g, w.lift.button, false)
		for _ in 0..<12 {
			switch weapon {
			case .Repeater: game.fire(&g, false)
			case .Shotgun: game.fire_shotgun(&g, false)
			case .Fragmentator:
				game.fire_fragment(&g, false)
				for _ in 0..<60 { game.update_fragments(&g, game.STEP) }
			}
			if g.lift_started { break }
		}
		testing.expectf(t, g.lift_started, "%v can activate a visible switch without focusing", weapon)
	}
	v := w.vents[w.lift.vent_index]
	testing.expect(t, game.vent_reaches(&w, v, v.position+game.Vec3{0, 8, 0}))
	game.add_block(&w, v.position+game.Vec3{0, 5, 0}, {8, 0.3, 8})
	testing.expect(t, !game.vent_reaches(&w, v, v.position+game.Vec3{0, 8, 0}))
}

@(test)
gc_door_restore_reconstructs_the_opening_pose_without_rebaking :: proc(t: ^testing.T) {
	w: game.World
	game.world_init_ram(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	g.boss.phase, g.boss.health, g.boss.stage = .Dead, 0, 2
	g.boss.timer, g.boss.duration = game.BOSS_DEATH_DURATION-0.4, game.BOSS_DEATH_DURATION
	game.boss_exit_sync(&g)
	amount, revision := w.boss_exit_amount, w.revision
	data: game.Save_Data
	game.save_capture(&data, &g, .Quick, 1)
	g.boss.timer = 0
	game.boss_exit_sync(&g)
	testing.expect_value(t, game.save_restore(&g, &data), game.Save_Error.None)
	testing.expect(t, w.boss_exit_amount == amount && w.revision == revision)
}

@(test)
rabbit_notices_the_arrival_without_crossing_the_previous_gallery_first :: proc(t: ^testing.T) {
	w: game.World
	game.world_init_ram(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	root := rabbit_slot(&g, 0)
	e := &g.enemies[root]
	c := w.sector.sections[game.room_index(&w.sector, 1017)].origin
	g.player.position = c+game.Vec3{48, 0.04, 0}
	e.sight_timer = 0
	game.enemy_sense(&g, e, root, game.STEP)
	testing.expect(t, !e.alerted)
	g.player.position = w.checkpoints[4].position
	e.sight_timer = 0
	game.enemy_sense(&g, e, root, game.STEP)
	testing.expect(t, e.sees_player && e.alerted, "The rabbit faces the doorway and reacts at the entrance")
}
