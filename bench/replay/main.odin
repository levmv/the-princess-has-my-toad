package replay_check

import "core:fmt"
import "core:mem"
import "core:os"
import game "../../src/game"
import replay "../../src/replay"

main :: proc() {
	assert(len(os.args) == 2, "Pass the path of a .nvr recording")
	tape: replay.Tape
	defer replay.destroy(&tape)
	if err := replay.read(&tape, os.args[1]); err != .None { fmt.eprintln(replay.error_text(err)); os.exit(1) }
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	assert(game.save_restore(&g, tape.initial) == .None)
	for command in tape.commands {
		context.allocator, context.temp_allocator = mem.panic_allocator(), mem.panic_allocator()
		game.update(&g, command, game.STEP)
	}
	err := replay.verify(&tape, &g)
	fmt.printf("%s ticks=%d sector=%v seed=%d difficulty=%v kills=%d deaths=%d hp=%.1f build=%s\n", replay.error_text(err), tape.count, w.sector.key, w.seed, g.difficulty, g.kills, g.deaths, g.player.health, game.BUILD_ID)
	assert(err == .None)
}
