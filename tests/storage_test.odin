package tests

import "core:testing"
import "core:os"
import "core:fmt"
import game "../src/game"
import storage "../src/storage"

@(test)
disk_saves_are_atomic_bounded_and_failed_loads_preserve_both_slots :: proc(t: ^testing.T) {
	directory, dir_err := os.make_directory_temp("", "the-princess-has-my-toad-storage-*", context.allocator)
	testing.expect(t, dir_err == nil)
	defer delete(directory)
	defer os.remove_all(directory)
	w: game.World
	game.world_init_ram(&w, 42)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	s: storage.Store
	storage.init(&s, directory)
	defer storage.destroy(&s)
	_, has_save := storage.latest(&s)
	testing.expect(t, !has_save)
	testing.expect_value(t, storage.write(&s, &g, .Checkpoint).kind, storage.Error_Kind.None)
	g.player.health, g.player.fragment_ammo, g.player.fragment_unlocked = 67, 7, true
	testing.expect_value(t, storage.write(&s, &g, .Quick).kind, storage.Error_Kind.None)
	selected, found := storage.latest(&s)
	testing.expect(t, found && selected == .Quick)
	// An interrupted writer's partial sibling must not replace either slot.
	partial := fmt.aprintf("%s/.pending-abandoned", directory)
	defer delete(partial)
	f, err := os.create(partial)
	testing.expect(t, err == nil)
	os.write(f, []u8{0, 1, 2})
	os.close(f)
	storage.refresh(&s)
	g.player.health = 10
	testing.expect_value(t, storage.load(&s, &g, .Quick).kind, storage.Error_Kind.None)
	testing.expect(t, g.player.health == 67 && g.player.fragment_ammo == 7)
	// A valid old slot remains usable when the other is corrupt.
	testing.expect_value(t, storage.atomic_write(directory, s.paths[.Quick], []u8{1, 2, 3}).kind, storage.Error_Kind.None)
	revision := w.revision
	testing.expect_value(t, storage.load(&s, &g, .Quick).kind, storage.Error_Kind.Format)
	testing.expect(t, w.revision == revision && g.player.health == 67)
	storage.refresh(&s)
	selected, found = storage.latest(&s)
	testing.expect(t, found && selected == .Checkpoint && !s.slots[.Quick].valid)
	testing.expect_value(t, storage.load(&s, &g, .Checkpoint).kind, storage.Error_Kind.None)
	testing.expect_value(t, g.player.health, f32(100))
	bytes: [64]u8
	count, read_err := storage.read_bounded(s.paths[.Quick], bytes[:])
	testing.expect(t, read_err.kind == .None && count == 3 && bytes[0] == 1, "Failed reading does not silently replace a corrupt slot")
	// Rename failure cleans up its temporary and leaves the destination alone.
	blocked := fmt.aprintf("%s/is-a-directory", directory)
	defer delete(blocked)
	os.mkdir(blocked)
	testing.expect_value(t, storage.atomic_write(directory, blocked, []u8{9}).kind, storage.Error_Kind.Rename)
	_, too_large := storage.read_bounded(s.paths[.Checkpoint], bytes[:])
	testing.expect(t, too_large.kind == .Format && too_large.format == .Too_Large)
}

@(test)
loading_replaced_or_removed_slots_refreshes_menu_metadata :: proc(t: ^testing.T) {
	directory, err := os.make_directory_temp("", "the-princess-has-my-toad-slot-cache-*", context.allocator)
	testing.expect(t, err == nil)
	defer delete(directory)
	defer os.remove_all(directory)
	w: game.World
	game.world_init(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	s, writer: storage.Store
	storage.init(&s, directory)
	storage.init(&writer, directory)
	defer storage.destroy(&s)
	defer storage.destroy(&writer)
	testing.expect_value(t, storage.write(&s, &g, .Checkpoint).kind, storage.Error_Kind.None)
	// Another process replaces a corrupt slot without restarting this reader.
	testing.expect_value(t, storage.atomic_write(directory, s.paths[.Quick], []u8{1}).kind, storage.Error_Kind.None)
	testing.expect_value(t, storage.load(&s, &g, .Quick).kind, storage.Error_Kind.Format)
	testing.expect(t, s.slots[.Quick].exists && !s.slots[.Quick].valid)
	writer.stamp = s.stamp+1000
	g.difficulty, g.run.difficulty = .Nightmare, .Nightmare
	game.init(&g)
	g.player.health = 37
	testing.expect_value(t, storage.write(&writer, &g, .Quick).kind, storage.Error_Kind.None)
	testing.expect_value(t, storage.load(&s, &g, .Quick).kind, storage.Error_Kind.None)
	slot, available := storage.latest(&s)
	testing.expect(t, available && slot == .Quick && g.player.health == 37)
	testing.expect_value(t, s.slots[.Quick], writer.slots[.Quick])
	testing.expect_value(t, s.stamp, writer.stamp)
	testing.expect_value(t, os.remove(s.paths[.Quick]), os.Error(nil))
	testing.expect_value(t, storage.load(&s, &g, .Quick).kind, storage.Error_Kind.Missing)
	testing.expect(t, !s.slots[.Quick].exists && !s.slots[.Quick].valid && s.slots[.Quick].stamp == 0)
	slot, available = storage.latest(&s)
	testing.expect(t, available && slot == .Checkpoint && g.player.health == 37)
}
