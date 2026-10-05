package inspect

import "core:fmt"
import "core:math"
import "core:os"
import "core:strconv"
import gl "vendor:OpenGL"
import rl "vendor:raylib"
import app "../../src"
import game "../../src/game"
import front "../../src/front"
import loc "../../src/locale"
import settings "../../src/settings"
import storage "../../src/storage"

// A visual survey, not a performance test. Works on a nested software display
// while the physical monitors are disconnected. No desktop settings are changed.
main :: proc() {
	prefix := "build/survey"
	if len(os.args) > 1 { prefix = os.args[1] }
	selected := 0
	opening := len(os.args) > 2 && os.args[2] == "intro"
	feedback := len(os.args) > 2 && os.args[2] == "feedback"
	wing_hint := len(os.args) > 2 && os.args[2] == "wing-hint"
	airways := len(os.args) > 2 && os.args[2] == "airways"
	supplies := len(os.args) > 2 && os.args[2] == "supplies"
	landmarks := len(os.args) > 2 && os.args[2] == "landmarks"
	actors_back := len(os.args) > 2 && os.args[2] == "actors-back"
	actors := actors_back || (len(os.args) > 2 && os.args[2] == "actors")
	weapons := len(os.args) > 2 && os.args[2] == "weapons"
	arsenal := len(os.args) > 2 && os.args[2] == "arsenal"
	gates := len(os.args) > 2 && os.args[2] == "gates"
	boss := len(os.args) > 2 && os.args[2] == "boss"
	lift := len(os.args) > 2 && os.args[2] == "lift"
	anvil := len(os.args) > 2 && os.args[2] == "anvil"
	deaths := len(os.args) > 2 && os.args[2] == "deaths"
	hero := len(os.args) > 2 && os.args[2] == "hero"
	if len(os.args) > 2 && !actors && !weapons && !arsenal && !gates && !boss && !anvil && !deaths && !hero && !opening && !airways && !feedback && !supplies && !landmarks && !lift && !wing_hint {
		id, ok := strconv.parse_int(os.args[2])
		assert(ok && id >= 0 && id <= 65535)
		selected = id
	}
	sector := game.Sector_ID.RAM_Bank_01
	if len(os.args) > 3 { sector = game.sector_by_path(os.args[3]); assert(sector != .None) }
	if actors || weapons || arsenal || deaths || hero { sector = .RAM_Combat_Lab }
	rl.SetTraceLogLevel(.WARNING)
	rl.SetConfigFlags({.WINDOW_HIDDEN})
	width, height := 960, 600
	if len(os.args) > 5 {
		w, wok := strconv.parse_int(os.args[4])
		h, hok := strconv.parse_int(os.args[5])
		assert(wok && hok && w >= 960 && h >= 600)
		width, height = w, h
	}
	rl.InitWindow(i32(width), i32(height), "THE PRINCESS HAS MY TOAD / room survey")
	assert(rl.IsWindowReady())
	defer rl.CloseWindow()
	rl.SetTargetFPS(0)
	w: game.World
	game.world_load_sector(&w, sector, game.DEFAULT_SEED)
	assert(selected == 0 || game.room_index(&w.sector, game.Room_ID(selected)) >= 0, "Unknown room ID")
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	r: app.Renderer
	app.renderer_init(&r, &g)
	defer app.renderer_destroy(&r)
	if lift { survey_lift(&r, &g, prefix); return }
	if opening { survey_intro(&r, &g, prefix); return }
	if feedback { survey_feedback(&r, &g, prefix); return }
	if wing_hint { survey_wing_hint(&r, &g, prefix); return }
	if actors { survey_actors(&r, &g, prefix, actors_back); return }
	if weapons { survey_weapons(&r, &g, prefix); return }
	if arsenal { survey_arsenal(&r, &g, prefix); return }
	if supplies { survey_supplies(&r, &g, prefix); return }
	if landmarks { survey_landmarks(&r, &g, prefix); return }
	if gates { survey_gates(&r, &g, prefix); return }
	if boss || anvil { survey_finale(&r, &g, prefix, anvil); return }
	if deaths || hero { survey_reactions(&r, &g, prefix, hero); return }
	h: game.Pose_History
	v: game.Render_Snapshot
	for room in 0..<w.sector.count {
		s := w.sector.sections[room]
		if selected != 0 && int(s.id) != selected { continue }
		if airways && !game.exterior_section(s.role) && s.role != .Capacitor_Garden { continue }
		for angle in 0..<2 {
			sign := f32(1 if angle == 0 else -1)
			g.player.position = s.origin+game.Vec3{0, 0.05, sign*s.depth*0.3}
			g.player.yaw, g.player.pitch = 0 if angle == 0 else math.PI, -0.08
			if s.width > s.depth {
				g.player.position = s.origin+game.Vec3{-sign*s.width*0.3, 0.05, 0}
				g.player.yaw = sign*math.PI*0.5
			}
			nav := &w.room_navigation[room]
			if nav.count > 0 {
				point := 0
				if angle == 1 {
					for p, i in nav.points[:nav.count] {
						if game.length(p-nav.points[0]) > game.length(nav.points[point]-nav.points[0]) { point = i }
					}
				}
				g.player.position = nav.points[point]+game.Vec3{0, 0.05, 0}
				delta := s.origin-g.player.position
				g.player.yaw = math.atan2(delta.x, -delta.z)
			}
			top := game.Vec3{g.player.position.x, s.origin.y+s.height-0.15, g.player.position.z}
			if nav.count > 0 { top.y = g.player.position.y+game.PLAYER_HEIGHT }
			floor := game.world_ray(&w, top, {0, -1, 0}, s.height+1)
			g.player.position.y = top.y-floor+0.03
			#partial switch s.role {
			case .Fracture_Span:
				g.player.position = game.ram_local(s, {0, 10.04, 16} if angle == 0 else game.Vec3{0, 7.04, -21})
				g.player.yaw = sign*math.PI*0.5
			case .Launch_Terrace:
				g.player.position = game.ram_local(s, {0, 6.04, 26} if angle == 0 else game.Vec3{0, 16.04, -31})
				g.player.yaw, g.player.pitch = sign*math.PI*0.5, 0.13 if angle == 0 else -0.22
			case .Charge_Causeway:
				p := game.CHARGE_LANDINGS[0 if angle == 0 else 3]
				target := game.CHARGE_LANDINGS[2 if angle == 0 else 5]
				g.player.position = s.origin+p+game.Vec3{0, 0.04, 0}
				g.player.yaw, g.player.pitch = math.atan2(target.x-p.x, p.z-target.z), -0.12
			case .Receiver_Terrace:
				g.player.position = game.ram_local(s, {0, 6.04, -28} if angle == 0 else game.Vec3{0, 6.04, 28})
				g.player.yaw = -sign*math.PI*0.5
			case .Capacitor_Garden:
				g.player.position = s.origin+(game.Vec3{-21, 0.04, 3} if angle == 0 else game.Vec3{-4, 5.54, 18})
				g.player.yaw, g.player.pitch = 1.18, -0.08
			}
			g.player.grounded = true
			g.message_time = 0
			g.time = 11.65
			g.lift_started = true
			game.capture_poses(&h, &g)
			game.render_snapshot(&v, &g, &h, 1)
			cam := game.camera(&v)
			for _ in 0..<2 {
				rl.BeginDrawing()
				app.render_scene(&r, &v, cam, g.time)
				ui := app.ui_context(&r)
				buffer: [128]u8
				app.label(ui, fmt.bprintf(buffer[:], "ROOM %d / %v / %v / VIEW %d", s.id, s.role, s.variant, angle), 25, 20, 18, app.PAPER, 2)
				rl.EndDrawing()
			}
			path: [512]u8
			fmt.bprintf(path[:], "%s-%d-%d.png", prefix, s.id, angle)
			rl.TakeScreenshot(cstring(&path[0]))
			assert(gl.GetError() == 0)
			fmt.printf("Survey room=%d view=%d camera=%v\n", s.id, angle, cam.position)
		}
	}
	fmt.println("SURVEY OK: requested rooms, both directions. This checks appearance, not traversal or GPU speed.")
}

