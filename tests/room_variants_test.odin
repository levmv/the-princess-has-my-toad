package tests

import "core:testing"
import "core:mem"
import "core:math"
import game "../src/game"

@(test)
room_variants_change_real_lanes_and_restore_explicit_choices :: proc(t: ^testing.T) {
	seen_gallery: [2]bool
	for seed in u32(0)..<32 {
		w, restored: game.World
		game.world_init_ram(&w, seed)
		defer game.world_destroy(&w)
		defer game.world_destroy(&restored)
		game.world_build_ram(&restored, w.sector, seed)
		for b, i in w.blocks { testing.expect_value(t, b, restored.blocks[i]) }
		testing.expect_value(t, w.room_navigation, restored.room_navigation)
		for &s, index in w.sector.sections[:w.sector.count] {
			testing.expect(t, s.variant != .Auto)
			if s.id == 1002 { seen_gallery[0 if s.variant == .Weave else 1] = true }
			if s.id == 1014 { testing.expect(t, s.variant == .Authored) }
			n := &w.room_navigation[index]
			for p, i in n.points[:n.count] {
				testing.expectf(t, game.room_at(&w.sector, p) == index, "Room %d has an out-of-room navigation corner %v", s.id, p)
				for kind in game.Enemy_Kind {
					if kind == .Rabbit && s.id != 1017 { continue } // The adult belongs to the large lift chamber.
					testing.expectf(t, n.links[kind][i] != 0, "Room %d has an isolated corner %d for %v", s.id, i, kind)
				}
			}
		}
	}
	testing.expect(t, seen_gallery[0] && seen_gallery[1])
	// The crosswise-rack gallery breaks this firing lane; the spine gallery
	// opens the same flank all the way through. This is geometry, not metadata.
	r := game.ram_cold_boot()
	i := game.room_index(&r, 1002)
	for variant in ([2]game.Room_Variant{.Weave, .Split}) {
		r.sections[i].variant = variant
		w: game.World
		game.world_build_ram(&w, r, 42)
		defer game.world_destroy(&w)
		p := r.sections[i].origin+game.Vec3{10, 1.5, 35}
		distance := game.world_ray(&w, p, {0, 0, -1}, 65)
		testing.expect(t, distance < 12 if variant == .Weave else distance == 65)
	}
}

@(test)
large_ground_enemies_route_around_baffles_and_memory_racks :: proc(t: ^testing.T) {
	for id in ([2]game.Room_ID{1002, 1014}) {
		for variant in ([2]game.Room_Variant{.Weave, .Split}) {
			r := game.ram_cold_boot()
			index := game.room_index(&r, id)
			r.sections[index].variant = variant
			s := r.sections[index]
			w: game.World
			game.world_build_ram(&w, r, 42)
			defer game.world_destroy(&w)
			g := game.State{world = &w}
			game.init(&g)
			for &e in g.enemies { e.health = 0 }
			g.player.position = s.origin+game.Vec3{0, 0.04, -s.depth*0.5+4}
			g.player.invulnerable = 1000
			handle, ok := game.spawn_enemy(&g, s.origin+game.Vec3{0, game.enemy_extent(.Crab).y+0.04, s.depth*0.5-4}, 8, 100, .Crab)
			testing.expect(t, ok)
			e := game.find_enemy(&g, handle)
			e.alerted, e.memory_time, e.last_known = true, 600, g.player.position+game.Vec3{0, 0.9, 0}
			{
				context.allocator = mem.panic_allocator()
				context.temp_allocator = mem.panic_allocator()
				for _ in 0..<6000 {
					game.update_enemies(&g, game.STEP)
					if game.length(e.position-g.player.position) < 5 { break }
				}
			}
			testing.expectf(t, game.length(e.position-g.player.position) < 5, "%d / %v: pursuing crab got stuck at %v, goal %v", id, variant, e.position, e.nav_goal)
		}
	}
}

