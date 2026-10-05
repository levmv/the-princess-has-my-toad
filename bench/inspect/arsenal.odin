package inspect

import "core:fmt"
import rl "vendor:raylib"
import gl "vendor:OpenGL"
import app "../../src"
import game "../../src/game"
import settings "../../src/settings"
import storage "../../src/storage"

survey_arsenal :: proc(r: ^app.Renderer, g: ^game.State, prefix: string) {
	for &e in g.enemies { e.health = 0 }
	g.enemy_count = 0
	g.player.position = {0, 0.03, -17}
	g.player.yaw, g.player.pitch, g.player.grounded = 0, 0, true
	g.player.shotgun_unlocked, g.player.fragment_unlocked = true, true
	g.player.shotgun_ammo, g.player.fragment_ammo, g.player.weapon = 12, 6, .Shotgun
	g.pickup_count = 4
	g.pickups[0] = {1, {-1.7, 0.55, -21.4}, .Shotgun, 12, false}
	g.pickups[1] = {2, {-0.9, 0.55, -21.4}, .Shells, 6, false}
	g.pickups[2] = {3, {0.9, 0.55, -21.4}, .Launcher, 6, false}
	g.pickups[3] = {4, {1.8, 0.55, -21.4}, .Fragments, 3, false}
	h: game.Pose_History
	v: game.Render_Snapshot
	for frame in 0..<13 {
		cam := game.Camera{position = {3.2, 1.9, -21}, target = g.player.position+game.Vec3{0, 0.9, 0}, fov = 45}
		if frame == 1 { g.hero = .Lora }
		if frame == 2 { g.player.weapon = .Fragmentator }
		if frame == 3 { cam.position, cam.target = {4.2, 2.7, -25}, {0, 0.45, -21.4} }
		if frame >= 4 {
			g.player.weapon = .Shotgun
			cam.position, cam.target, cam.fov = {3.3, 2.3, -15}, {0, 1.3, -22}, 55
		}
		if frame == 4 {
			id, ok := game.spawn_enemy(g, {0, 1.7, -22}, 11, 100, .Sentry)
			assert(ok)
			game.aim_at(g, g.enemies[id.slot].position, false)
			assert(game.fire_shotgun(g, false))
			assert(g.enemies[id.slot].gibbed)
		}
		if frame >= 5 && frame <= 7 {
			steps := [3]int{15, 50, 240}
			for _ in 0..<steps[frame-5] {
				for &e in g.enemies[:g.enemy_count] { game.update_enemy_death(g, &e, game.STEP) }
				game.update_gibs(g, game.STEP)
				g.player.recoil = 0
				for &p in g.particles { p.life = 0 }
				for &f in g.flashes { f.life = 0 }
			}
		}
		if frame == 8 {
			g.fragments[0] = {{0, 1.8, -21.4}, {0, 0, -56}, 1}
			cam.position, cam.target, cam.fov = {1.1, 2.15, -22.9}, {0, 1.8, -21.4}, 45
		}
		if frame == 9 { g.fragments[0].life = 0; game.explode_fragment(g, {0, 1.0, -22}) }
		if frame == 11 {
			for &p in g.particles { p.life = 0 }
			for &f in g.flashes { f.life = 0 }
			sources := [3]game.Death_Cause{.Fairy, .Nanny, .GC}
			for source, i in sources { g.projectiles[i] = {{f32(i-1)*1.3, 1.8, -21.4}, {0, 0, -36}, 1, source} }
			cam.position, cam.target, cam.fov = {2.8, 2.7, -24.5}, {0, 1.8, -21.4}, 45
		}
		if frame == 12 {
			for &p in g.projectiles { p.life = 0 }
			game.explode_fragment(g, {0, 1.3, -22})
			for _ in 0..<24 { game.update(g, {}, game.STEP) }
		}
		cam.forward = game.normalized(cam.target-cam.position)
		game.capture_poses(&h, g)
		game.render_snapshot(&v, g, &h, 1)
		for _ in 0..<2 {
			rl.BeginDrawing()
			app.render_scene(r, &v, cam, g.time)
			if frame == 10 {
				prefs := settings.Store{data = settings.defaults()}
				prefs.data.language, r.language = .Russian, .Russian
				menu := app.Menu_State{page = .Controls, binding = -1, selected = int(settings.Action.Shotgun)}
				saves: storage.Store
				app.draw_menu_panel(r, g, false, &menu, &saves, &prefs)
			} else { app.draw_hud(r, g, false, false, true, 0, 0, 0) }
			rl.EndDrawing()
		}
		path: [512]u8
		fmt.bprintf(path[:], "%s-arsenal-%d.png", prefix, frame)
		rl.TakeScreenshot(cstring(&path[0]))
		assert(gl.GetError() == 0)
	}
}
