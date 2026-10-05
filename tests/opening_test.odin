package tests

import "core:testing"
import game "../src/game"

@(test)
ram_introduces_enemy_roles_in_order_on_every_difficulty :: proc(t: ^testing.T) {
	for seed in u32(0)..<32 {
		w: game.World
		game.world_init_ram(&w, seed)
		defer game.world_destroy(&w)
		for difficulty in ([3]game.Difficulty{.Hard, .Brutal, .Nightmare}) {
			g := game.State{world = &w, difficulty = difficulty}
			game.init(&g)
			first: [game.Enemy_Kind]game.Room_ID
			arrival, gallery, court_ground := 0, 0, 0
			for e in g.enemies[:g.enemy_count] {
				room := w.encounters[e.encounter-1].room
				if first[e.kind] == 0 { first[e.kind] = room }
				if room == 1001 { arrival += 1 }
				if room == 1002 { gallery += 1 }
				if room == 1005 && game.enemy_grounded_kind(e.kind) { court_ground += 1 }
			}
			testing.expect_value(t, first[.Interceptor], game.Room_ID(1001))
			testing.expect_value(t, first[.Crab], game.Room_ID(1002))
			testing.expect_value(t, first[.Sentry], game.Room_ID(1004))
			testing.expect_value(t, first[.Kettle], game.Room_ID(1005))
			testing.expect_value(t, first[.Nanny], game.Room_ID(1015))
			testing.expect(t, arrival == 1 && gallery == 2 && court_ground == 3,
				"Difficulty changes pressure without replacing the opening's authored ground enemies")
		}
	}
}

@(test)
arrival_gives_control_before_first_fairy_engages :: proc(t: ^testing.T) {
	w: game.World
	game.world_init_ram(&w, 42)
	defer game.world_destroy(&w)
	g := game.State{world = &w, difficulty = .Nightmare}
	game.init(&g)
	for _ in 0..<600 { game.update(&g, {}, game.STEP) }
	testing.expect_value(t, g.player.health, f32(100))
	for e in g.enemies[:g.enemy_count] {
		testing.expect(t, !e.alerted, "No enemy should start attacking a player who has not left the arrival")
	}
	for _ in 0..<130 { game.update(&g, {move = {0, 1}}, game.STEP) }
	testing.expect(t, g.enemies[0].alerted, "Walking forward naturally starts the first encounter")
}
