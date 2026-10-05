package replay

import "core:mem"
import "base:intrinsics"
import game "../game"
import storage "../storage"

VERSION :: u32(1)
MAX_TICKS :: 120*60*30
COMMAND_SIZE :: 24
HEADER_SIZE :: 112
LIMIT :: HEADER_SIZE+game.SAVE_LIMIT+MAX_TICKS*COMMAND_SIZE
#assert(intrinsics.type_struct_field_count(game.Input) == 12, "Update replay commands/version when Input changes")

Error :: enum { None, Busy, Format, Version, Build, Platform, Checksum, Save, IO, Limit, Diverged }
Tape :: struct {
	initial: ^game.Save_Data,
	commands: []game.Input,
	count, cursor: int,
	recording, playing, full: bool,
	pending_write: bool,
	end_hash: u32,
	last_look: game.Vec2,
	last_focus: bool,
}

error_text :: proc(err: Error) -> string {
	switch err {
	case .None: return "Replay OK."
	case .Busy: return "Cannot capture a replay during a simulation tick."
	case .Format: return "Malformed or truncated replay."
	case .Version: return "Unsupported replay version."
	case .Build: return "Replay belongs to a different source/compiler build."
	case .Platform: return "Replay belongs to a different platform."
	case .Checksum: return "Replay checksum does not match."
	case .Save: return "Replay's initial save is invalid or incompatible."
	case .IO: return "Could not read or atomically write replay."
	case .Limit: return "Replay exceeds the 30 minute command limit."
	case .Diverged: return "Replay's final state differs from the recorded run."
	}
	unreachable()
}

destroy :: proc(t: ^Tape) {
	free(t.initial)
	delete(t.commands)
	t^ = {}
}

begin :: proc(t: ^Tape, g: ^game.State, capacity: int = MAX_TICKS) -> Error {
	if capacity <= 0 || capacity > MAX_TICKS { return .Limit }
	if g.in_step { return .Busy }
	destroy(t)
	t.initial = new(game.Save_Data)
	if game.save_capture(t.initial, g, .Quick, 0) != .None { destroy(t); return .Save }
	t.commands = make([]game.Input, capacity)
	t.recording = true
	t.last_look, t.last_focus = {g.player.yaw, g.player.pitch}, g.focused
	return .None
}

// Called AFTER the recorded simulation tick. The preallocated command array is
// the only write; no file IO, encoding, hashing or allocation occurs here.
record_tick :: proc(t: ^Tape, command: game.Input, g: ^game.State) {
	if !t.recording { return }
	assert(t.count < len(t.commands))
	t.commands[t.count] = command
	t.count += 1
	t.full = t.count == len(t.commands)
	t.last_look, t.last_focus = {g.player.yaw, g.player.pitch}, g.focused
}

state_hash :: #force_no_inline proc(g: ^game.State) -> (u32, Error) {
	data: game.Save_Data
	bytes: [game.SAVE_LIMIT]u8
	if game.save_capture(&data, g, .Quick, 0) != .None { return 0, .Save }
	n, err := game.save_encode(&data, bytes[:])
	if err != .None { return 0, .Save }
	return game.save_checksum(bytes[:n]), .None
}

finish :: #force_no_inline proc(t: ^Tape, g: ^game.State) -> Error {
	if !t.recording { return .None }
	// Mouse look can change on a rendered frame with no fixed tick. The replay
	// ends at its last tick, not at that later presentation-only camera pose.
	last := g^
	last.player.yaw, last.player.pitch, last.focused = t.last_look.x, t.last_look.y, t.last_focus
	hash, err := state_hash(&last)
	if err != .None { return err }
	t.end_hash, t.recording, t.pending_write = hash, false, true
	return .None
}

// A failed write retains the completed recording. Retrying must neither lose
// it nor replace its end hash with the state of a later simulation tick.
flush :: proc(t: ^Tape, g: ^game.State, path: string) -> Error {
	if !t.recording && !t.pending_write { return .None }
	if err := finish(t, g); err != .None { return err }
	return write(t, path)
}

verify :: proc(t: ^Tape, g: ^game.State) -> Error {
	hash, err := state_hash(g)
	if err != .None { return err }
	return .None if hash == t.end_hash else .Diverged
}

command_codec :: proc(c: ^game.Save_Cursor, input: ^game.Input) {
	game.save_field(c, &input.move); game.save_field(c, &input.look)
	flags := u32(int(input.has_look)) | u32(int(input.jump_pressed))<<1 | u32(int(input.jump_held))<<2 | u32(int(input.dash_pressed))<<3 | u32(int(input.fire))<<4 | u32(int(input.focus))<<5 | u32(int(input.interact_pressed))<<6 | u32(int(input.kick_pressed))<<7 | u32(int(input.anvil_pressed))<<8
	game.save_field(c, &flags); game.save_field(c, &input.weapon_select)
	if flags & ~u32(511) != 0 || input.weapon_select < 0 || input.weapon_select > 3 || abs(input.move.x) > 1 || abs(input.move.y) > 1 || abs(input.look.x) > 1e6 || input.look.y < -1.2 || input.look.y > 1.15 { c.error = .Value; return }
	if c.reading {
		input.has_look, input.jump_pressed, input.jump_held = flags&1 != 0, flags&2 != 0, flags&4 != 0
		input.dash_pressed, input.fire, input.focus = flags&8 != 0, flags&16 != 0, flags&32 != 0
		input.interact_pressed, input.kick_pressed, input.anvil_pressed = flags&64 != 0, flags&128 != 0, flags&256 != 0
	}
}

