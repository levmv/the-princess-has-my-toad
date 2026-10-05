package inspect

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import gl "vendor:OpenGL"
import app "../../src"
import game "../../src/game"
import settings "../../src/settings"
import loc "../../src/locale"

survey_wing_hint :: proc(r: ^app.Renderer, g: ^game.State, prefix: string) {
	anchor, ok := game.resolve_location(&g.world.sector, g.world.sector.wing_hint)
	assert(ok)
	g.player.position, g.player.yaw, g.player.pitch = anchor+game.Vec3{0, 0.05, 0}, math.PI*0.5, -0.10
	g.player.grounded = true
	h: game.Pose_History
	v: game.Render_Snapshot
	game.capture_poses(&h, g)
	game.render_snapshot(&v, g, &h, 1)
	for language in loc.Language {
		r.language = language
		for key in ([2]int{32, -5}) {
			prefs := settings.defaults()
			settings.bind(&prefs, .Jump, key)
			for _ in 0..<2 {
				rl.BeginDrawing()
				app.render_scene(r, &v, game.camera(&v), g.time)
				app.draw_hud(r, g, false, false, true, 0, 0, 0, &prefs)
				app.draw_wing_hint(r, 1, &prefs)
				rl.EndDrawing()
			}
			path: [512]u8
			fmt.bprintf(path[:], "%s-%v-%d.png", prefix, language, key)
			rl.TakeScreenshot(cstring(&path[0]))
			assert(gl.GetError() == 0)
		}
	}
}
