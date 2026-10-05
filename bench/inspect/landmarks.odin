package inspect

import "core:fmt"
import rl "vendor:raylib"
import app "../../src"
import game "../../src/game"

survey_landmarks :: proc(r: ^app.Renderer, g: ^game.State, prefix: string) {
	View :: struct { room: game.Room_ID, feet, target: game.Vec3, name: string }
	views := [9]View{
		{1001, {0, 0.04, 10}, {-8, 2.3, -1}, "patch-cabinet"},
		{1003, {0, 0.04, 11}, {5, 3.9, -13.8}, "coil-arrival"},
		{1003, {12, 0.04, -2}, {5, 4.1, -13.8}, "coil-side"},
		{1005, {-17, 0.04, 1}, {14, 8.5, -24.6}, "royal-court"},
		{1005, {-4, 5.54, 18}, {14, 9, -24.6}, "royal-overlook"},
		{1015, {-10, 0.04, 13}, {4, 5.4, -3}, "pony-hall"},
		{1015, {17, 0.04, 11}, {1, 6, -3}, "pony-reverse"},
		{1011, {4, 30.04, 9}, {20, 28.6, -9}, "landing-guard"},
		{1014, {1.5, 0.04, 26}, {-2, 1.8, 8}, "cargo-ambush"},
	}
	for view in views {
		s := g.world.sector.sections[game.room_index(&g.world.sector, view.room)]
		g.player.position, g.player.velocity, g.player.grounded = s.origin+view.feet, {}, true
		game.aim_at(g, s.origin+view.target, false)
		g.time, g.message_time = 11.65, 0
		h: game.Pose_History
		v: game.Render_Snapshot
		game.capture_poses(&h, g)
		game.render_snapshot(&v, g, &h, 1)
		for _ in 0..<2 {
			rl.BeginDrawing()
			app.render_scene(r, &v, game.camera(&v), g.time)
			rl.EndDrawing()
		}
		path: [512]u8
		fmt.bprintf(path[:], "%s-%s.png", prefix, view.name)
		rl.TakeScreenshot(cstring(&path[0]))
		fmt.printf("LANDMARK %s: vertices=%d chunks=%d draws=%d\n", view.name, r.architecture_vertices, len(r.chunks), r.objects.world_draws)
	}
}
