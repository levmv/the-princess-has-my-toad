package main

import "core:fmt"
import rl "vendor:raylib"
import game "game"
import settings "settings"
import storage "storage"
import replay "replay"
import front "front"

Play_Session :: struct {
	started, paused, was_focused, just_resumed, fire_guard: bool,
	accumulator: f32,
	input_buffer: game.Input_Buffer,
	history: game.Pose_History,
	checkpoint_sequence: u32,
	cheat: game.Cheat_Entry,
	death: front.Death_Screen,
	tape: ^replay.Tape,
	record_path: string,
}

session_end_record :: proc(s: ^Play_Session, g: ^game.State) -> bool {
	if s.tape == nil || (!s.tape.recording && !s.tape.pending_write) { return true }
	err := replay.flush(s.tape, g, s.record_path)
	if err != .None { fmt.eprintf("RECORD FAILED: %s (%s)\n", replay.error_text(err), s.record_path); return false }
	fmt.printf("RECORD OK: %d ticks (%.2f seconds), build=%s, file=%s\n", s.tape.count, f32(s.tape.count)*game.STEP, game.BUILD_ID, s.record_path)
	return true
}

session_resume :: proc(s: ^Play_Session, g: ^game.State, audio: ^Audio) {
	s.started, s.paused, s.just_resumed, s.fire_guard = true, false, true, true
	s.accumulator, s.input_buffer, s.was_focused = 0, {}, g.focused
	s.cheat = {}
	s.death = {}
	s.checkpoint_sequence = g.checkpoint_sequence
	game.capture_poses(&s.history, g)
	audio_pause(audio); audio_sync(audio, g)
	rl.DisableCursor()
	rl.GetMouseDelta()
}

session_pause :: proc(s: ^Play_Session, audio: ^Audio) {
	s.paused, s.accumulator, s.input_buffer, s.cheat = true, 0, {}, {}
	audio_pause(audio)
	rl.EnableCursor()
}

binding_down :: proc(d: ^settings.Data, action: settings.Action) -> bool {
	key := d.bindings[action]
	return rl.IsMouseButtonDown(rl.MouseButton(-1-key)) if key < 0 else rl.IsKeyDown(rl.KeyboardKey(key))
}

binding_pressed :: proc(d: ^settings.Data, action: settings.Action) -> bool {
	key := d.bindings[action]
	return rl.IsMouseButtonPressed(rl.MouseButton(-1-key)) if key < 0 else key_pressed(rl.KeyboardKey(key))
}

session_input :: proc(s: ^Play_Session, g: ^game.State, prefs: ^settings.Data) -> game.Input {
	input: game.Input
	if s.just_resumed { input.focus = g.focused; return input }
	mouse := rl.GetMouseDelta()
	input.focus = binding_down(prefs, .Scope)
	game.change_focus(g, s.was_focused, input.focus)
	sensitivity := prefs.sensitivity*(0.35 if input.focus else f32(1))
	g.player.yaw += mouse.x*sensitivity
	g.player.pitch = clamp(g.player.pitch+mouse.y*sensitivity*(1 if prefs.invert_y else -1), -1.2, 1.15)
	input.move = {f32(int(binding_down(prefs, .Right))-int(binding_down(prefs, .Left))), f32(int(binding_down(prefs, .Forward))-int(binding_down(prefs, .Backward)))}
	input.jump_held, input.jump_pressed = binding_down(prefs, .Jump), binding_pressed(prefs, .Jump)
	input.dash_pressed, input.interact_pressed, input.kick_pressed = binding_pressed(prefs, .Dash), binding_pressed(prefs, .Use), binding_pressed(prefs, .Kick)
	if !binding_down(prefs, .Fire) { s.fire_guard = false }
	input.fire = !s.fire_guard && (binding_down(prefs, .Fire) || binding_pressed(prefs, .Fire))
	if binding_pressed(prefs, .Repeater) { input.weapon_select = 1 }
	if binding_pressed(prefs, .Fragmentator) { input.weapon_select = 2 }
	if binding_pressed(prefs, .Shotgun) { input.weapon_select = 3 }
	if wheel := rl.GetMouseWheelMove(); wheel != 0 { input.weapon_select = game.cycle_weapon(&g.player, 1 if wheel > 0 else -1) }
	s.cheat.age += min(0.25, rl.GetFrameTime())
	for key in native_events.keys[:native_events.count] {
		if int(key) > 0 && int(key) < 256 && game.cheat_key(&s.cheat, u8(key), 0) { input.anvil_pressed = true }
	}
	return input
}

