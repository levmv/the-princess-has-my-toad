#+build js
package storage

import "core:strings"

System_Error :: int

foreign import browser "env.o"
foreign browser {
	toad_storage_read :: proc "c" (key: cstring, data: [^]u8, capacity: int) -> int ---
	toad_storage_write :: proc "c" (key: cstring, data: [^]u8, size: int) -> int ---
}

default_directory :: proc(config: bool = false) -> string {
	return strings.clone("the-princess-has-my-toad/config" if config else "the-princess-has-my-toad/save")
}

read_bounded :: proc(path: string, bytes: []u8) -> (int, Error) {
	key := strings.clone_to_cstring(path)
	defer delete(key)
	size := toad_storage_read(key, raw_data(bytes), len(bytes))
	if size == -1 { return 0, {kind = .Missing} }
	if size == -2 { return 0, {kind = .Format, format = .Too_Large} }
	if size < 0 { return 0, {kind = .Read} }
	return size, {}
}

// localStorage replaces a single bounded value atomically. Failed/quota-denied
// writes leave the prior slot intact and use the same error path as native I/O.
atomic_write :: proc(directory, path: string, bytes: []u8) -> Error {
	key := strings.clone_to_cstring(path)
	defer delete(key)
	if toad_storage_write(key, raw_data(bytes), len(bytes)) != 0 { return {kind = .Write} }
	return {}
}