@(test)
missing_the_first_glide_has_a_real_return_ramp :: proc(t: ^testing.T) {
	w: game.World
	game.world_init_ram(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	for &e in g.enemies { e.health = 0 }
	s := w.sector.sections[game.room_index(&w.sector, 1004)]
	g.player.position = game.ram_local(s, {0, 10.04, 13})
	g.player.yaw = math.PI*0.5
	for _ in 0..<60 { game.update(&g, {}, game.STEP) }
	for tick in 0..<180 { game.update(&g, game.Input{move = {0, 1}, jump_pressed = tick == 0, jump_held = true}, game.STEP) }
	testing.expect(t, g.player.position.y < -9.5 && g.deaths == 0, "A missed crossing lands on the maintenance floor")
	for point in ([4]game.Vec3{{12, 0, -7}, {12, 10, 34}, {0, 10, 34}, {0, 10, 13}}) {
		if !testing.expectf(t, walk_to_grounded(&g, game.ram_local(s, point)), "Return ramp blocked at %v, target %v", g.player.position, point) { return }
	}
	for _ in 0..<60 { game.update(&g, {}, game.STEP) }
	wings := g.glide_sequence
	if !testing.expectf(t, fly_to(&g, game.ram_local(s, {0, 7, -21.5})), "Wing crossing failed at %v", g.player.position) { return }
	testing.expect(t, g.deaths == 0 && g.glide_sequence > wings && g.player.position.y > -3.5)
	testing.expect(t, fly_to(&g, game.ram_local(s, {0, 10, -41})))
}

@(test)
first_bridge_exit_is_walkable_without_jumping :: proc(t: ^testing.T) {
	w: game.World
	game.world_init_ram(&w)
	defer game.world_destroy(&w)
	s := w.sector.sections[game.room_index(&w.sector, 1004)]
	for offset in ([3]f32{-2.3, 0, 2.3}) {
		g := game.State{world = &w}
		game.init(&g)
		for &e in g.enemies { e.health = 0 }
		g.player.position = game.ram_local(s, {offset, 7.04, -22})
		for _ in 0..<60 { game.update(&g, {}, game.STEP) }
		target := game.ram_local(s, {offset, 10, -46})
		testing.expectf(t, walk_to_grounded(&g, target), "Bridge exit blocked at %v, target %v", g.player.position, target)
		for _ in 0..<60 { game.update(&g, {}, game.STEP) }
		target = game.ram_local(s, {-offset, 7, -22})
		testing.expectf(t, walk_to_grounded(&g, target), "Return to bridge blocked at %v, target %v", g.player.position, target)
		testing.expect(t, g.jump_sequence == 0 && g.glide_sequence == 0 && g.deaths == 0)
	}
}

walk_to_grounded :: proc(g: ^game.State, target: game.Vec3) -> bool {
	for _ in 0..<1800 {
		delta := target-g.player.position
		distance := game.length(game.Vec3{delta.x, 0, delta.z})
		if distance < 0.45 && abs(delta.y) < 0.35 { return true }
		g.player.yaw = math.atan2(delta.x, -delta.z)
		game.update(g, {move = {0, min(1, distance*2)}}, game.STEP)
		if g.deaths > 0 { return false }
	}
	return false
}

@(test)
charge_columns_and_courtyard_perches_are_reachable_with_real_flight :: proc(t: ^testing.T) {
	w: game.World
	game.world_init_ram(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	for &e in g.enemies { e.health = 0 }
	s := w.sector.sections[game.room_index(&w.sector, 1011)]
	g.player.position = s.origin+game.CHARGE_LANDINGS[0]+game.Vec3{0, 0.04, 0}
	for p in game.CHARGE_LANDINGS {
		if !testing.expectf(t, fly_to(&g, s.origin+p), "Column %v unreachable from %v", p, g.player.position) { return }
	}
	testing.expect(t, g.deaths == 0 && g.glide_sequence >= 4, "The crossing actually uses the wing")
	// The space between supports has no floor. The central chip blocks a
	// direct shot between the launch and receiving stations.
	testing.expect(t, game.world_ray(&w, s.origin+game.Vec3{25, 20, 25}, {0, -1, 0}, 60) == 60)
	a, b := s.origin+game.CHARGE_LANDINGS[0]+game.Vec3{0, 1.5, 0}, s.origin+game.CHARGE_LANDINGS[5]+game.Vec3{0, 1.5, 0}
	testing.expect(t, game.world_ray(&w, a, game.normalized(b-a), game.length(b-a)) < game.length(b-a)-1)
	// A longer glide can skip a landing on either side of the obstruction.
	// The route therefore need not become six compulsory little jumps.
	g.player.position, g.player.velocity = s.origin+game.CHARGE_LANDINGS[0]+game.Vec3{0, 0.04, 0}, {}
	g.player.gliding, g.player.grounded = false, false
	for _ in 0..<60 { game.update(&g, {}, game.STEP) }
	for landing in ([3]int{2, 3, 5}) {
		if !testing.expectf(t, fly_to(&g, s.origin+game.CHARGE_LANDINGS[landing]), "Long glide to %d failed at %v", landing, g.player.position) { return }
	}
	// The optional upper combat route is accessed by normal jumps, then glides
	// around the capacitor. There is also still a broad route on the ground.
	s = w.sector.sections[game.room_index(&w.sector, 1005)]
	g.player.position, g.player.velocity = s.origin+game.Vec3{-21, 0.04, 3}, {}
	g.player.gliding, g.player.grounded = false, false
	for p in ([7]game.Vec3{{-18, 1.3, 8}, {-14, 2.8, 11}, {-10, 4.3, 14}, {-4, 5.5, 18}, {18, 3.8, 9}, {18, 3.8, -3}, {10, 2, -19}}) {
		if !testing.expectf(t, fly_to(&g, s.origin+p), "Courtyard perch %v unreachable from %v", p, g.player.position) { return }
	}
	testing.expect(t, fly_to(&g, s.origin+game.Vec3{0, 0, -24}) && g.deaths == 0)
	// The serious fall is recoverable from a checkpoint at the launch lip;
	// it must not send the player back through the approach and courtyard.
	game.init(&g)
	for &e in g.enemies { e.health = 0 }
	checkpoint := w.checkpoints[2]
	// The save volume must cover the outer edge too, not just the centre line.
	g.player.position, g.player.velocity = checkpoint.position+game.Vec3{0, 0, 9}, {}
	game.update(&g, {}, game.STEP)
	testing.expect_value(t, g.checkpoint_id, checkpoint.id)
	g.player.position = w.sector.sections[game.room_index(&w.sector, 1011)].origin+game.Vec3{25, 20, 25}
	for _ in 0..<240 {
		game.update(&g, {}, game.STEP)
		if g.deaths > 0 { break }
	}
	testing.expect(t, g.deaths == 1 && game.length(g.player.position-checkpoint.position) < 0.1)
}
