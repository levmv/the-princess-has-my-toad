package tests

import "core:testing"
import "core:os"
import settings "../src/settings"
import storage "../src/storage"

@(test)
settings_accept_current_partial_files_and_preserve_custom_weapon_keys :: proc(t: ^testing.T) {
	directory, err := os.make_directory_temp("", "the-princess-has-my-toad-current-settings-*", context.allocator)
	testing.expect(t, err == nil)
	defer delete(directory)
	defer os.remove_all(directory)
	s: settings.Store
	settings.init(&s, directory)
	defer settings.destroy(&s)
	for text in ([2]string{`{"version":2,"sensitivity":0.004}`, `{"version":2,"bindings":{"Shotgun":81,"Fragmentator":82}}`}) {
		testing.expect_value(t, storage.atomic_write(directory, s.path, transmute([]u8)text).kind, storage.Error_Kind.None)
		settings.destroy(&s)
		settings.init(&s, directory)
		testing.expect(t, s.error.kind == .None && !s.dirty && settings.valid(&s.data))
		if s.data.sensitivity == 0.004 {
			testing.expect(t, s.data.bindings[.Shotgun] == '2' && s.data.bindings[.Fragmentator] == '3')
		} else {
			testing.expect(t, s.data.bindings[.Shotgun] == 'Q' && s.data.bindings[.Fragmentator] == 'R')
		}
	}
}

@(test)
settings_reject_old_unknown_and_unversioned_files_without_migration :: proc(t: ^testing.T) {
	directory, err := os.make_directory_temp("", "the-princess-has-my-toad-settings-version-*", context.allocator)
	testing.expect(t, err == nil)
	defer delete(directory)
	defer os.remove_all(directory)
	s: settings.Store
	settings.init(&s, directory)
	defer settings.destroy(&s)
	for text in ([3]string{`{"version":1,"sensitivity":0.004}`, `{"version":999}`, `{"sensitivity":0.004}`}) {
		testing.expect_value(t, storage.atomic_write(directory, s.path, transmute([]u8)text).kind, storage.Error_Kind.None)
		settings.destroy(&s)
		settings.init(&s, directory)
		testing.expect(t, s.error.kind == .Format && !s.dirty && s.data == settings.defaults())
	}
}

@(test)
settings_roundtrip_rebinding_and_corruption_fallback :: proc(t: ^testing.T) {
	directory, err := os.make_directory_temp("", "the-princess-has-my-toad-settings-*", context.allocator)
	testing.expect(t, err == nil)
	defer delete(directory)
	defer os.remove_all(directory)
	a, b: settings.Store
	settings.init(&a, directory)
	defer settings.destroy(&a)
	testing.expect(t, settings.bind(&a.data, .Forward, 'A'))
	testing.expect(t, a.data.bindings[.Forward] == 'A' && a.data.bindings[.Left] == 'W', "Conflicting bindings swap, leaving both actions accessible")
	testing.expect(t, !settings.bind(&a.data, .Fire, 256))
	a.data.sensitivity, a.data.invert_y, a.data.effects, a.data.voice = 0.004, true, 0.4, 0.7
	a.data.ambience, a.data.width, a.data.height, a.data.display = 0.2, 1920, 1080, .Borderless
	a.data.render_scale, a.data.music = 0.5, 0.35
	a.data.language, a.data.hero = .Russian, .Lora
	a.data.wing_hint_seen = true
	a.dirty = true
	testing.expect_value(t, settings.flush(&a).kind, storage.Error_Kind.None)
	settings.init(&b, directory)
	testing.expect(t, b.error.kind == .None && b.data == a.data)
	settings.destroy(&b)
	bad := "{\"version\":1,\"effects\":5}"
	storage.atomic_write(directory, a.path, transmute([]u8)bad)
	settings.init(&b, directory)
	defer settings.destroy(&b)
	testing.expect(t, b.error.kind == .Format && b.data == settings.defaults() && !b.dirty)
	settings.flush(&b)
	bytes: [128]u8
	n, read_err := storage.read_bounded(a.path, bytes[:])
	testing.expect(t, read_err.kind == .None && string(bytes[:n]) == bad, "Invalid settings are diagnosed without overwriting them on startup")
}
