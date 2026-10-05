package render_checks

import "core:fmt"
import "core:math"
import "core:mem"
import gl "vendor:OpenGL"
import rl "vendor:raylib"
import app "../../src"
import game "../../src/game"
import settings "../../src/settings"
import storage "../../src/storage"
import front "../../src/front"
import loc "../../src/locale"

main :: proc() {
	rl.SetTraceLogLevel(.WARNING)
	rl.SetConfigFlags({.WINDOW_HIDDEN})
	rl.InitWindow(1280, 800, "Renderer regression")
	assert(rl.IsWindowReady())
	defer rl.CloseWindow()
	a, b: game.World
	game.world_init(&a)
	game.world_init(&b, 42)
	defer game.world_destroy(&a)
	defer game.world_destroy(&b)
	g := game.State{world = &a}
	game.init(&g)
	r: app.Renderer
	app.renderer_init(&r, &g)
	fmt.printf("GL: %s | %s\n", gl.GetString(gl.RENDERER), gl.GetString(gl.VERSION))
	defer app.renderer_destroy(&r)
	// Switching to the prepared intro and back must preserve level buffers.
	level_vao := r.chunks[0].mesh.vaoId
	level_vertices := r.architecture_vertices
	app.sync_world_mesh(&r, &r.theatre)
	stage_vao := r.chunks[0].mesh.vaoId
	{
		context.allocator, context.temp_allocator = mem.panic_allocator(), mem.panic_allocator()
		for _ in 0..<3 {
			app.sync_world_mesh(&r, &a)
			assert(r.chunks[0].mesh.vaoId == level_vao && r.architecture_vertices == level_vertices)
			app.sync_world_mesh(&r, &r.theatre)
			assert(r.chunks[0].mesh.vaoId == stage_vao)
		}
		app.sync_world_mesh(&r, &a)
	}
	// Cached values at shared triangle corners agree with independent ray tests.
	mesh: app.Mesh_Builder
	app.mesh_block(&mesh, &a, a.blocks[0], rl.WHITE, rl.WHITE)
	for i := 0; i < len(mesh.positions); i += 17 {
		assert(abs(mesh.uv[i].x-app.ambient_visibility(&a, mesh.positions[i], mesh.normals[i])) < 0.000001)
	}
	app.mesh_destroy_builder(&mesh)
	sounds: app.Audio
	app.audio_init(&sounds, true)
	defer app.audio_destroy(&sounds)
	// Exercise decoding, aliases and playback without producing audible sound.
	// The audio device's master gain remains zero throughout this test.
	sounds.muted = false
	check_audio_transport(&sounds, &g)
	// Validate generated cues even on a machine with no audio device.
	for cue in game.Sound_Cue {
		kind := app.cue_sound(cue)
		// Finished recordings are decoded and uploaded by audio_init above.
		if kind in app.RECORDED_SOUNDS { continue }
		for variant in 0..<4 {
			samples: [22050]f32
			count := app.enemy_cue_samples(kind, variant, samples[:])
			energy := f32(0)
			for value in samples[:count] { assert(!math.is_nan(value) && abs(value) <= 0.75); energy += value*value }
			assert(energy/f32(count) > 0.00001 && abs(samples[0]) < 0.001 && abs(samples[count-1]) < 0.003)
		}
	}
	vertices := r.architecture_vertices
	game.add_block(&a, {0, 16, -20}, {3, 3, 3})
	game.world_commit(&a)
	app.sync_world_mesh(&r, &a)
	assert(r.world_revision == a.revision && r.architecture_vertices > vertices, "Committed geometry was not uploaded")
	// Independent levels may legitimately have the same revision number.
	b.revision, b.index_revision = a.revision, a.revision
	app.sync_world_mesh(&r, &b)
	assert(r.world_source == &b && r.material_seed == 42, "Renderer reused another world's cache")
	g.world = &b
	game.init(&g)
	h: game.Pose_History
	v: game.Render_Snapshot
	game.capture_poses(&h, &g)
	game.render_snapshot(&v, &g, &h, 1)
	rl.BeginDrawing()
	app.render_scene(&r, &v, game.camera(&v), 0)
	rl.EndDrawing()
	// Exercise the weighted mesh in airborne, landing, strafing and scoped
	// poses. Invalid weights or transforms can render without a GL error.
	for character in game.Character {
	g.hero = character
	skin: app.Skin_Builder
	if character == .Duke { app.build_hero(&skin) } else { app.build_lora(&skin) }
	defer app.mesh_destroy_builder(&skin.mesh)
	defer delete(skin.weights)
	assert(len(skin.weights) == len(skin.mesh.positions))
	for pose in 0..<14 {
		g.shot_sequence += 3
		g.jump_sequence += 1
		g.land_sequence += 1
		g.step_sequence += 1
		g.glide_sequence += 1
		app.audio_update(&sounds, &g)
		app.audio_update_streams(&sounds, &g, false, true)
		g.player.yaw = f32(pose)*0.7
		g.player.pitch = -0.8+f32(pose)*0.3
		g.player.grounded = pose%2 == 0
		g.player.air_time = 0.3
		g.player.velocity = {9, 0, -8}
		g.player.gait_phase = f32(pose)*1.2
		g.player.land_time, g.player.land_strength = 0.12, 0.9
		g.player.gliding = pose == 3
		g.player.glide_blend = 1 if pose == 3 else 0
		g.player.kick_time = game.KICK_DURATION-f32(pose-5)*0.075 if pose >= 6 else 0
		g.player.weapon = .Shotgun if pose >= 10 else (.Fragmentator if pose >= 6 else .Repeater)
		g.player.fragment_unlocked, g.player.fragment_ammo = true, 8
		g.player.shotgun_unlocked, g.player.shotgun_ammo = true, 12
		if pose >= 10 {
			g.player.pitch, g.player.grounded, g.player.velocity = 0, true, {}
			g.player.land_time, g.player.kick_time, g.player.invulnerable = 0, 0, 0
			g.player.idle_time = 7 if pose == 10 else (12.5 if pose == 11 else (17.25 if pose == 12 else 0))
			g.player.hurt_time = 0.14 if pose == 13 else 0
   g.player.hurt_strength = 1
		}
		game.capture_poses(&h, &g)
		game.render_snapshot(&v, &g, &h, 1)
		rl.BeginDrawing()
		app.render_scene(&r, &v, game.camera(&v, pose == 5), g.time)
		rl.EndDrawing()
		for p, i in skin.mesh.positions {
			weights := skin.weights[i]
			assert(abs(weights.z+weights.w-1) < 0.00001 && weights.z >= 0 && weights.w >= 0)
			result: game.Vec3
			for blend in 0..<2 {
				bone := int(weights[blend])
				assert(bone >= 0 && bone < len(r.hero.bones))
				m := r.hero.bones[app.Hero_Bone(bone)]
				for axis in 0..<3 { result[axis] += (m[0][axis]*p.x+m[1][axis]*p.y+m[2][axis]*p.z+m[3][axis])*weights[blend+2] }
			}
			distance := game.length(result-g.player.position)
			assert(!math.is_nan(distance) && distance < 2.1, "Skin escaped the character bounds")
			assert(result.y >= g.player.position.y-0.055, "Skin penetrates the floor")
		}
	}
	}
	// Replace an arena with the longer sector without replacing shared models.
	// Exercise the patterned material, star field, dormant/active fan and shot switch.
	game.world_init_ram(&b, 42)
	game.init(&g)
	g.player.position = b.checkpoints[4].position
	for powered in 0..<2 {
		g.lift_started = powered == 1
		game.capture_poses(&h, &g)
		game.render_snapshot(&v, &g, &h, 1)
		rl.BeginDrawing()
		app.render_scene(&r, &v, game.camera(&v), g.time)
		rl.EndDrawing()
	}
	// Moving collision doors are instances, not a reason to rebuild the world.
	static_revision := r.world_revision
	g.player.position = {126, 0.03, -235}
	g.player.yaw = math.PI
	for pose in 0..<3 {
		b.gates[0].amount, b.gates[0].open = f32(pose)*0.5, pose > 0
		game.capture_poses(&h, &g)
		game.render_snapshot(&v, &g, &h, 1)
		{
			context.allocator = mem.panic_allocator()
			context.temp_allocator = mem.panic_allocator()
			rl.BeginDrawing()
			app.render_scene(&r, &v, game.camera(&v), g.time)
			rl.EndDrawing()
		}
		assert(r.world_revision == static_revision && gl.GetError() == 0)
	}
	// Restoring gameplay in the same sector must keep uploaded architecture.
	saved: game.Save_Data
	assert(game.save_capture(&saved, &g, .Quick, 1) == .None)
	g.player.position = b.spawn
	assert(game.save_restore(&g, &saved) == .None)
	app.audio_pause(&sounds)
	app.audio_sync(&sounds, &g)
	game.capture_poses(&h, &g)
	game.render_snapshot(&v, &g, &h, 1)
	saves: storage.Store
	preferences := settings.Store{data = settings.defaults()}
	for page in app.Menu_Page {
		menu := app.Menu_State{page = page, binding = -1}
		{
			context.allocator = mem.panic_allocator()
			context.temp_allocator = mem.panic_allocator()
			rl.BeginDrawing()
			app.render_menu_background(&r, 4)
			app.draw_menu_panel(&r, &g, false, &menu, &saves, &preferences)
			rl.EndDrawing()
		}
		assert(r.world_revision == static_revision && gl.GetError() == 0, "Quickload or menu invalidated static GPU data")
	}
 // Every intro shot, both selectable skins, both languages. Warm the stage
 // before asserting frame allocation (changing worlds is a loading boundary).
 opening := front.State{phase = .Intro, scene = 0, elapsed = 1, animation = 1}
 rl.BeginDrawing(); app.render_frontend(&r, &opening); rl.EndDrawing()
 assert(r.damage_location >= 0, "Damage vignette uniform is missing")
 for language in loc.Language {
  r.language = language
  {
   context.allocator, context.temp_allocator = mem.panic_allocator(), mem.panic_allocator()
   for cause in game.Death_Cause {
    rl.BeginDrawing(); app.draw_death_screen(&r, {active = true, age = 1, cause = cause}); rl.EndDrawing()
    assert(gl.GetError() == 0)
   }
  }
  for shot in 0..<len(front.DURATION)+2 {
   opening.scene, opening.phase = min(shot, len(front.DURATION)-1), .Intro if shot < len(front.DURATION) else .Fighter
   opening.hero = .Duke if shot == len(front.DURATION) else .Lora
   {
    context.allocator, context.temp_allocator = mem.panic_allocator(), mem.panic_allocator()
    rl.BeginDrawing()
    app.render_frontend(&r, &opening)
    app.draw_frontend_text(&r, &opening)
    rl.EndDrawing()
   }
   assert(gl.GetError() == 0 && r.objects.count < app.INSTANCE_CAPACITY)
  }
 }
 // Advancing early must not jump the camera before the continuous pullback.
 for early in ([3]f32{0.3, 1.5, 3}) {
  opening.phase, opening.scene, opening.elapsed = .Intro, 1, early
  close := app.frontend_camera(&opening)
  opening.scene, opening.elapsed = 2, 0
  reveal := app.frontend_camera(&opening)
  assert(close.position == reveal.position && close.target == reveal.target && close.fov == reveal.fov)
 }
 for font in ([3]rl.Font{r.font, r.display, r.mono}) {
  for point in ([4]rune{'Ж', 'Я', 'ё', 'Ю'}) { assert(font.glyphs[rl.GetGlyphIndex(font, point)].value == point, "Missing Cyrillic glyph") }
 }
 app.sync_world_mesh(&r, g.world)
	// The authored boss uses static shell collision and animated shared meshes.
	// Every phase and the falling joke must fit the same allocation-free frame.
	g.lift_started = true
	g.player.position = game.boss_room_origin(&b)+game.Vec3{0, 0.04, 14}
	for phase in game.Boss_Phase {
		g.boss.stage, g.boss.health = 2, 12
		game.boss_plan(&g)
		game.boss_phase(&g.boss, phase, 2)
		g.boss.timer = 1
		if phase == .Dead { g.boss.health = 0 }
		game.drop_anvil(&g)
		game.capture_poses(&h, &g)
		game.render_snapshot(&v, &g, &h, 0.5)
		{
			context.allocator, context.temp_allocator = mem.panic_allocator(), mem.panic_allocator()
			rl.BeginDrawing()
			app.render_scene(&r, &v, game.camera(&v), 12)
			app.audio_update(&sounds, &g)
			rl.EndDrawing()
		}
		assert(r.world_revision == static_revision && gl.GetError() == 0)
	}
	// The transfer room deliberately has no shot switch, fan, actors or checkpoints.
	// Exercise the real campaign transition and renderer cache invalidation.
	g.lift_started, g.won = true, true
	assert(game.advance_campaign(&g))
	game.capture_poses(&h, &g)
	game.render_snapshot(&v, &g, &h, 1)
	rl.BeginDrawing()
	app.render_scene(&r, &v, game.camera(&v), g.time)
	app.draw_hud(&r, &g, false, false, true, 0, 0, 0)
	rl.EndDrawing()
	assert(r.world_revision == b.revision && b.sector.key == .RAM_Transfer && b.gate_count == 0)
	// All actor models, floor effects and a live support link share the
	// normal instancing/shadow path. Exercise every telegraph at pool capacity.
	game.world_load_sector(&b, .RAM_Combat_Lab, 42)
	game.init(&g)
	app.sync_world_mesh(&r, &b)
	for &enemy in g.enemies { enemy.health = 0 }
	for i in 0..<game.ENEMY_CAPACITY {
		kind := game.Enemy_Kind(i%len([game.Enemy_Kind]int{}))
		position := game.Vec3{f32(i%8)*3+32, game.enemy_extent(kind).y+0.04, f32(i/8)*2.2-43}
		_, ok := game.spawn_enemy(&g, position, 10, 0, kind)
		assert(ok)
		g.enemies[i].phase, g.enemies[i].phase_time = .Windup, 0.27
		g.enemies[i].attack_target = position-game.Vec3{0, position.y-0.04, 0}
		game.enemy_warning(&g, &g.enemies[i])
	}
	// One opened support umbrella and its linked ally in the crowded scene.
	g.enemies[4].phase, g.enemies[4].phase_time, g.enemies[4].shield = .Attack, 1, 6
	g.enemies[4].support = {u32(3), g.enemies[3].generation}
	for i in 0..<len(g.hazards) { assert(game.spawn_floor_hazard(&g, {f32(i%6)*3+35, 0.04, f32(i/6)*3-35}, 2.8)) }
	for &particle, i in g.particles { particle = {{f32(i%16)*2+29, 2, f32(i/16)*1.1-43}, {}, 1, 1, 0.06, i%7} }
	for &gib, i in g.gibs { gib = {{f32(i%8)*2+29, 1.5, f32(i/8)*1.1-40}, {}, 6, 6, 0.2, i%3} }
	for &bullet, i in g.projectiles {
		sources := [3]game.Death_Cause{.Fairy, .Nanny, .GC}
		bullet = {{f32(i%8)*3+32, 3, f32(i/8)*3-40}, {0, 0, 10}, 1, sources[i%3]}
	}
	for &fragment, i in g.fragments { fragment = {{f32(i%4)*3+37, 2.5, f32(i/4)*3-38}, {0, 0, -20}, 1} }
	g.player.position = {44, 0, -16}
	game.capture_poses(&h, &g)
	game.render_snapshot(&v, &g, &h, 1)
	{
		context.allocator = mem.panic_allocator()
		context.temp_allocator = mem.panic_allocator()
		rl.BeginDrawing()
		app.render_scene(&r, &v, game.camera(&v), 0)
		app.audio_update(&sounds, &g)
		rl.EndDrawing()
	}
	assert(r.objects.count < app.INSTANCE_CAPACITY)
	assert(gl.GetError() == 0, "GL error after world replacement")
	// Scale only the 3D target; the framebuffer/UI dimensions stay unchanged.
	for scale in ([3]f32{0.75, 0.5, 1}) {
		r.render_scale = scale
		app.resize_render_target(&r)
		assert(r.width == 1280 && r.height == 800 && r.target.texture.width == i32(1280*scale) && r.target.texture.height == i32(800*scale))
		{
			context.allocator, context.temp_allocator = mem.panic_allocator(), mem.panic_allocator()
			rl.BeginDrawing(); app.render_scene(&r, &v, game.camera(&v), 0); app.draw_hud(&r, &g, false, false, true, 0, 0, 0); rl.EndDrawing()
		}
		assert(gl.GetError() == 0)
	}
	r.debug.view = .All
	app.debug_sync(&r.debug, g.world)
	{
		context.allocator, context.temp_allocator = mem.panic_allocator(), mem.panic_allocator()
		rl.BeginDrawing(); app.render_scene(&r, &v, game.camera(&v), 0); app.draw_debug_ai(&r, &g, game.camera(&v)); rl.EndDrawing()
	}
	assert(gl.GetError() == 0)
	r.debug.view = .None
	for progress in 0..<4 {
		for &e in g.enemies {
			e.health, e.phase = 0, .Recover
			e.phase_time = game.enemy_death_duration(e.kind)*max(0, 0.95-f32(progress)*0.4)
		}
		game.capture_poses(&h, &g)
		game.render_snapshot(&v, &g, &h, 1)
		{
			context.allocator, context.temp_allocator = mem.panic_allocator(), mem.panic_allocator()
			// Second frame exercises cached support offsets for settled wrecks.
			for _ in 0..<2 {
				rl.BeginDrawing()
				app.render_scene(&r, &v, game.camera(&v), 0)
				app.audio_update(&sounds, &g)
				app.audio_update_streams(&sounds, &g, false, true)
				rl.EndDrawing()
			}
		}
		hulls := 0
		for &command in r.objects.commands[:r.objects.count] {
			for column in command.instance.transform { for value in column { assert(!math.is_nan(value) && !math.is_inf(value)) } }
			for column in command.instance.normal { for value in column { assert(!math.is_nan(value) && !math.is_inf(value)) } }
			if command.kind == .SentryHull || command.kind == .InterceptorHull || command.kind == .CrabShell || command.kind == .KettleBody || command.kind == .NannyBody || command.kind == .RabbitBody {
				hulls += 1
				if progress == 3 {
     bottom := app.enemy_part_bottom(&r, &command)
     if command.kind == .SentryHull || command.kind == .InterceptorHull || command.kind == .RabbitBody { assert(bottom >= 0.062, "Organic torso penetrates its supporting floor")
     } else { assert(abs(bottom-0.065) < 0.003, "A settled wreck floats above its floor") }
    }
			}
		}
		assert(hulls == game.ENEMY_CAPACITY && r.objects.count < app.INSTANCE_CAPACITY && gl.GetError() == 0)
	}
	for &e in g.enemies { if game.enemy_organic(e.kind) { e.gibbed = true } }
	game.capture_poses(&h, &g)
	game.render_snapshot(&v, &g, &h, 1)
	{
		context.allocator, context.temp_allocator = mem.panic_allocator(), mem.panic_allocator()
		rl.BeginDrawing(); app.render_scene(&r, &v, game.camera(&v), 0); rl.EndDrawing()
	}
	assert(r.objects.count < app.INSTANCE_CAPACITY && gl.GetError() == 0)
	fmt.printf("RENDER CHECK OK: worlds/transfer, skinning/idle/hurt, shot switch, sky, same-sector quickload, four menu pages, GC phases/anvil, 128 mixed enemies/deaths and saturated effects (%d instances), cue synthesis/spatial audio/ambience, audio device=%v\n", r.objects.count, sounds.ready)
}