survey_feedback :: proc(r: ^app.Renderer, g: ^game.State, prefix: string) {
 h: game.Pose_History
 v: game.Render_Snapshot
 for frame in 0..<4 {
  g.player.hurt_time, g.player.hurt_strength = 0.28 if frame == 1 else 0, 1
  game.capture_poses(&h, g)
  game.render_snapshot(&v, g, &h, 1)
  r.language = .Russian if frame == 2 else .English
  for _ in 0..<2 {
   rl.BeginDrawing()
   if frame < 2 { app.render_scene(r, &v, game.camera(&v), g.time)
   } else { app.draw_death_screen(r, {active = true, age = 1, cause = .Fairy}) }
   rl.EndDrawing()
  }
  path: [512]u8
  fmt.bprintf(path[:], "%s-feedback-%d.png", prefix, frame)
  rl.TakeScreenshot(cstring(&path[0]))
  assert(gl.GetError() == 0)
 }

}

survey_reactions :: proc(r: ^app.Renderer, g: ^game.State, prefix: string, hero: bool) {
	for &e in g.enemies { e.health, e.phase_time = 0, 0 }
	g.player.position = {0, 0.02, -22}
	g.player.yaw, g.player.pitch, g.player.grounded = 0, 0, true
	g.player.velocity, g.player.land_time, g.player.kick_time = {}, 0, 0
	g.player.invulnerable = 0
	h: game.Pose_History
	v: game.Render_Snapshot
	count := 4 if hero else len([game.Enemy_Kind]int{})*4
	for frame in 0..<count {
		target := g.player.position+game.Vec3{0, 0.9, 0}
		if hero {
			g.player.idle_time = 7 if frame == 0 else (12.5 if frame == 1 else (17.25 if frame == 2 else 0))
			g.player.hurt_time = 0.14 if frame == 3 else 0
		} else {
			kind := game.Enemy_Kind(frame/4)
			e := &g.enemies[0]
			e^ = {kind = kind, position = {0, game.enemy_extent(kind).y+0.03, -30}, health = 1, facing = {0, 0, 1}}
			game.damage_enemy(g, 0, 5, .Body, e.position, true)
			steps := 720 if frame%4 == 3 else int(f32(1+frame%4)*game.enemy_death_duration(kind)*0.24/game.STEP)
			for _ in 0..<steps { game.update_enemy_death(g, e, game.STEP) }
			// Photograph the articulated mesh; do not accumulate the initial
			// impact flashes from all fifteen independent fixtures.
			g.flashes, g.particles = {}, {}
			target = e.position
		}
		game.capture_poses(&h, g)
		game.render_snapshot(&v, g, &h, 1)
		position := target+game.Vec3{2.7, 1.0, -3.8} if hero else target+game.Vec3{3.2, 1.8, 4}
		cam := game.Camera{position = position, target = target, forward = game.normalized(target-position), fov = 42, scoped = !hero}
		for _ in 0..<2 { rl.BeginDrawing(); app.render_scene(r, &v, cam, 12); rl.EndDrawing() }
		path: [512]u8
		fmt.bprintf(path[:], "%s-%s-%d.png", prefix, "hero" if hero else "death", frame)
		rl.TakeScreenshot(cstring(&path[0]))
		assert(gl.GetError() == 0)
		fmt.printf("Reaction frame=%d instances=%d\n", frame, r.objects.count)
	}
}

