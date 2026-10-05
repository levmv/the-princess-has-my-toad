#+build !js
package storage

import "core:fmt"
import "core:os"
import "core:strings"

System_Error :: os.Error

default_directory :: proc(config: bool = false) -> string {
	variable := "XDG_CONFIG_HOME" if config else "XDG_DATA_HOME"
	base := os.get_env(variable, context.allocator)
	defer delete(base)
	if len(base) > 0 && base[0] == '/' { return fmt.aprintf("%s/the-princess-has-my-toad", base) }
	user_dir := os.get_env("HOME", context.allocator)
	defer delete(user_dir)
	if len(user_dir) == 0 || user_dir[0] != '/' { return "" }
	return fmt.aprintf("%s/%s/the-princess-has-my-toad", user_dir, ".config" if config else ".local/share")
}


read_bounded :: proc(path: string, bytes: []u8) -> (int, Error) {
	f, open_err := os.open(path, {.Read, .Non_Blocking})
	if open_err != nil { return 0, {kind = .Missing if open_err == os.General_Error.Not_Exist else .Open, system = open_err} }
	defer os.close(f)
	info, info_err := os.fstat(f, context.allocator)
	if info_err != nil { return 0, {kind = .Read, system = info_err} }
	defer os.file_info_delete(info, context.allocator)
	if info.type != .Regular { return 0, {kind = .Read} }
	if info.size > i64(len(bytes)) { return 0, {kind = .Format, format = .Too_Large} }
	if info.size < 0 { return 0, {kind = .Read} }
	size, at := int(info.size), 0
	for at < size {
		n, err := os.read(f, bytes[at:size])
		if err != nil || n <= 0 { return 0, {kind = .Read, system = err} }
		at += n
	}
	return size, {}
}

// The old slot is untouched until the complete replacement has been flushed.
// A unique sibling temporary also permits independent game processes to save;
// rename publishes one complete snapshot, never a mixture of their bytes.
atomic_write :: #force_no_inline proc(directory, path: string, bytes: []u8) -> Error {
	if err := os.mkdir_all(directory, {.Read_User, .Write_User, .Execute_User}); err != nil && err != os.General_Error.Exist { return {kind = .Directory, system = err} }
	f, open_err := os.create_temp_file(directory, ".pending-*")
	if open_err != nil { return {kind = .Open, system = open_err} }
	temporary := strings.clone(os.name(f))
	defer delete(temporary)
	defer os.remove(temporary)
	defer if f != nil { os.close(f) }
	at := 0
	for at < len(bytes) {
		n, err := os.write(f, bytes[at:])
		if err != nil || n <= 0 { return {kind = .Write, system = err} }
		at += n
	}
	if err := os.sync(f); err != nil { return {kind = .Sync, system = err} }
	close_err := os.close(f)
	f = nil
	if close_err != nil { return {kind = .Write, system = close_err} }
	if err := os.rename(temporary, path); err != nil { return {kind = .Rename, system = err} }
	dir, dir_err := os.open(directory)
	if dir_err != nil { return {kind = .Sync, system = dir_err} }
	defer os.close(dir)
	if err := os.sync(dir); err != nil { return {kind = .Sync, system = err} }
	return {}
}
