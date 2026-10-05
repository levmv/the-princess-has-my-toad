package storage

import "core:fmt"
import "core:strings"
import "core:time"
import game "../game"

Slot :: enum { Checkpoint, Quick }
Error_Kind :: enum { None, Missing, Directory, Open, Read, Write, Sync, Rename, Format, Disabled }
Error :: struct { kind: Error_Kind, format: game.Save_Error, system: System_Error }
Slot_Info :: struct { exists, valid: bool, stamp: u64, sector: game.Sector_ID, difficulty: game.Difficulty, error: Error }
Store :: struct { directory: string, paths: [Slot]string, slots: [Slot]Slot_Info, stamp: u64, enabled: bool }

error_text :: proc(err: Error) -> string {
	switch err.kind {
	case .None: return "Saved."
	case .Missing: return "No save in this slot."
	case .Directory: return "Cannot create the save directory."
	case .Open: return "Cannot open the save file."
	case .Read: return "Could not read the complete file."
	case .Write: return "Save write failed; the previous file is intact."
	case .Sync: return "Disk sync failed; save durability is unconfirmed."
	case .Rename: return "Cannot replace the save file."
	case .Format: return game.save_error_text(err.format)
	case .Disabled: return "Saving is disabled for this test launch."
	}
	unreachable()
}

init :: proc(s: ^Store, override: string = "", enabled: bool = true) {
	s.enabled = enabled
	if !enabled { return }
	s.directory = strings.clone(override) if len(override) > 0 else default_directory()
	if len(s.directory) == 0 { s.enabled = false; return }
	s.paths[.Checkpoint] = fmt.aprintf("%s/checkpoint.nvs", s.directory)
	s.paths[.Quick] = fmt.aprintf("%s/quick.nvs", s.directory)
	refresh(s)
}

destroy :: proc(s: ^Store) {
	for path in s.paths { delete(path) }
	delete(s.directory)
	s^ = {}
}

// Reads never allocate a buffer from an untrusted on-disk length.
read_save :: #force_no_inline proc(path: string, out: ^game.Save_Data) -> Error {
	bytes: [game.SAVE_LIMIT]u8
	size, err := read_bounded(path, bytes[:])
	if err.kind != .None { return err }
	if format := game.save_decode(bytes[:size], out); format != .None { return {kind = .Format, format = format} }
	return {}
}

refresh :: proc(s: ^Store) {
	if !s.enabled { return }
	for slot in Slot {
		data: game.Save_Data
		err := read_save(s.paths[slot], &data)
		update_slot(s, slot, &data, err)
	}
}

update_slot :: proc(s: ^Store, slot: Slot, data: ^game.Save_Data, err: Error) {
	info := Slot_Info{exists = err.kind != .Missing, error = err}
	if err.kind == .None {
		info.valid, info.stamp, info.sector, info.difficulty = true, data.stamp, data.sector, data.live.state.difficulty
		s.stamp = max(s.stamp, data.stamp)
	}
	s.slots[slot] = info
}

latest :: proc(s: ^Store) -> (Slot, bool) {
	if !s.enabled { return .Checkpoint, false }
	if s.slots[.Quick].valid && (!s.slots[.Checkpoint].valid || s.slots[.Quick].stamp > s.slots[.Checkpoint].stamp) { return .Quick, true }
	return .Checkpoint, s.slots[.Checkpoint].valid
}

write :: #force_no_inline proc(s: ^Store, g: ^game.State, slot: Slot) -> Error {
	if !s.enabled { return {kind = .Disabled} }
	data: game.Save_Data
	stamp := max(s.stamp+1, u64(max(0, time.to_unix_nanoseconds(time.now()))))
	format := game.save_capture(&data, g, .Quick if slot == .Quick else .Checkpoint, stamp)
	if format != .None { return {kind = .Format, format = format} }
	bytes: [game.SAVE_LIMIT]u8
	size, encode_err := game.save_encode(&data, bytes[:])
	if encode_err != .None { return {kind = .Format, format = encode_err} }
	err := atomic_write(s.directory, s.paths[slot], bytes[:size])
	if err.kind != .None { return err }
	update_slot(s, slot, &data, {})
	return {}
}

load :: #force_no_inline proc(s: ^Store, g: ^game.State, slot: Slot) -> Error {
	if !s.enabled { return {kind = .Disabled} }
	data: game.Save_Data
	err := read_save(s.paths[slot], &data)
	if err.kind == .None {
		format := game.save_restore(g, &data)
		if format != .None { err = {kind = .Format, format = format} }
	}
	// A slot may have been removed, repaired or replaced since the menu opened.
	// Publish only metadata from a fully restored save, including its new stamp.
	update_slot(s, slot, &data, err)
	return err
}
