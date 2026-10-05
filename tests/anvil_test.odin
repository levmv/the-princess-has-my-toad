package tests

import "core:testing"
import "core:mem"
import game "../src/game"

@(test)
iddqd_recognition_requires_the_sequence_and_expires :: proc(t: ^testing.T) {
	e: game.Cheat_Entry
	text := "IIDXIDDQIDDQD"
	for key, i in text {
		found := game.cheat_key(&e, u8(key), 0.1)
		testing.expect_value(t, found, i == len(text)-1)
	}
	for key in "IDD" { game.cheat_key(&e, u8(key), 0.1) }
	testing.expect(t, !game.cheat_key(&e, 'Q', 4))
	testing.expect(t, !game.cheat_key(&e, 'D', 0.1))
	for key, i in "iddqd" { testing.expect_value(t, game.cheat_key(&e, u8(key), 0.1), i == 4) }
}

@(test)
anvil_gives_time_to_dodge_and_damages_only_once :: proc(t: ^testing.T) {
	for dodge in ([2]bool{false, true}) {
		w: game.World
		game.world_init_ram(&w)
		defer game.world_destroy(&w)
		g := game.State{world = &w}
		game.init(&g)
		game.update(&g, {anvil_pressed = true}, game.STEP)
		target := g.anvil.target
		testing.expect(t, g.anvil.phase == .Warning && g.anvil.timer > 1.1 && !game.drop_anvil(&g))
		{
			context.allocator, context.temp_allocator = mem.panic_allocator(), mem.panic_allocator()
			for i in 0..<420 {
				game.update(&g, {move = {1 if dodge && i < 55 else 0, 0}}, game.STEP)
				if g.anvil.phase != .Idle { testing.expect_value(t, g.anvil.target, target) }
			}
		}
		testing.expect_value(t, g.anvil.phase, game.Anvil_Phase.Idle)
		testing.expect_value(t, g.player.health, f32(100 if dodge else 65))
		testing.expect_value(t, g.damage_sequence, u32(0 if dodge else 1))
		testing.expect(t, g.deaths == 0 && g.kills == 0 && g.checkpoint_id == 0)
	}
}

@(test)
anvil_falling_save_resumes_but_death_clears_the_joke :: proc(t: ^testing.T) {
	w, loaded: game.World
	game.world_init_ram(&w); game.world_init_ram(&loaded)
	defer game.world_destroy(&w); defer game.world_destroy(&loaded)
	a, b := game.State{world = &w}, game.State{world = &loaded}
	game.init(&a); game.init(&b)
	game.drop_anvil(&a)
	for _ in 0..<160 {
		game.update(&a, {}, game.STEP)
		if a.anvil.phase == .Falling && a.anvil.speed > 2 { break }
	}
	testing.expect_value(t, a.anvil.phase, game.Anvil_Phase.Falling)
	data, decoded: game.Save_Data
	bytes: [game.SAVE_LIMIT]u8
	game.save_capture(&data, &a, .Quick, 1)
	n, err := game.save_encode(&data, bytes[:])
	testing.expect_value(t, err, game.Save_Error.None)
	testing.expect_value(t, game.save_decode(bytes[:n], &decoded), game.Save_Error.None)
	testing.expect_value(t, game.save_restore(&b, &decoded), game.Save_Error.None)
	for _ in 0..<210 { game.update(&a, {}, game.STEP); game.update(&b, {}, game.STEP) }
	saved_equal(t, &a, &b)
	game.drop_anvil(&b); game.respawn(&b)
	testing.expect(t, b.anvil.phase == .Idle && b.player.health == 100)
	// A ceiling too close to give a readable drop rejects the joke safely.
	game.add_block(&loaded, b.player.position+game.Vec3{0, 2.1, 0}, {6, 0.2, 6})
	testing.expect(t, !game.drop_anvil(&b))
}
