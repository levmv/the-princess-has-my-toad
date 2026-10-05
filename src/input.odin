package main

import rl "vendor:raylib"

Native_Events :: struct {
	pressed: [512]bool,
	keys: [32]rl.KeyboardKey,
	count: int,
}
native_events: Native_Events

// Raylib's state comparison can miss a complete press/release pair during a
// slow frame (or a save). Its key queue preserves the press event itself.
// Drain once, then share the same frame's edges between menu and game actions.
poll_key_events :: proc() {
	native_events = {}
	for {
		key := rl.GetKeyPressed()
		if key == .KEY_NULL { break }
		index := int(key)
		if index > 0 && index < len(native_events.pressed) { native_events.pressed[index] = true }
		if native_events.count < len(native_events.keys) {
			native_events.keys[native_events.count] = key
			native_events.count += 1
		}
	}
}

key_pressed :: proc(key: rl.KeyboardKey) -> bool {
	index := int(key)
	return index > 0 && index < len(native_events.pressed) && native_events.pressed[index]
}