survey_gates :: proc(r: ^app.Renderer, g: ^game.State, prefix: string) {
	assert(g.world.gate_count > 0)
	gate := &g.world.gates[0]
	g.player.position = gate.closed.center+game.Vec3{0, -gate.closed.size.y*0.5+0.03, -7}
	g.player.yaw, g.player.pitch, g.player.grounded = math.PI, -0.08, true
	h: game.Pose_History
	v: game.Render_Snapshot
	for pose in 0..<3 {
		gate.amount, gate.open = f32(pose)*0.5, pose > 0
		game.capture_poses(&h, g)
		game.render_snapshot(&v, g, &h, 1)
		for _ in 0..<2 {
			rl.BeginDrawing()
			app.render_scene(r, &v, game.camera(&v), 12)
			rl.EndDrawing()
		}
		path: [512]u8
		fmt.bprintf(path[:], "%s-gate-%d.png", prefix, pose)
		rl.TakeScreenshot(cstring(&path[0]))
		assert(gl.GetError() == 0)
	}
}

survey_weapons :: proc(r: ^app.Renderer, g: ^game.State, prefix: string) {
	for &e in g.enemies { e.health = 0 }
	g.player.position = {0, 0.02, -22}
	g.player.yaw, g.player.pitch = 0, 0
	g.player.weapon, g.player.fragment_unlocked, g.player.fragment_ammo = .Fragmentator, true, 8
	g.player.grounded = true
	g.pickup_count = 2
	g.pickups[0] = {1, {-1.1, 0.6, -22}, .Health, 30, false}
	g.pickups[1] = {2, {-1.8, 0.6, -22}, .Fragments, 4, false}
	h: game.Pose_History
	v: game.Render_Snapshot
	for frame in 0..<4 {
		g.player.kick_time = game.KICK_DURATION-f32(frame)*0.10 if frame > 0 else 0
		game.capture_poses(&h, g)
		game.render_snapshot(&v, g, &h, 1)
		position := g.player.position+game.Vec3{3.2, 1.9, -4.0}
		target := g.player.position+game.Vec3{0, 0.8, 0}
		cam := game.Camera{position = position, target = target, forward = game.normalized(target-position), fov = 42}
		for _ in 0..<2 {
			rl.BeginDrawing()
			app.render_scene(r, &v, cam, 12)
			app.draw_hud(r, g, false, false, true, 0, 0, 0)
			rl.EndDrawing()
		}
		path: [512]u8
		fmt.bprintf(path[:], "%s-weapons-%d.png", prefix, frame)
		rl.TakeScreenshot(cstring(&path[0]))
		assert(gl.GetError() == 0)
		fmt.printf("Survey weapons pose=%d kick=%.3f\n", frame, g.player.kick_time)
	}
}

