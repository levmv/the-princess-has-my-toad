package inspect

import "core:fmt"
import gl "vendor:OpenGL"
import rl "vendor:raylib"
import app "../../src"
import game "../../src/game"

survey_supplies :: proc(r: ^app.Renderer, g: ^game.State, prefix: string) {
	rooms := [4]game.Room_ID{1004, 1004, 1005, 1006}
	feet := [4]game.Vec3{{9, 0.04, -9}, {10, 0.04, -22}, {-8, 4.34, 14}, {6, 0.04, -14}}
	targets := [4]game.Vec3{{0, 2, -20}, {-3, 1, -24}, {0, 6.1, 18}, {13, 1, -15}}
	for room, i in rooms {
		s := g.world.sector.sections[game.room_index(&g.world.sector, room)]
		g.player.position = game.ram_local(s, feet[i])
		game.aim_at(g, game.ram_local(s, targets[i]), false)
		g.time = 11.65
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
		fmt.bprintf(path[:], "%s-%d.png", prefix, i)
		rl.TakeScreenshot(cstring(&path[0]))
		assert(gl.GetError() == 0)
	}
	fmt.println("SUPPLY SURVEY OK: lower pocket, perch weapon, stair recess")
}
