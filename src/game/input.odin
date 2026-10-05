package game

// Frame input and simulation ticks run at different rates. Keep the latest
// held state, but preserve presses until one tick consumes them. No queue or
// allocation is needed; repeated presses before a tick coalesce into one.
Input_Buffer :: struct { held, pending: Input }

input_push :: proc(b: ^Input_Buffer, input: Input) {
	b.held = input
	b.pending.jump_pressed = b.pending.jump_pressed || input.jump_pressed
	b.pending.dash_pressed = b.pending.dash_pressed || input.dash_pressed
	b.pending.interact_pressed = b.pending.interact_pressed || input.interact_pressed
	b.pending.kick_pressed = b.pending.kick_pressed || input.kick_pressed
	b.pending.anvil_pressed = b.pending.anvil_pressed || input.anvil_pressed
	b.pending.fire = b.pending.fire || input.fire
	if input.weapon_select != 0 { b.pending.weapon_select = input.weapon_select }
}

input_take :: proc(b: ^Input_Buffer) -> Input {
	command := b.held
	command.jump_pressed, command.dash_pressed = b.pending.jump_pressed, b.pending.dash_pressed
	command.interact_pressed, command.kick_pressed = b.pending.interact_pressed, b.pending.kick_pressed
	command.anvil_pressed, command.weapon_select = b.pending.anvil_pressed, b.pending.weapon_select
	command.fire = command.fire || b.pending.fire
	b.pending = {}
	return command
}
