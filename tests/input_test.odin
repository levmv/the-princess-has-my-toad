package tests

import "core:testing"
import game "../src/game"

@(test)
short_presses_survive_frames_without_a_tick_and_are_consumed_once :: proc(t: ^testing.T) {
	b: game.Input_Buffer
	// A click and release at a high render rate may both precede the next tick.
	game.input_push(&b, {fire = true, jump_pressed = true, jump_held = true, kick_pressed = true, weapon_select = 3})
	game.input_push(&b, {dash_pressed = true, interact_pressed = true, anvil_pressed = true, weapon_select = 2})
	game.input_push(&b, {move = {1, 0}, has_look = true, look = {1.2, -0.2}, focus = true})
	command := game.input_take(&b)
	testing.expect(t, command.fire && command.jump_pressed && command.kick_pressed && command.dash_pressed && command.interact_pressed && command.anvil_pressed)
	testing.expect(t, command.weapon_select == 2 && !command.jump_held, "The latest weapon request and held state win")
	testing.expect(t, command.move == game.Vec2{1, 0} && command.has_look && command.look == game.Vec2{1.2, -0.2} && command.focus)
	for _ in 0..<12 {
		command = game.input_take(&b)
		testing.expect(t, !command.fire && !command.jump_pressed && !command.kick_pressed && !command.dash_pressed && !command.interact_pressed && !command.anvil_pressed && command.weapon_select == 0, "Catch-up ticks must not repeat a released press")
		testing.expect(t, command.move == game.Vec2{1, 0} && command.focus)
	}
}

@(test)
held_fire_continues_across_ticks_and_a_session_reset_discards_pending_input :: proc(t: ^testing.T) {
	b: game.Input_Buffer
	game.input_push(&b, {fire = true, jump_pressed = true, jump_held = true})
	for step in 0..<12 {
		command := game.input_take(&b)
		testing.expect(t, command.fire && command.jump_held && command.jump_pressed == (step == 0))
	}
	game.input_push(&b, {fire = true, interact_pressed = true, weapon_select = 2})
	b = {}
	testing.expect_value(t, game.input_take(&b), game.Input{})
}
