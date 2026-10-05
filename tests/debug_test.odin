package tests

import "core:testing"
import game "../src/game"

@(test)
developer_room_launches_are_clear_and_can_be_replayed_from_a_save :: proc(t: ^testing.T) {
	w, restored: game.World
	game.world_init_ram(&w)
	game.world_init_ram(&restored)
	defer game.world_destroy(&w)
	defer game.world_destroy(&restored)
	g, b := game.State{world = &w}, game.State{world = &restored}
	game.init(&g); game.init(&b)
	for s in w.sector.sections[:w.sector.count] {
		game.init(&g)
		if !testing.expectf(t, game.debug_enter_room(&g, s.id), "Room %d has no developer entry", s.id) { return }
		testing.expect(t, game.room_at(&w.sector, g.player.position) == game.room_index(&w.sector, s.id))
		testing.expect(t, game.world_clear_box(&w, g.player.position+game.Vec3{0, game.PLAYER_HEIGHT*0.5, 0}, {game.PLAYER_RADIUS, game.PLAYER_HEIGHT*0.5, game.PLAYER_RADIUS}))
		#partial switch s.role {
		case .Fracture_Span: testing.expect(t, abs(g.player.position.y) < 0.05)
		case .Launch_Terrace, .Receiver_Terrace: testing.expect(t, abs(g.player.position.y-6) < 0.05)
		case .Charge_Causeway: testing.expect(t, abs(g.player.position.y-16) < 0.05 && g.checkpoint_id == w.checkpoints[2].id)
		}
		save: game.Save_Data
		testing.expect_value(t, game.save_capture(&save, &g, .Quick, 0), game.Save_Error.None)
		testing.expect_value(t, game.save_restore(&b, &save), game.Save_Error.None)
		testing.expect_value(t, b.player.position, g.player.position)
	}
	position := g.player.position
	testing.expect(t, !game.debug_enter_room(&g, 65535) && g.player.position == position)
}
