package settings

import "core:encoding/json"
import "core:fmt"
import "core:strings"
import storage "../storage"
import game "../game"
import loc "../locale"

VERSION :: u32(2)
FILE_LIMIT :: 16*1024
Action :: enum { Forward, Backward, Left, Right, Jump, Dash, Fire, Scope, Use, Kick, Repeater, Fragmentator, Quick_Save, Quick_Load, Shotgun }
Display :: enum { Window, Borderless }

// Bindings use raylib/GLFW's stable key numbers. Negative values select mouse
// buttons (-1 is left, -2 is right); this package has no graphics dependency.
Data :: struct {
	version: u32,
	sensitivity, effects, voice, ambience, music: f32,
	render_scale: f32,
	invert_y, muted: bool,
	wing_hint_seen: bool,
	display: Display,
	width, height: int,
	difficulty: game.Difficulty,
	hero: game.Character,
	language: loc.Language,
	bindings: [Action]int,
}
Store :: struct { data: Data, directory, path: string, enabled, dirty: bool, error: storage.Error }

defaults :: proc() -> Data {
	return {version = VERSION, sensitivity = 0.0023, effects = 1, voice = 1, ambience = 0.55, music = 0.55, render_scale = 1, width = 1280, height = 800,
		bindings = {.Forward = 'W', .Backward = 'S', .Left = 'A', .Right = 'D', .Jump = 32, .Dash = 340, .Fire = -1, .Scope = -2, .Use = 'E', .Kick = 'F', .Repeater = '1', .Fragmentator = '3', .Quick_Save = 294, .Quick_Load = 298, .Shotgun = '2'}}
}

action_name :: proc(action: Action) -> string {
	switch action {
	case .Forward: return "FORWARD"
	case .Backward: return "BACKWARD"
	case .Left: return "STRAFE LEFT"
	case .Right: return "STRAFE RIGHT"
	case .Jump: return "JUMP / WING"
	case .Dash: return "DASH"
	case .Fire: return "FIRE"
	case .Scope: return "SCOPE"
	case .Use: return "USE"
	case .Kick: return "KICK"
	case .Repeater: return "REPEATER"
	case .Fragmentator: return "FRAGMENTATOR"
	case .Shotgun: return "SHOTGUN"
	case .Quick_Save: return "QUICK SAVE"
	case .Quick_Load: return "QUICK LOAD"
	}
	unreachable()
}

valid_binding :: proc(key: int) -> bool {
	// Escape, Enter, M, F3 and F11 remain accessible for menus, mute, diagnostics
	// and fullscreen even after movement controls have been reassigned.
	if key == 256 || key == 257 || key == 'M' || key == 292 || key == 300 { return false }
	return (key >= -7 && key <= -1) || key == 32 || key == 39 || (key >= 44 && key <= 57) || key == 59 || key == 61 || (key >= 'A' && key <= 'Z') || (key >= 91 && key <= 93) || key == 96 || (key >= 258 && key <= 269) || (key >= 290 && key <= 301) || (key >= 320 && key <= 336) || (key >= 340 && key <= 347)
}

bind :: proc(d: ^Data, action: Action, key: int) -> bool {
	if !valid_binding(key) { return false }
	old := d.bindings[action]
	for other in Action { if other != action && d.bindings[other] == key { d.bindings[other] = old } }
	d.bindings[action] = key
	return true
}

valid :: proc(d: ^Data) -> bool {
	if d.version != VERSION || !(d.sensitivity >= 0.0002 && d.sensitivity <= 0.012) { return false }
	if !(d.effects >= 0 && d.effects <= 1 && d.voice >= 0 && d.voice <= 1 && d.ambience >= 0 && d.ambience <= 1) { return false }
	if !(d.music >= 0 && d.music <= 1) { return false }
	if !(d.render_scale >= 0.5 && d.render_scale <= 1) { return false }
	if d.display < .Window || d.display > .Borderless || d.width < 960 || d.width > 7680 || d.height < 600 || d.height > 4320 { return false }
	if d.language < .English || d.language > .Russian || d.hero < .Duke || d.hero > .Lora { return false }
	if d.difficulty < .Hard || d.difficulty > .Nightmare { return false }
	for action in Action {
		if !valid_binding(d.bindings[action]) { return false }
		for other in Action { if other < action && d.bindings[action] == d.bindings[other] { return false } }
	}
	return true
}

init :: proc(s: ^Store, override: string = "", enabled: bool = true) {
	s.data, s.enabled = defaults(), enabled
	if !enabled { return }
	s.directory = strings.clone(override) if len(override) > 0 else storage.default_directory(config = true)
	if len(s.directory) == 0 { s.enabled = false; return }
	s.path = fmt.aprintf("%s/settings.json", s.directory)
	bytes: [FILE_LIMIT]u8
	size, err := storage.read_bounded(s.path, bytes[:])
	if err.kind == .Missing { return }
	if err.kind != .None { s.error = err; return }
	candidate := defaults()
	// Current partial files inherit defaults; absent/old versions are rejected.
	// This prototype deliberately has no settings migration path.
	candidate.version = 0
	decode_err := json.unmarshal(bytes[:size], &candidate)
	if decode_err != nil || !valid(&candidate) { s.error = {kind = .Format, format = .Value}; return }
	s.data = candidate
}

flush :: proc(s: ^Store) -> storage.Error {
	if !s.enabled || !s.dirty { return {} }
	if !valid(&s.data) { return {kind = .Format, format = .Value} }
	bytes, err := json.marshal(s.data)
	if err != nil { return {kind = .Format, format = .Value} }
	defer delete(bytes)
	s.error = storage.atomic_write(s.directory, s.path, bytes)
	if s.error.kind == .None { s.dirty = false }
	return s.error
}

destroy :: proc(s: ^Store) {
	delete(s.directory); delete(s.path)
	s^ = {}
}
