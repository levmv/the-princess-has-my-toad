package tests

import "core:testing"
import game "../src/game"

@(test)
difficulties_change_encounters_resources_and_pressure_with_a_real_dodge_window :: proc(t: ^testing.T) {
	w: game.World
	game.world_init_ram(&w, 42)
	defer game.world_destroy(&w)
	hard := game.State{world = &w, difficulty = .Hard}
	night := game.State{world = &w, difficulty = .Nightmare}
	game.init(&hard)
	game.init(&night)
	testing.expect(t, night.enemy_total == hard.enemy_total && night.pickup_count == hard.pickup_count)
	different := 0
	for enemy, i in hard.enemies[:hard.enemy_count] {
		other := night.enemies[i]
		testing.expect(t, enemy.content_id == other.content_id && enemy.position == other.position)
		testing.expect(t, other.health > enemy.health && other.health <= enemy.health+6)
		if other.kind != enemy.kind { different += 1 }
	}
	testing.expect(t, different >= 2 && night.pickups[0].amount < hard.pickups[0].amount)
	// The rush commits for 200 ms on every difficulty. A lateral move after
	// commitment must avoid actual contact even with the faster Nightmare dash.
	for difficulty in game.Difficulty {
		g := game.State{world = &w, difficulty = difficulty}
		flat_world(&g)
		_, ok := game.spawn_enemy(&g, {0, 1, -8}, 10, 0, .Interceptor)
		testing.expect(t, ok)
		e := &g.enemies[0]
		for _ in 0..<90 { game.update_enemies(&g, game.STEP); if e.phase == .Windup && e.phase_time <= 0.19 { break } }
		testing.expect(t, e.windup_duration >= 0.57 && e.phase == .Windup)
		for _ in 0..<100 {
			game.update_player(&g, game.Input{move = {1, 0}}, game.STEP)
			game.update_enemies(&g, game.STEP)
		}
		testing.expectf(t, g.player.health == 100, "%v rush cannot be dodged with a real strafe", difficulty)
		testing.expect(t, e.position.z > -1 && e.phase == .Recover, "The dodge check must include an actual completed rush")
	}
}

@(test)
pickups_respect_capacity_walls_and_single_collection :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	flat_world(&g)
	g.pickup_count = 1
	g.pickups[0] = {1, {0.9, 0.75, 0}, .Health, 30, false}
	game.update_pickups(&g)
	testing.expect(t, !g.pickups[0].collected)
	g.player.health = 60
	game.add_block(&w, {0.5, 2, 0}, {0.1, 4, 4})
	game.world_commit(&w)
	game.update_pickups(&g)
	testing.expect(t, !g.pickups[0].collected && g.player.health == 60)
	game.clear_blocks(&w)
	game.world_commit(&w)
	game.update_pickups(&g)
	game.update_pickups(&g)
	testing.expect(t, g.player.health == 90 && g.pickup_sequence == 1)
	g.pickups[0] = {2, {0.9, 0.75, 0}, .Launcher, 4, false}
	g.player.fragment_unlocked = true
	g.player.fragment_ammo = game.FRAGMENT_AMMO_MAX
	game.update_pickups(&g)
	testing.expect(t, !g.pickups[0].collected)
	g.player.fragment_ammo -= 2
	game.update_pickups(&g)
	testing.expect(t, g.pickups[0].collected && g.player.fragment_unlocked && g.player.fragment_ammo == game.FRAGMENT_AMMO_MAX)
	game.capture_checkpoint(&g)
	g.player.fragment_ammo -= 3
	game.respawn(&g)
	testing.expect(t, g.pickups[0].collected && g.player.fragment_unlocked && g.player.fragment_ammo == game.FRAGMENT_AMMO_MAX, "Checkpoint restores the spent ammo and its collected reward together")
}

@(test)
authored_supplies_have_real_clearance_and_reachable_floor :: proc(t: ^testing.T) {
	for sector in ([2]game.Sector_ID{.RAM_Bank_01, .RAM_Combat_Lab}) {
		for seed in u32(0)..<16 {
			w: game.World
			game.world_load_sector(&w, sector, seed)
			defer game.world_destroy(&w)
			for pickup in w.pickup_spawns[:w.pickup_count] {
				drop := game.world_ray(&w, pickup.position, {0, -1, 0}, 4)
				testing.expectf(t, drop > 0.3 && drop < 0.9, "Pickup %v has no nearby floor: %v", pickup.id, pickup.position)
				for &block in w.blocks {
					inside := true
					for face in 0..<6+block.clip_count {
						plane := game.block_plane(&block, face)
						support := (abs(plane.normal.x)+abs(plane.normal.y)+abs(plane.normal.z))*0.35
						if game.dot(plane.normal, pickup.position)-plane.distance > support { inside = false; break }
					}
					testing.expectf(t, !inside, "Pickup %v intersects a solid at %v", pickup.id, pickup.position)
				}
			}
		}
	}
}