platform_tag :: proc() -> string { return "linux-amd64" when ODIN_OS == .Linux && ODIN_ARCH == .amd64 else ("web-wasm32" when ODIN_OS == .JS else "other") }

encode :: #force_no_inline proc(t: ^Tape, bytes: []u8) -> (int, Error) {
	if t.initial == nil || t.recording || t.count < 0 || t.count > len(t.commands) || t.count > MAX_TICKS { return 0, .Format }
	if len(bytes) < HEADER_SIZE { return 0, .Format }
	mem.zero(raw_data(bytes), HEADER_SIZE)
	save_size, err := game.save_encode(t.initial, bytes[HEADER_SIZE:])
	if err != .None { return 0, .Save }
	size := HEADER_SIZE+save_size+t.count*COMMAND_SIZE
	if size > len(bytes) { return 0, .Limit }
	c := game.Save_Cursor{bytes = bytes, at = HEADER_SIZE+save_size}
	for &command in t.commands[:t.count] { command_codec(&c, &command) }
	if c.error != .None { return 0, .Format }
	h := game.Save_Cursor{bytes = bytes}
	magic, version, count, save_count := u32(0x5249564E), VERSION, u32(t.count), u32(save_size)
	checksum := game.save_checksum(bytes[HEADER_SIZE:size])
	game.save_field(&h, &magic); game.save_field(&h, &version); game.save_field(&h, &count); game.save_field(&h, &save_count)
	game.save_field(&h, &t.end_hash); game.save_field(&h, &checksum)
	assert(len(game.BUILD_ID) <= 64)
	copy(bytes[24:88], game.BUILD_ID)
	copy(bytes[88:104], platform_tag())
	h.at = 104
	step, reserved := game.STEP, u32(0)
	game.save_field(&h, &step); game.save_field(&h, &reserved)
	return size, .None
}

tag_matches :: proc(bytes: []u8, value: string) -> bool {
	if len(value) > len(bytes) || string(bytes[:len(value)]) != value { return false }
	for b in bytes[len(value):] { if b != 0 { return false } }
	return true
}

decode :: #force_no_inline proc(t: ^Tape, bytes: []u8) -> Error {
	if len(bytes) < HEADER_SIZE || len(bytes) > LIMIT { return .Format }
	h := game.Save_Cursor{bytes = bytes, reading = true}
	magic, version, count, save_size, end_hash, checksum := u32(0), u32(0), u32(0), u32(0), u32(0), u32(0)
	game.save_field(&h, &magic); game.save_field(&h, &version); game.save_field(&h, &count); game.save_field(&h, &save_size)
	game.save_field(&h, &end_hash); game.save_field(&h, &checksum)
	if magic != 0x5249564E { return .Format }
	if version != VERSION { return .Version }
	if count > MAX_TICKS || save_size > game.SAVE_LIMIT { return .Limit }
	if int(save_size)+int(count)*COMMAND_SIZE+HEADER_SIZE != len(bytes) { return .Format }
	if !tag_matches(bytes[24:88], game.BUILD_ID) { return .Build }
	if !tag_matches(bytes[88:104], platform_tag()) { return .Platform }
	h.at = 104
	step, reserved := f32(0), u32(0)
	game.save_field(&h, &step); game.save_field(&h, &reserved)
	if step != game.STEP || reserved != 0 { return .Version }
	if game.save_checksum(bytes[HEADER_SIZE:]) != checksum { return .Checksum }
	candidate: Tape
	defer destroy(&candidate)
	candidate.initial = new(game.Save_Data)
	if game.save_decode(bytes[HEADER_SIZE:HEADER_SIZE+int(save_size)], candidate.initial) != .None { return .Save }
	candidate.commands = make([]game.Input, int(count))
	candidate.count, candidate.end_hash = int(count), end_hash
	c := game.Save_Cursor{bytes = bytes, at = HEADER_SIZE+int(save_size), reading = true}
	for &command in candidate.commands { command_codec(&c, &command) }
	if c.error != .None { return .Format }
	destroy(t)
	t^, candidate = candidate, {}
	return .None
}

read :: proc(t: ^Tape, path: string) -> Error {
	bytes := make([]u8, LIMIT)
	defer delete(bytes)
	n, err := storage.read_bounded(path, bytes)
	if err.kind != .None { return .IO }
	return decode(t, bytes[:n])
}

write :: proc(t: ^Tape, path: string) -> Error {
	bytes := make([]u8, LIMIT)
	defer delete(bytes)
	n, err := encode(t, bytes)
	if err != .None { return err }
	directory := parent_directory(path)
	if len(directory) == 0 { directory = "." }
	if storage.atomic_write(directory, path, bytes[:n]).kind != .None { return .IO }
	t.pending_write = false
	return .None
}