check_audio_transport :: proc(a: ^app.Audio, g: ^game.State) {
	if !a.ready || !a.music.ready || !a.ambience.ready {
		fmt.println("AUDIO TRANSPORT SKIPPED: no audio device/streams")
		return
	}
	// Slow the muted device so queue assertions don't race a 93 ms buffer
	// turnover. This exercises actual raylib queues, not a mock of our calls.
	rl.SetAudioStreamPitch(a.music.stream, 0.01)
	rl.SetAudioStreamPitch(a.ambience.stream, 0.01)
	defer rl.SetAudioStreamPitch(a.music.stream, 1)
	defer rl.SetAudioStreamPitch(a.ambience.stream, 1)
	app.audio_update_streams(a, g, false, true)
	assert(rl.IsAudioStreamPlaying(a.music.stream) && rl.IsAudioStreamPlaying(a.ambience.stream))
	app.audio_pause(a)
	frame, cursor := a.music.synth.frame, a.ambience.cursor
	assert(frame > 0 && cursor > 0)
	for _ in 0..<3 {
		app.audio_update_streams(a, g, false, false)
		assert(!rl.IsAudioStreamPlaying(a.music.stream) && !rl.IsAudioStreamPlaying(a.ambience.stream))
		assert(!rl.IsAudioStreamProcessed(a.music.stream) && !rl.IsAudioStreamProcessed(a.ambience.stream), "Starting or pausing discarded queued samples")
		app.audio_update_streams(a, g, false, true)
		app.audio_pause(a)
		assert(a.music.synth.frame == frame && a.ambience.cursor == cursor, "Resume skipped queued music or ambience")
	}
	app.audio_update_streams(a, g, true, true)
	assert(rl.IsAudioStreamPlaying(a.music.stream) && !rl.IsAudioStreamPlaying(a.ambience.stream))
	app.audio_update_streams(a, g, false, false)
	assert(!rl.IsAudioStreamPlaying(a.music.stream), "Cancelling the intro leaked music into a paused game")
	was_won := g.won
	g.won = true
	app.audio_update_streams(a, g, false, true)
	assert(rl.IsAudioStreamPlaying(a.music.stream) && rl.IsAudioStreamPlaying(a.ambience.stream))
	g.won = was_won
	app.audio_pause(a)
	fmt.println("AUDIO TRANSPORT OK: initial queue, repeated pause/resume, intro cancellation and win-screen playback")
}