session_simulate :: proc(s: ^Play_Session, g: ^game.State, input: game.Input, dt: f32, audio: ^Audio) {
	command := input
	command.look, command.has_look = {g.player.yaw, g.player.pitch}, true
	s.was_focused = command.focus
	game.input_push(&s.input_buffer, command)
	s.accumulator += dt
	steps := 0
	for s.accumulator >= game.STEP && steps < 12 {
		playing := s.tape != nil && s.tape.playing
		if playing && s.tape.cursor >= s.tape.count { s.accumulator = 0; break }
		command = game.input_take(&s.input_buffer)
		if playing { command = s.tape.commands[s.tape.cursor]; s.was_focused = command.focus }
		game.capture_poses(&s.history, g)
		deaths := g.deaths
		game.update(g, command, game.STEP)
		if playing { s.tape.cursor += 1 }
		if s.tape != nil { replay.record_tick(s.tape, command, g) }
		s.accumulator -= game.STEP
		steps += 1
		if g.deaths != deaths {
			// A checkpoint rewinds event sequences and positions. Neither audio
			// nor interpolation may interpret the rewind as a new jump or shot.
			audio_pause(audio); audio_sync(audio, g)
			game.capture_poses(&s.history, g)
			s.accumulator, s.was_focused = 0, false
			if !playing {
				front.death_begin(&s.death, g.last_death)
				audio_play(audio, .HurtLora if g.hero == .Lora else .Hurt, 0.9)
				rl.EnableCursor()
			}
			break
		}
		if s.tape != nil && s.tape.recording && s.tape.full { s.accumulator = 0; break }
	}
	if steps == 12 { s.accumulator = 0 }
	if !s.death.active { audio_update(audio, g) }
}

session_death_input :: proc(s: ^Play_Session, g: ^game.State, audio: ^Audio, dt: f32) {
	held, pressed := false, native_events.count > 0
	for key in 1..<512 { held = held || rl.IsKeyDown(rl.KeyboardKey(key)) }
	for button in 0..<7 {
		held = held || rl.IsMouseButtonDown(rl.MouseButton(button))
		pressed = pressed || rl.IsMouseButtonPressed(rl.MouseButton(button))
	}
	if front.death_update(&s.death, dt, rl.IsWindowFocused(), held, pressed) { session_resume(s, g, audio) }
}

session_save :: proc(saves: ^storage.Store, g: ^game.State, slot: storage.Slot, menu: ^Menu_State) -> bool {
	if !saves.enabled { return false }
	start := rl.GetTime()
	err := storage.write(saves, g, slot)
	if err.kind != .None {
		menu_notice(menu, storage.error_text(err), true)
		fmt.eprintf("Save failed (%s): %s / %v\n", saves.paths[slot], storage.error_text(err), err.system)
		return false
	}
	menu_notice(menu, "QUICK SAVED" if slot == .Quick else "CHECKPOINT SAVED")
	fmt.printf("SAVE %v: %.2f ms\n", slot, (rl.GetTime()-start)*1000)
	return true
}

session_load :: proc(s: ^Play_Session, g: ^game.State, audio: ^Audio, saves: ^storage.Store, slot: storage.Slot, menu: ^Menu_State) -> bool {
	if !session_end_record(s, g) { menu_notice(menu, "Could not write input recording.", true); return false }
	err := storage.load(saves, g, slot)
	if err.kind != .None {
		menu_notice(menu, storage.error_text(err), true)
		fmt.eprintf("Load failed (%s): %s / %v\n", saves.paths[slot], storage.error_text(err), err.system)
		return false
	}
	session_resume(s, g, audio)
	menu.page, menu.selected, menu.binding = .Root, 0, -1
	menu_notice(menu, "QUICK SAVE LOADED" if slot == .Quick else "CHECKPOINT LOADED")
	return true
}

apply_preferences :: proc(data, old: ^settings.Data, audio: ^Audio) {
	audio.effects_gain, audio.voice_gain, audio.ambience_gain = data.effects, data.voice, data.ambience
	audio.music_gain = data.music
	if audio.muted != data.muted {
		audio.muted = data.muted
		if audio.ready { rl.SetMasterVolume(0 if data.muted else 0.8) }
	}
	when ODIN_OS != .JS {
		if data.display != old.display { rl.ToggleBorderlessWindowed() }
	}
	when ODIN_OS != .JS {
	if data.display == .Window && (data.width != old.width || data.height != old.height || data.display != old.display) { rl.SetWindowSize(i32(data.width), i32(data.height)) }
	}
}
