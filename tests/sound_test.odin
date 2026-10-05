package tests

import "core:testing"
import "core:math"
import "core:mem"
import game "../src/game"

@(test)
spatial_cues_follow_listener_and_occlusion_without_consuming_rng :: proc(t: ^testing.T) {
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	flat_world(&g)
	left, left_pan := game.sound_projection(&w, &g.player, {-6, 1.5, 0})
	right, right_pan := game.sound_projection(&w, &g.player, {6, 1.5, 0})
	testing.expect(t, left == right && left_pan < -0.8 && right_pan > 0.8)
	g.player.yaw = math.PI
	_, turned := game.sound_projection(&w, &g.player, {6, 1.5, 0})
	testing.expect(t, turned < -0.8)
	game.add_block(&w, {3, 3, 0}, {0.1, 6, 10})
	game.world_commit(&w)
	blocked, _ := game.sound_projection(&w, &g.player, {6, 1.5, 0})
	testing.expect(t, blocked > 0 && blocked < right*0.4)
	far, _ := game.sound_projection(&w, &g.player, {60, 1.5, 0})
	testing.expect_value(t, far, f32(0))
	rng, effects := g.rng, g.effect_rng
	{
		context.allocator = mem.panic_allocator()
		context.temp_allocator = mem.panic_allocator()
		for i in 0..<150 { game.sound_event(&g, .CrabCharge, {f32(i), 0, 0}) }
	}
	testing.expect(t, g.rng == rng && g.effect_rng == effects && g.sound_sequence == 150)
	for sequence in u32(23)..=150 {
		e := g.sound_events[(sequence-1)%u32(len(g.sound_events))]
		testing.expect(t, e.sequence == sequence && e.position.x == f32(sequence-1))
	}
}