survey_actors :: proc(r: ^app.Renderer, g: ^game.State, prefix: string, rear: bool = false) {
	for &e in g.enemies { e.health = 0 }
	g.enemy_count = 1
	g.player.position = {0, 0, -15}
	h: game.Pose_History
	v: game.Render_Snapshot
	for kind in game.Enemy_Kind {
		for phase in game.Enemy_Phase {
			e := &g.enemies[0]
			y := game.enemy_extent(kind).y+0.03 if game.enemy_grounded_kind(kind) else f32(1.7)
			e^ = game.Enemy{kind = kind, phase = phase, phase_time = 0.27, health = 10, position = {0, y, -22}, attack_target = {0, 0.04, -18}, facing = {0, 0, 1}, gait_phase = 1.4}
			game.capture_poses(&h, g)
			game.render_snapshot(&v, g, &h, 1)
			position := e.position+game.Vec3{3.2, 1.8, -4.0 if rear else 4.0}*max(1, game.enemy_scale(kind)*0.75)
			cam := game.Camera{position = position, target = e.position, forward = game.normalized(e.position-position), fov = 42, scoped = true}
			for _ in 0..<2 {
				rl.BeginDrawing()
				app.render_scene(r, &v, cam, 12)
				buffer: [128]u8
				app.label(app.ui_context(r), fmt.bprintf(buffer[:], "%v / %v", kind, phase), 25, 20, 18, app.PAPER, 2)
				rl.EndDrawing()
			}
			path: [512]u8
			fmt.bprintf(path[:], "%s-%v-%v.png", prefix, kind, phase)
			rl.TakeScreenshot(cstring(&path[0]))
			assert(gl.GetError() == 0)
			fmt.printf("Survey actor=%v phase=%v instances=%d\n", kind, phase, r.objects.count)
		}
	}
}

