package tests

import "core:testing"
import "core:mem"
import "core:os"
import "core:fmt"
import game "../src/game"
import replay "../src/replay"

@(test)
replay_round_trip_reproduces_real_commands_and_rejects_incompatible_data :: proc(t: ^testing.T) {
	w, other: game.World
	game.world_load_sector(&w, .RAM_Combat_Lab, 71)
	game.world_init(&other)
	defer game.world_destroy(&w)
	defer game.world_destroy(&other)
	a, b := game.State{world = &w, difficulty = .Nightmare}, game.State{world = &other}
	game.init(&a); game.init(&b)
	recorded, loaded: replay.Tape
	defer replay.destroy(&recorded)
	defer replay.destroy(&loaded)
	testing.expect_value(t, replay.begin(&recorded, &a, 900), replay.Error.None)
	for i in 0..<900 {
		command := game.Input{has_look = true, look = {0.1, -0.06}, move = {0.3, 1}, fire = i%4 != 0, focus = i > 200 && i < 400, jump_pressed = i%150 == 0, jump_held = i%150 < 30, kick_pressed = i%107 == 0, anvil_pressed = i == 700, weapon_select = 1}
		{
			context.allocator, context.temp_allocator = mem.panic_allocator(), mem.panic_allocator()
			game.update(&a, command, game.STEP)
			replay.record_tick(&recorded, command, &a)
		}
	}
	testing.expect(t, recorded.full)
	testing.expect_value(t, replay.finish(&recorded, &a), replay.Error.None)
	bytes := make([]u8, replay.LIMIT)
	defer delete(bytes)
	n, err := replay.encode(&recorded, bytes)
	testing.expect_value(t, err, replay.Error.None)
	testing.expect_value(t, replay.decode(&loaded, bytes[:n]), replay.Error.None)
	testing.expect_value(t, game.save_restore(&b, loaded.initial), game.Save_Error.None)
	for command in loaded.commands { game.update(&b, command, game.STEP) }
	testing.expect_value(t, replay.verify(&loaded, &b), replay.Error.None)
	saved_equal(t, &a, &b)
	retained := loaded.initial
	bytes[n-1] ~= 1
	testing.expect_value(t, replay.decode(&loaded, bytes[:n]), replay.Error.Checksum)
	testing.expect_value(t, loaded.initial, retained)
	bytes[n-1] ~= 1
	bytes[24] ~= 1
	testing.expect_value(t, replay.decode(&loaded, bytes[:n]), replay.Error.Build)
	bytes[24] ~= 1
	bytes[88] ~= 1
	testing.expect_value(t, replay.decode(&loaded, bytes[:n]), replay.Error.Platform)
	bytes[88] ~= 1
	testing.expect_value(t, replay.decode(&loaded, bytes[:n-1]), replay.Error.Format)
	b.player.health = max(1, b.player.health-1)
	testing.expect_value(t, replay.verify(&loaded, &b), replay.Error.Diverged)
}

@(test)
failed_replay_write_retains_completed_tape_until_retry_succeeds :: proc(t: ^testing.T) {
	directory, err := os.make_directory_temp("", "the-princess-has-my-toad-replay-retry-*", context.allocator)
	testing.expect(t, err == nil)
	defer delete(directory)
	defer os.remove_all(directory)
	path := fmt.aprintf("%s/blocked.nvr", directory)
	defer delete(path)
	testing.expect_value(t, os.mkdir(path), os.Error(nil))
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	tape, loaded: replay.Tape
	defer replay.destroy(&tape)
	defer replay.destroy(&loaded)
	testing.expect_value(t, replay.begin(&tape, &g, 1), replay.Error.None)
	command := game.Input{fire = true}
	game.update(&g, command, game.STEP)
	replay.record_tick(&tape, command, &g)
	hash, hash_err := replay.state_hash(&g)
	testing.expect_value(t, hash_err, replay.Error.None)
	testing.expect_value(t, replay.flush(&tape, &g, path), replay.Error.IO)
	testing.expect(t, !tape.recording && tape.pending_write && tape.end_hash == hash)
	// The live game may advance after a full recording fails to save.
	g.player.health = 1
	testing.expect_value(t, replay.flush(&tape, &g, path), replay.Error.IO)
	testing.expect(t, tape.pending_write && tape.end_hash == hash)
	testing.expect_value(t, os.remove(path), os.Error(nil))
	testing.expect_value(t, replay.flush(&tape, &g, path), replay.Error.None)
	testing.expect(t, !tape.pending_write && !tape.recording)
	testing.expect_value(t, replay.read(&loaded, path), replay.Error.None)
	testing.expect_value(t, loaded.end_hash, hash)
	testing.expect_value(t, game.save_restore(&g, loaded.initial), game.Save_Error.None)
	for c in loaded.commands { game.update(&g, c, game.STEP) }
	testing.expect_value(t, replay.verify(&loaded, &g), replay.Error.None)
	// Once published, subsequent transitions must not rewrite a recording.
	testing.expect_value(t, os.remove(path), os.Error(nil))
	testing.expect_value(t, replay.flush(&tape, &g, path), replay.Error.None)
	testing.expect(t, !os.exists(path))
}

@(test)
failed_replay_finish_cannot_publish_an_invalid_hash :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	tape: replay.Tape
	defer replay.destroy(&tape)
	testing.expect_value(t, replay.begin(&tape, &g, 1), replay.Error.None)
	g.in_step = true
	testing.expect_value(t, replay.finish(&tape, &g), replay.Error.Save)
	testing.expect(t, tape.recording && !tape.pending_write)
	bytes := make([]u8, replay.LIMIT)
	defer delete(bytes)
	_, err := replay.encode(&tape, bytes)
	testing.expect_value(t, err, replay.Error.Format)
	g.in_step = false
	testing.expect_value(t, replay.finish(&tape, &g), replay.Error.None)
	testing.expect(t, !tape.recording && tape.pending_write)
}

@(test)
replay_finishes_at_last_tick_ignoring_later_camera_only_motion :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	tape: replay.Tape
	defer replay.destroy(&tape)
	testing.expect_value(t, replay.begin(&tape, &g, 2), replay.Error.None)
	command := game.Input{look = {0.2, 0.1}, has_look = true}
	game.update(&g, command, game.STEP)
	replay.record_tick(&tape, command, &g)
	hash, err := replay.state_hash(&g)
	testing.expect_value(t, err, replay.Error.None)
	g.player.yaw, g.player.pitch, g.focused = 0.7, 0.3, true
	testing.expect_value(t, replay.finish(&tape, &g), replay.Error.None)
	testing.expect_value(t, tape.end_hash, hash)
}
