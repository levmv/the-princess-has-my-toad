package tests

import "core:testing"
import "core:mem"
import game "../src/game"

@(test)
content_rejects_broken_connections_duplicate_ids_and_missing_anchors :: proc(t: ^testing.T) {
	r := game.ram_cold_boot()
	error, _ := game.validate_sector(&r)
	testing.expect_value(t, error, game.Content_Error.None)
	r.sections[1].id = r.sections[0].id
	error, _ = game.validate_sector(&r)
	testing.expect_value(t, error, game.Content_Error.Room_ID)
	r = game.ram_cold_boot()
	r.sections[3].origin.x += 2
	error, _ = game.validate_sector(&r)
	testing.expect(t, error != .None, "Moving a room away from its portal must invalidate the recipe")
	r = game.ram_cold_boot()
	r.connections[0].width -= 1
	error, _ = game.validate_sector(&r)
	testing.expect_value(t, error, game.Content_Error.Connection)
	r = game.ram_cold_boot()
	r.exit.room = 65000
	error, _ = game.validate_sector(&r)
	testing.expect_value(t, error, game.Content_Error.Location)
	r = game.ram_cold_boot()
	r.mechanism_room = r.sections[0].id
	error, _ = game.validate_sector(&r)
	testing.expect_value(t, error, game.Content_Error.Mechanism)
	r = game.ram_transfer()
	game.sector_room(&r, 65000, .Junction, {100, 0, 100}, 10, 10, 5)
	error, _ = game.validate_sector(&r)
	testing.expect_value(t, error, game.Content_Error.Disconnected)
	r = game.ram_cold_boot()
	r.checkpoints[1].id = r.checkpoints[0].id
	error, _ = game.validate_sector(&r)
	testing.expect_value(t, error, game.Content_Error.Checkpoint)
}

@(test)
room_storage_order_does_not_move_authored_anchors_or_generated_objects :: proc(t: ^testing.T) {
	first := game.ram_cold_boot()
	reordered := first
	for i in 0..<first.count { reordered.sections[i] = first.sections[first.count-1-i] }
	error, _ := game.validate_sector(&reordered)
	if !testing.expect_value(t, error, game.Content_Error.None) { return }
	a, b: game.World
	game.world_build_ram(&a, first, 42)
	game.world_build_ram(&b, reordered, 42)
	defer game.world_destroy(&a)
	defer game.world_destroy(&b)
	testing.expect_value(t, a.spawn, b.spawn)
	testing.expect_value(t, a.exit, b.exit)
	testing.expect_value(t, a.lift, b.lift)
	testing.expect_value(t, a.checkpoints, b.checkpoints)
	testing.expect_value(t, len(a.blocks), len(b.blocks))
	for &group in a.encounters {
		for spawn in group.spawns[:group.count] {
			matches := 0
			for &other in b.encounters {
				for candidate in other.spawns[:other.count] {
					if spawn.id == candidate.id {
						matches += 1
						testing.expect_value(t, spawn, candidate)
					}
				}
			}
			testing.expect_value(t, matches, 1)
		}
	}
	// Trace cover and shell surfaces, not only the room metadata.
	for i in 0..<first.count {
		s := first.sections[i]
		for height in 0..<3 {
			p := s.origin+game.Vec3{0, 1+f32(height)*2, 0}
			for dx in -2..<3 {
				for dz in -2..<3 {
					direction := game.normalized(game.Vec3{f32(dx), -0.3, f32(dz)})
					testing.expect_value(t, game.world_ray(&a, p, direction, 100), game.world_ray(&b, p, direction, 100))
				}
			}
		}
	}
}

@(test)
campaign_transition_rebuilds_world_and_keeps_completion :: proc(t: ^testing.T) {
	w: game.World
	game.world_load_sector(&w, .RAM_Bank_01, 42)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	revision := w.revision
	testing.expect(t, !game.advance_campaign(&g) && w.revision == revision, "A live sector cannot be skipped by continuing")
	g.lift_started = true
	// This fixture starts after the separately exercised boss encounter.
	g.boss.phase, g.boss.health, g.boss.stage = .Dead, 0, 2
	g.player.position = w.exit
	{
		context.allocator = mem.panic_allocator()
		context.temp_allocator = mem.panic_allocator()
		game.update(&g, {}, game.STEP)
	}
	testing.expect(t, g.won && g.campaign.current == .RAM_Bank_01)
	completed := g.campaign.completed
	testing.expect(t, completed != 0)
	g.player.health, g.player.fragment_unlocked, g.player.fragment_ammo, g.player.weapon = 65, true, 7, .Fragmentator
	testing.expect(t, game.advance_campaign(&g))
	testing.expect(t, g.player.health == 65 && g.player.fragment_unlocked && g.player.fragment_ammo == 7 && g.player.weapon == .Fragmentator, "The sector transition keeps the player's resources and weapon")
	testing.expect(t, w.revision > revision && w.sector.key == .RAM_Transfer && w.seed == 42)
	testing.expect(t, g.campaign.current == .RAM_Transfer && g.campaign.completed == completed && !g.won)
	testing.expect(t, len(w.vents) == 0 && len(w.encounters) == 0 && w.checkpoint_count == 0, "The previous sector's content must not leak into the next one")
	testing.expect(t, w.sector.mechanism == .None && !g.lift_started)
	game.init(&g)
	testing.expect_value(t, g.campaign.completed, completed)
	// Traverse the transfer room with the same controller as the full route.
	for link in w.sector.connections[:w.sector.connection_count] { testing.expect(t, fly_to(&g, link.position)) }
	testing.expect(t, fly_to(&g, w.exit) && g.won)
	testing.expect(t, game.campaign_next(&g) == .None && !game.advance_campaign(&g))
	testing.expect_value(t, g.campaign.completed, completed)
}

@(test)
early_ram_views_cannot_shoot_late_encounters :: proc(t: ^testing.T) {
	w: game.World
	game.world_init_ram(&w, 42)
	defer game.world_destroy(&w)
	starts := [3]game.Vec3{w.spawn, w.sector.sections[1].origin, w.sector.sections[2].origin}
	for p in starts {
		for height in 0..<5 {
			eye := p+game.Vec3{0, game.EYE_HEIGHT+f32(height)*0.5, 0}
			for &group in w.encounters {
				if group.room < 1015 { continue }
				for spawn in group.spawns[:group.count] {
					delta := spawn.position-eye
					distance := game.length(delta)
					testing.expect(t, game.world_ray(&w, eye, game.normalized(delta), distance) < distance-1, "Early grounded, jumping and scoped views must be occluded from the final encounters")
				}
			}
		}
	}
}
