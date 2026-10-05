package tests

import "core:testing"
import "core:mem"
import "core:math"
import game "../src/game"

// Aim through the actual camera/muzzle path, keeping the weapon cone enabled.
shoot_lift :: proc(g: ^game.State) {
	game.aim_at(g, g.world.lift.button, true)
	for _ in 0..<12 {
		game.fire(g, true)
		if g.lift_started { return }
	}
}

@(test)
shot_lift_latches_and_does_not_accept_shots_through_walls :: proc(t: ^testing.T) {
	w: game.World
	game.world_init_ram(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	g.player.position = w.checkpoints[4].position
	game.capture_checkpoint(&g)
	vent := w.vents[w.lift.vent_index]
	for _ in 0..<3 {
		g.player.position = vent.position+game.Vec3{0, 3, 0}
		g.player.gliding = true
		game.update_player(&g, {jump_held = true}, game.STEP)
		testing.expect(t, !g.lift_started && !g.player.in_current && g.player.velocity.y < 0, "An unpowered fan cannot lift the player")
		game.respawn(&g)
		testing.expect(t, !g.lift_started && !g.restart.run.lift_started, "Respawning alone must not switch on the fan")
	}
	g.player.position = w.checkpoints[4].position
	for &e in g.enemies[:g.enemy_count] { e.health = 0 }
	shoot_lift(&g)
	testing.expect(t, g.lift_started, "The high button is hittable from the entrance")
	sequence := g.sound_sequence
	shoot_lift(&g)
	testing.expect_value(t, g.sound_sequence, sequence)
	game.respawn(&g)
	testing.expect(t, g.lift_started && g.enemies[0].health > 0, "Latch the fan without saving mid-fight damage")
	game.init(&g)
	g.player.position = w.checkpoints[4].position
	for &e in g.enemies[:g.enemy_count] { e.health = 0 }
	game.add_block(&w, w.lift.button+game.Vec3{2, 0, 0}, {1, 8, 8})
	shoot_lift(&g)
	testing.expect(t, !g.lift_started, "Solid cover stops the shot before the target")
}

@(test)
lift_power_and_exit_do_not_require_a_kill_count :: proc(t: ^testing.T) {
	w: game.World
	game.world_init_ram(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	g.player.position = w.vents[w.lift.vent_index].position+game.Vec3{0, 3, 0}
	g.player.gliding = true
	game.update_player(&g, game.Input{jump_held = true}, game.STEP)
	testing.expect(t, !g.player.in_current && g.player.velocity.y < 0)
	g.lift_started = true
	for _ in 0..<40 { game.update_player(&g, game.Input{jump_held = true}, game.STEP) }
	testing.expect(t, g.player.in_current && g.player.velocity.y > 2, "Power changes the falling glide into an ascent")
	g.player.position = w.exit
	g.player.velocity = {}
	game.update(&g, {}, game.STEP)
	testing.expect(t, !g.won, "The authored collector, rather than an ordinary kill quota, controls the final exit")
	g.boss.phase, g.boss.health, g.boss.stage = .Dead, 0, 2
	game.update(&g, {}, game.STEP)
	testing.expect(t, g.won && g.kills == 0, "Avoiding the ordinary patrols remains a legitimate way to the final encounter")
}

@(test)
sector_layouts_keep_spawn_clearance_and_are_reproducible :: proc(t: ^testing.T) {
	for seed in u32(0)..<32 {
		a, b: game.World
		game.world_init_ram(&a, seed)
		game.world_init_ram(&b, seed)
		defer game.world_destroy(&a)
		defer game.world_destroy(&b)
		testing.expect_value(t, len(a.blocks), len(b.blocks))
		for block, i in a.blocks { testing.expect_value(t, block, b.blocks[i]) }
		for &group, index in a.encounters {
			testing.expect_value(t, group, b.encounters[index])
			for spawn in group.spawns[:group.count] {
				extent := game.enemy_extent(spawn.kind)
				for &block in a.blocks {
					inside := true
					for plane in 0..<6+block.clip_count {
						p := game.block_plane(&block, plane)
						support := abs(p.normal.x)*extent.x+abs(p.normal.y)*extent.y+abs(p.normal.z)*extent.z
						if game.dot(p.normal, spawn.position)-p.distance > support { inside = false; break }
					}
					testing.expectf(t, !inside, "Seed %d embeds %v in geometry at %v", seed, spawn.kind, spawn.position)
				}
			}
		}
	}
}

@(test)
sector_simulation_stays_allocation_free_and_does_not_spawn_rounds :: proc(t: ^testing.T) {
	w: game.World
	game.world_init_ram(&w, 42)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	total := g.enemy_total
	testing.expect_value(t, total, 50)
	{
		context.allocator = mem.panic_allocator()
		context.temp_allocator = mem.panic_allocator()
		for i in 0..<3600 {
			game.update(&g, game.Input{fire = i%4 == 0, move = {0, 1}, jump_pressed = i%180 == 0}, game.STEP)
		}
	}
	testing.expect(t, g.enemy_total == total, "All groups exist from load; no endless reinforcements")
}

@(test)
ram_main_route_is_a_chain_with_only_short_secret_branches :: proc(t: ^testing.T) {
 r := game.ram_cold_boot()
 testing.expect(t, r.connection_count == r.count-1, "No return loops")
 for room in r.sections[:r.count] {
  main_degree, secret_degree := 0, 0
  for link in r.connections[:r.connection_count] {
   if link.a != room.id && link.b != room.id { continue }
   other := link.b if link.a == room.id else link.a
   if r.sections[game.room_index(&r, other)].intent == .Secret { secret_degree += 1 } else { main_degree += 1 }
  }
  if room.intent == .Secret { testing.expect(t, main_degree == 1 && secret_degree == 0)
  } else if room.intent == .Arrival || room.intent == .Finale { testing.expect(t, main_degree == 1)
  } else { testing.expectf(t, main_degree == 2 && secret_degree <= 1, "Room %d introduces a main-route fork", room.id) }
 }
 testing.expect(t, r.sections[game.room_index(&r, 1013)].door_count == 2)
}

@(test)
ram_route_is_traversable_with_normal_controls :: proc(t: ^testing.T) {
	seeds := [4]u32{0, 42, game.DEFAULT_SEED, 0xFFFFFFFF}
	for seed in seeds {
		w: game.World
		game.world_init_ram(&w, seed)
		defer game.world_destroy(&w)
		g := game.State{world = &w}
		game.init(&g)
		// Isolate traversal, as in the original arena pilot. Ordinary combat and the GC fight are tested separately.
		g.boss.phase, g.boss.health, g.boss.stage = .Dead, 0, 2
		for &enemy in g.enemies { enemy.health = 0 }
		path := []game.Room_ID{1001, 1002, 1003, 1004, 1005, 1006, 1010, 1011, 1012, 1013, 1014, 1015, 1016, 1017, 1018, 1019, 1020}
		for index in 0..<len(path)-1 {
			from, to := w.sector.sections[game.room_index(&w.sector, path[index])], w.sector.sections[game.room_index(&w.sector, path[index+1])]
			if from.id == 1003 {
				control := w.gates[0].control
				if !testing.expect(t, fly_to(&g, control+game.Vec3{2, -1.3, 0})) { return }
				g.player.yaw = -math.PI*0.5
				game.update(&g, game.Input{interact_pressed = true}, game.STEP)
				for _ in 0..<90 { game.update(&g, {}, game.STEP) }
				testing.expect(t, w.gates[0].open && w.gates[0].amount == 1)
				visit := [6]game.Vec3{{-7, 0, -15}, {-14, 0, -15}, {-14, 0, -9}, {-18, 0, -9}, {-34, 0, -6}, {-34, 0, -10}}
				for point in visit { if !testing.expectf(t, fly_to(&g, from.origin+point), "First secret approach failed at %v", g.player.position) { return } }
				testing.expect_value(t, g.secret_count, 1)
				for step in 0..<len(visit) { if !testing.expect(t, fly_to(&g, from.origin+visit[len(visit)-1-step])) { return } }
			}
			if from.id == 1018 {
				if !testing.expect(t, walk_room_to(&g, from, from.origin+game.Vec3{16, 0, 0})) { return }
				visit := [3]game.Vec3{{19.5, 0, 0}, {30, 0, -3}, {19.5, 0, 0}}
				for point in visit { if !testing.expectf(t, fly_to(&g, from.origin+point), "Second secret approach failed at %v", g.player.position) { return } }
				if !testing.expect(t, fly_to(&g, from.origin+game.Vec3{16, 0, 0})) { return }
				testing.expect_value(t, g.secret_count, 2)
			}
			portal: game.Vec3
			found := false
			for link in w.sector.connections[:w.sector.connection_count] {
				if (link.a == from.id && link.b == to.id) || (link.b == from.id && link.a == to.id) { portal, found = link.position, true; break }
			}
			if !testing.expect(t, found) { return }
			x_axis := abs(to.origin.x-from.origin.x) > abs(to.origin.z-from.origin.z)
			after := portal
			if x_axis { after.x += 1.5 if to.origin.x > from.origin.x else -1.5 } else { after.z += 1.5 if to.origin.z > from.origin.z else -1.5 }
			if from.role == .Air_Lift {
				shoot_lift(&g)
				testing.expect(t, g.lift_started)
				vent := w.vents[w.lift.vent_index].position
				lift := []game.Vec3{vent+{2.4, 0, 5}, vent, vent+{0, 14, 0}}
				for target in lift { if !testing.expectf(t, fly_to(&g, target), "Lift approach failed at %v", g.player.position) { return } }
			} else if from.role == .Branch_Landing && portal.y > from.origin.y+1 {
				for p in ([4]game.Vec3{{12, 0, 19}, {12, 6, -4}, {16, 6, -4}, {16, 6, 0}}) {
					if !testing.expectf(t, fly_to(&g, from.origin+p), "Ramp failed at %v", g.player.position) { return }
				}
			} else if from.role == .Address_Bridge {
				if !testing.expectf(t, cross_bridge(&g, from), "Seed %d: bridge %d failed at %v", seed, from.id, g.player.position) { return }
			} else if from.role == .Charge_Causeway {
				for p in game.CHARGE_LANDINGS {
					if !testing.expectf(t, fly_to(&g, from.origin+p), "Seed %d: aerial landing %v failed at %v", seed, p, g.player.position) { return }
				}
			} else {
				if !testing.expectf(t, walk_room_to(&g, from, portal), "Seed %d: room %d approach failed at %v", seed, from.id, g.player.position) { return }
			}
			waypoints := [2]game.Vec3{portal, after}
			for target in waypoints {
				if !testing.expectf(t, fly_to(&g, target), "Seed %d: connection %d -> %d failed, target=%v player=%v", seed, path[index], path[index+1], target, g.player.position) { return }
			}
		}
		// The collector reservoir is solid: go around its left side.
		c := game.boss_room_origin(&w)
		for p in ([4]game.Vec3{{-8, 0, 14}, {-8, 0, -18}, {0, 0, -18}, {0, 0, -25}}) { if !testing.expect(t, fly_to(&g, c+p)) { return } }
		testing.expect(t, g.won && g.deaths == 0)
	}
}

// Follow the selected room's physically verified corners, then let the normal
// movement controller handle every turn. No path point teleports the player.
walk_room_to :: proc(g: ^game.State, room: game.Section_Recipe, target: game.Vec3) -> bool {
	index := game.room_index(&g.world.sector, room.id)
	offset := game.Vec3{0, game.enemy_extent(.Crab).y+0.04, 0}
	for _ in 0..<24 {
		point, ok := game.enemy_room_goal(g.world, index, g.player.position+offset, target+offset, .Crab)
		if !ok || !fly_to(g, point-offset) { return false }
		if game.length(point-offset-target) < 0.1 { return true }
	}
	return false
}

cross_bridge :: proc(g: ^game.State, room: game.Section_Recipe) -> bool {
	span := max(room.width, room.depth)
	length := (span-18)/4
	local_z := -(g.player.position.x-room.origin.x) if room.width > room.depth else g.player.position.z-room.origin.z
	direction := 1 if local_z > 0 else -1
	for step in 0..<4 {
		i := step if direction == 1 else 3-step
		z := span*0.5-length*0.5-f32(i)*(length+6)
		x := f32(1 if i == 1 else -1)*1.5 if i == 1 || i == 2 else 0
		if !fly_to(g, game.ram_local(room, {x, 6, z})) { return false }
		if step < 3 {
			if !fly_to(g, game.ram_local(room, {x, 6, z-f32(direction)*(length*0.5-1.1)})) { return false }
			next := i+direction
			next_z := span*0.5-length*0.5-f32(next)*(length+6)
			next_x := f32(1 if next == 1 else -1)*1.5 if next == 1 || next == 2 else 0
			if !fly_to(g, game.ram_local(room, {next_x, 6, next_z+f32(direction)*(length*0.5-1.1)})) { return false }
		}
	}
	return true
}