survey_finale :: proc(r: ^app.Renderer, g: ^game.State, prefix: string, anvil: bool) {
	g.lift_started = true
	g.player.position = game.boss_room_origin(g.world)+game.Vec3{0, 0.02, 13}
	g.player.yaw, g.player.pitch, g.player.grounded = 0, 0, true
	if anvil { g.player.position = g.world.spawn; game.drop_anvil(g) }
	h: game.Pose_History
	v: game.Render_Snapshot
	for pose in 0..<7 {
		if anvil {
			g.anvil.phase = .Warning if pose < 2 else (.Falling if pose < 5 else .Rest)
			g.anvil.timer = 1
			g.anvil.position = g.anvil.target+game.Vec3{0, 3.4-f32(pose)*0.42, 0}
		} else {
			g.boss.stage = min(2, pose/2)
			g.boss.health = 36-g.boss.stage*12
			game.boss_plan(g)
			game.boss_phase(&g.boss, .Sweep if pose%2 == 1 else .Mark, 2)
			g.boss.timer = 1
			if pose == 5 { game.boss_phase(&g.boss, .Exposed, 3); g.boss.timer = 2 }
			if pose == 6 { game.boss_phase(&g.boss, .Dead, 3); g.boss.health = 0 }
		}
		game.capture_poses(&h, g)
		game.render_snapshot(&v, g, &h, 1)
		cam := game.camera(&v)
		if anvil || pose >= 4 {
			from := g.player.position+game.Vec3{4, 3.2, 5} if anvil else game.boss_origin(g.world)+game.Vec3{9, 5.5, 15}
			target := g.anvil.target+game.Vec3{0, 1.4, 0} if anvil else game.boss_core(g.world)
			cam = {position = from, target = target, forward = game.normalized(target-from), fov = 53}
		}
		for _ in 0..<2 { rl.BeginDrawing(); app.render_scene(r, &v, cam, 12); rl.EndDrawing() }
		path: [512]u8
		fmt.bprintf(path[:], "%s-%s-%d.png", prefix, "anvil" if anvil else "boss", pose)
		rl.TakeScreenshot(cstring(&path[0]))
		assert(gl.GetError() == 0)
		fmt.printf("Finale pose=%d instances=%d\n", pose, r.objects.count)
	}
}


survey_intro :: proc(r: ^app.Renderer, g: ^game.State, prefix: string) {
 saves: storage.Store
 prefs := settings.Store{data = settings.defaults()}
 reveal_times := [3]f32{0, 1.25, 3.2}
 for language in loc.Language {
  r.language, prefs.data.language = language, language
  for shot in 0..<9 {
   s := front.State{phase = .Intro, scene = min(shot, 2), elapsed = 2, animation = 5, hero = .Duke}
   // Same camera at the close shot / reveal boundary, midpoint and low angle.
   if shot >= 2 && shot <= 4 { s.elapsed = reveal_times[shot-2] }
   if shot == 5 || shot == 6 { s.phase = .Fighter; s.hero = .Duke if shot == 5 else .Lora }
   if shot >= 7 { s.scene = 1 }
   for _ in 0..<2 {
    rl.BeginDrawing()
    if shot == 7 { app.render_menu_background(r, s.animation) }
    else { app.render_frontend(r, &s) }
    if shot < 7 { app.draw_frontend_text(r, &s) }
    else if shot == 7 { menu := app.Menu_State{binding = -1, selected = 1}; app.draw_menu_panel(r, g, false, &menu, &saves, &prefs) }
    else { app.draw_win(r, g) }
    rl.EndDrawing()
   }
   path: [512]u8
   fmt.bprintf(path[:], "%s-%v-%d.png", prefix, language, shot)
   rl.TakeScreenshot(cstring(&path[0]))
   assert(gl.GetError() == 0)
  }
 }
}

// Entrance readability, target acquisition and the separate GC exit.
survey_lift :: proc(r: ^app.Renderer, g: ^game.State, prefix: string) {
	h: game.Pose_History
	v: game.Render_Snapshot
	for frame in 0..<5 {
		g.player.position = g.world.checkpoints[4].position
		g.lift_started = frame == 2
		g.player.yaw, g.player.pitch = -math.PI*0.5, 0
		cam := game.camera(g)
		if frame == 1 { game.aim_at(g, g.world.lift.button, true); cam = game.camera(g, true) }
		if frame >= 3 {
			g.boss.phase = .Dead if frame == 4 else .Dormant
			g.boss.timer = 0
			game.boss_exit_sync(g)
			c := game.boss_room_origin(g.world)
			from, target := c+game.Vec3{9, 4, -14}, c+game.Vec3{0, 3, -20}
			cam = {position = from, target = target, forward = game.normalized(target-from), scoped = true, fov = 60}
		}
		game.capture_poses(&h, g)
		game.render_snapshot(&v, g, &h, 1)
		for _ in 0..<2 { rl.BeginDrawing(); app.render_scene(r, &v, cam, 12); rl.EndDrawing() }
		path: [512]u8
		fmt.bprintf(path[:], "%s-lift-%d.png", prefix, frame)
		rl.TakeScreenshot(cstring(&path[0]))
		assert(gl.GetError() == 0)
	}
}
