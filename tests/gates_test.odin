package tests

import "core:testing"
import "core:mem"
import game "../src/game"

@(test)
secret_gate_blocks_every_physical_query_and_opens_without_static_rebuild :: proc(t: ^testing.T) {
	w: game.World
	game.world_init_ram(&w, 42)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	revision := w.revision
	start := game.Vec3{-14, 0.85, -123}
	testing.expect(t, game.world_ray(&w, start, {-1, 0, 0}, 4) < 4)
	fraction, _ := game.world_sweep(&w, start, {-4, 0, 0}, {0.36, 0.825, 0.36})
	testing.expect(t, fraction < 0.5)
	g.player.position = {-17, 0, -119}
	g.player.yaw = 1.5707963
	game.update_gates(&g, game.Input{interact_pressed = true}, game.STEP)
	testing.expect(t, !w.gates[0].open, "The control cannot be used through its enclosure from the near side")
	g.player.position = w.gates[0].control+game.Vec3{2, -1.3, 0}
	g.player.yaw = -1.5707963
	{
		context.allocator = mem.panic_allocator()
		context.temp_allocator = mem.panic_allocator()
		game.update_gates(&g, game.Input{interact_pressed = true}, game.STEP)
		for _ in 0..<90 { game.update_gates(&g, {}, game.STEP) }
	}
	testing.expect(t, w.gates[0].open && w.gates[0].amount == 1 && w.revision == revision)
	testing.expect_value(t, game.world_ray(&w, start, {-1, 0, 0}, 4), f32(4))
	fraction, _ = game.world_sweep(&w, start, {-4, 0, 0}, {0.36, 0.825, 0.36})
	testing.expect_value(t, fraction, f32(1))
	game.respawn(&g)
	testing.expect(t, w.gates[0].open)
	game.init(&g)
	testing.expect(t, !w.gates[0].open && w.gates[0].amount == 0)
	// A player who reached the door's top must not be lifted into the ceiling.
	w.gates[0].open = true
	g.player.position = w.gates[0].closed.center+game.Vec3{0, w.gates[0].closed.size.y*0.5+0.001, 0}
	game.update_gates(&g, {}, game.STEP)
	testing.expect_value(t, w.gates[0].amount, f32(0))
	// Secret identities remain stable and a second visit cannot award one twice.
	g.player.position = {-34, 0, -124}
	game.update_secrets(&g)
	game.update_secrets(&g)
	testing.expect(t, g.secret_count == 1 && g.secrets[0] == game.room_object_id(1021, 0x500))
	game.respawn(&g)
	testing.expect_value(t, g.secret_count, 1)
	game.init(&g)
	testing.expect_value(t, g.secret_count, 0)
}
