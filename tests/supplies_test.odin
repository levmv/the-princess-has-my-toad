package tests

import "core:testing"
import game "../src/game"

lower_guard :: proc(id: game.Object_ID) -> bool {
	return id >= game.room_object_id(1004, 0x102) && id <= game.room_object_id(1004, 0x104)
}

@(test)
lower_supplies_have_cover_ground_guards_and_a_walkable_escape :: proc(t: ^testing.T) {
	w: game.World
	game.world_init_ram(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	s := w.sector.sections[game.room_index(&w.sector, 1004)]
	guards := 0
	for e in g.enemies[:g.enemy_count] {
		if !lower_guard(e.content_id) { continue }
		guards += 1
		testing.expect(t, game.enemy_grounded_kind(e.kind))
		for viewpoint in ([4]game.Vec3{{-4, 11.5, 13}, {4, 11.5, 13}, {0, 8.5, -22}, {0, 11.5, -41}}) {
			eye := game.ram_local(s, viewpoint)
			delta := e.position-eye
			testing.expectf(t, game.world_ray(&w, eye, game.normalized(delta), game.length(delta)) < game.length(delta)-0.1, "Lower guard exposed from %v", viewpoint)
		}
	}
	testing.expect_value(t, guards, 3)
	for &e in g.enemies { if !lower_guard(e.content_id) { e.health = 0 } }
	g.player.position = game.ram_local(s, {10, 0.04, -22})
	for _ in 0..<420 {
		game.update(&g, {}, game.STEP)
		if g.player.health < 100 || g.deaths > 0 { break }
	}
	testing.expect(t, g.player.health < 100 || g.deaths > 0, "The lower guards must actually threaten a player beside the supplies")
	game.init(&g)
	for &e in g.enemies { e.health = 0 }
	g.player.health, g.player.shotgun_unlocked, g.player.shotgun_ammo = 30, true, 0
	g.player.position = game.ram_local(s, {0, 0.04, -10})
	for point in ([7]game.Vec3{{10, 0, -11}, {10, 0, -22}, {3, 0, -23}, {-3, 0, -25}, {4, 0, -22}, {10, 0, -22}, {12, 0, -7}}) {
		if !testing.expectf(t, walk_to_grounded(&g, game.ram_local(s, point)), "Supply path blocked at %v, target %v", g.player.position, point) { return }
	}
	testing.expect(t, g.player.health > 30 && g.player.shotgun_ammo > 0 && g.deaths == 0)
	testing.expect(t, walk_to_grounded(&g, game.ram_local(s, {12, 10, 34})))
}

@(test)
perch_weapon_and_stair_recess_rewards_are_collectible :: proc(t: ^testing.T) {
	w: game.World
	game.world_init_ram(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	for &e in g.enemies { e.health = 0 }
	s := w.sector.sections[game.room_index(&w.sector, 1005)]
	g.player.position = s.origin+game.Vec3{-21, 0.04, 3}
	game.update_pickups(&g)
	testing.expect(t, !g.player.fragment_unlocked)
	for p in ([5]game.Vec3{{-18, 1.3, 8}, {-14, 2.8, 11}, {-10, 4.3, 14}, {-4, 5.5, 18}, {0, 5.5, 18}}) {
		if !testing.expect(t, fly_to(&g, s.origin+p)) { return }
	}
	testing.expect(t, g.player.fragment_unlocked && g.player.fragment_ammo > 0)
	s = w.sector.sections[game.room_index(&w.sector, 1006)]
	g.player.position, g.player.velocity, g.player.health = s.origin+game.Vec3{0, 0.04, 19}, {}, 20
	game.update(&g, {}, game.STEP) // Commit the entrance checkpoint's healing first.
	g.player.health = 20
	for p in ([4]game.Vec3{{6, 0, -13}, {11, 0, -12.5}, {15, 0, -17}, {6, 0, -13}}) {
		if !testing.expectf(t, walk_to_grounded(&g, s.origin+p), "Stair recess blocked: %v", g.player.position) { return }
	}
	testing.expect_value(t, g.player.health, f32(80))
}
