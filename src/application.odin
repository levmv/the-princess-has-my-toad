package main

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import game "game"
import storage "storage"
import settings "settings"
import replay "replay"
import front "front"
import loc "locale"

// One owned application and one frame function serve desktop and browser.
// The simulation still runs at 120 Hz; presentation follows the host frame clock.
Application :: struct {
 smoke, capture_menu, muted, window_msaa, arena, no_save, no_audio, autostart, continue_game: bool,
 difficulty_explicit, language_explicit, hero_explicit: bool,
 sector: game.Sector_ID,
 seed: u32,
 difficulty: game.Difficulty,
 language: loc.Language,
 hero: game.Character,
 save_dir, config_dir, record_path, replay_path: string,
 room_id: game.Room_ID,
 debug_view: Debug_View,
 render_scale: f32,
 capture_page: Menu_Page,
 tape: replay.Tape,
 prefs: settings.Store,
 saves: storage.Store,
 g_world: game.World,
 g: game.State,
 audio: Audio,
 session: Play_Session,
 menu: Menu_State,
 opening: front.State,
 renderer: Renderer,
 debug, quit: bool,
 frames, exit_code: int,
 view: game.Render_Snapshot,
 sim_ms, frame_ms, p95: f64,
 samples: [240]f64,
 applied: settings.Data,
}

// Application owns large fixed buffers. Initialize the allocated instance
// directly so debug builds do not materialize a second whole application.
application_create :: proc() -> ^Application {
 a := new(Application)
 a.sector = .RAM_Bank_01
 a.seed = game.DEFAULT_SEED
 a.difficulty = .Hard
 a.language = .English
 a.hero = .Duke
 return a
}

application_init :: proc(a: ^Application, prepare_renderer: bool = true, prepare_audio: bool = true) -> bool {
	if a.replay_path != "" {
		if err := replay.read(&a.tape, a.replay_path); err != .None { fmt.eprintln(replay.error_text(err)); return false }
	}
	persistent := !a.no_save && !a.smoke && !a.capture_menu
	settings.init(&a.prefs, a.config_dir, persistent)
	if a.difficulty_explicit { a.prefs.data.difficulty = a.difficulty }
	if a.language_explicit { a.prefs.data.language = a.language; a.prefs.dirty = true }
	if a.hero_explicit { a.prefs.data.hero = a.hero }
	if a.muted { a.prefs.data.muted = true }
	if a.render_scale > 0 { a.prefs.data.render_scale = a.render_scale }
	storage.init(&a.saves, a.save_dir, persistent)
	rl.SetTraceLogLevel(.WARNING)
	flags := rl.ConfigFlags{}
	when ODIN_OS != .JS { flags += {.WINDOW_RESIZABLE} }
	if a.window_msaa { flags += {.MSAA_4X_HINT} }
	rl.SetConfigFlags(flags)
	rl.InitWindow(i32(a.prefs.data.width), i32(a.prefs.data.height), "THE PRINCESS HAS MY TOAD / Cold Boot")
	if !rl.IsWindowReady() { return false }
	rl.SetWindowMinSize(960, 600)
	rl.SetExitKey(.KEY_NULL)
	when ODIN_OS != .JS { rl.SetTargetFPS(144) }
	when ODIN_OS != .JS {
		if a.prefs.data.display == .Borderless { rl.ToggleBorderlessWindowed() }
	}
	if a.arena || a.smoke { game.world_init(&a.g_world, a.seed) } else { game.world_load_sector(&a.g_world, a.sector, a.seed) }
	a.g = game.State{world = &a.g_world, difficulty = a.prefs.data.difficulty, hero = a.prefs.data.hero}
	game.init(&a.g)
	if a.room_id != 0 {
		if !game.debug_enter_room(&a.g, a.room_id) { fmt.eprintln("Unknown or inaccessible room in this sector."); return false }
		fmt.printf("Developer room %d; persistence disabled.\n", a.room_id)
	}
	if a.replay_path != "" {
		if game.save_restore(&a.g, a.tape.initial) != .None { fmt.eprintln("Replay initial world could not be restored."); return false }
		a.tape.playing = true
	}
	if prepare_audio && !a.no_audio { audio_init(&a.audio, a.prefs.data.muted) }
	apply_preferences(&a.prefs.data, &a.prefs.data, &a.audio)
	a.session = Play_Session{started = a.smoke, checkpoint_sequence = a.g.checkpoint_sequence, tape = &a.tape, record_path = a.record_path}
	game.capture_poses(&a.session.history, &a.g)
	a.menu = Menu_State{binding = -1, page = a.capture_page}
	_, saved := storage.latest(&a.saves)
	if !saved && a.menu.page == .Root { a.menu.selected = 1 }
	for slot in storage.Slot {
		if a.saves.slots[slot].exists && !a.saves.slots[slot].valid {
			menu_notice(&a.menu, "A save could not be read. Only valid slots are available.", true)
			fmt.eprintf("Unreadable %s: %s\n", a.saves.paths[slot], storage.error_text(a.saves.slots[slot].error))
		}
	}
	if a.prefs.error.kind != .None { menu_notice(&a.menu, "Settings could not be read; defaults are in use.", true) }
	if a.continue_game {
		slot, available := storage.latest(&a.saves)
		if available { session_load(&a.session, &a.g, &a.audio, &a.saves, slot, &a.menu)
		} else { menu_notice(&a.menu, "No compatible save is available.", true) }
	} else if a.autostart {
		session_resume(&a.session, &a.g, &a.audio)
		session_save(&a.saves, &a.g, .Checkpoint, &a.menu)
	}
	if prepare_renderer {
		renderer_init(&a.renderer, &a.g)
		a.renderer.debug.view = a.debug_view
		debug_sync(&a.renderer.debug, &a.g_world)
	}
	a.applied = a.prefs.data
 return true
}

application_destroy :: proc(a: ^Application) {
 session_end_record(&a.session, &a.g)
 settings.flush(&a.prefs)
 renderer_destroy(&a.renderer)
 audio_destroy(&a.audio)
 game.world_destroy(&a.g_world)
 storage.destroy(&a.saves)
 settings.destroy(&a.prefs)
 replay.destroy(&a.tape)
 rl.EnableCursor()
 rl.CloseWindow()
}

application_frame :: proc(a: ^Application) -> bool {
 if a.quit { return false }
	when ODIN_OS != .JS { if rl.WindowShouldClose() { return false } }
	a.session.just_resumed = a.frames == 0 && a.session.started && !a.smoke
	frame_start := rl.GetTime()
	dt := clamp(rl.GetFrameTime(), 0, 0.1)
	if a.smoke { dt = 1.0/60.0 }
	poll_key_events()
	when ODIN_OS == .JS { web_prepare_frame(a) }
	had_death := a.session.death.active
	if had_death { session_death_input(&a.session, &a.g, &a.audio, dt) }
	a.menu.notice_time = max(0, a.menu.notice_time-dt)
	if ODIN_OS != .JS && key_pressed(.F11) { a.prefs.data.display = .Borderless if a.prefs.data.display == .Window else .Window; a.prefs.dirty = true }
	if key_pressed(.F3) { a.debug = !a.debug }
	if key_pressed(.M) { a.prefs.data.muted = !a.prefs.data.muted; a.prefs.dirty = true }
	if a.session.started && !a.session.paused && !a.session.death.active && !a.smoke && !a.tape.playing && !rl.IsWindowFocused() {
		session_pause(&a.session, &a.audio)
		a.menu.page, a.menu.selected, a.menu.binding = .Root, 0, -1
	}
  had_frontend := a.opening.phase != .None
  if !a.session.started || a.session.paused || had_frontend {
   if a.menu.binding < 0 { language_toggle(&a.renderer, &a.prefs) }
  }
  a.renderer.language = a.prefs.data.language
  begin_game := false
  if had_frontend {
   command := front.update(&a.opening, frontend_input(&a.opening, &a.renderer), dt)
   switch command {
   case .None:
   case .Begin: begin_game = true; a.prefs.data.hero, a.prefs.dirty = a.opening.hero, true
   case .Back: a.menu.page, a.menu.selected = .New_Game, 1
   case .Watched: a.menu.page, a.menu.selected = .Root, 3
   }
  }
  if !had_frontend && !had_death && key_pressed(.ESCAPE) {
		if a.tape.playing { a.quit = true
		} else if (!a.session.started || a.session.paused) && menu_back(&a.menu) {
			// Back stays within the menu and never resets a running level.
		} else if a.session.started {
			if a.session.paused { session_resume(&a.session, &a.g, &a.audio)
			} else { session_pause(&a.session, &a.audio); a.menu.page, a.menu.selected, a.menu.binding = .Root, 0, -1 }
		}
	}
	if !had_frontend && (!a.session.started || a.session.paused) {
		command := menu_update(&a.menu, &a.renderer, a.session.started, &a.saves, &a.prefs)
		switch command {
		case .None:
		case .Resume: session_resume(&a.session, &a.g, &a.audio)
		case .Continue:
			slot, available := storage.latest(&a.saves)
			if available { session_load(&a.session, &a.g, &a.audio, &a.saves, slot, &a.menu) }
		case .New_Game:
    front.start(&a.opening, a.prefs.data.hero)
    audio_pause(&a.audio)
		case .Intro:
    front.start(&a.opening, a.prefs.data.hero, replay_only = true)
    audio_pause(&a.audio)
		case .Save: session_save(&a.saves, &a.g, .Quick, &a.menu)
		case .Load: session_load(&a.session, &a.g, &a.audio, &a.saves, .Quick, &a.menu)
		case .Quit: a.quit = true
		}
	}
  if begin_game {
   if session_end_record(&a.session, &a.g) {
    wanted := game.Sector_ID.None if a.arena else a.sector
    if a.g.world.seed != a.seed || a.g.world.sector.key != wanted { game.world_load_sector(a.g.world, wanted, a.seed) }
    a.g.run = game.Run_State{difficulty = a.prefs.data.difficulty, hero = a.opening.hero}
    game.init(&a.g)
    a.menu.page, a.menu.selected = .Root, 0
    session_resume(&a.session, &a.g, &a.audio)
    session_save(&a.saves, &a.g, .Checkpoint, &a.menu)
   } else { menu_notice(&a.menu, "Could not write input recording.", true) }
  }
  showing_frontend := a.opening.phase != .None
	if !showing_frontend && !had_frontend && !had_death && !a.tape.playing && a.session.started && !a.session.just_resumed && (!a.session.paused || a.menu.page == .Root) && a.menu.binding < 0 {
		if binding_pressed(&a.prefs.data, .Quick_Save) { session_save(&a.saves, &a.g, .Quick, &a.menu) }
		if binding_pressed(&a.prefs.data, .Quick_Load) { session_load(&a.session, &a.g, &a.audio, &a.saves, .Quick, &a.menu) }
	}
	if !showing_frontend && !had_frontend && !a.tape.playing && a.g.won && a.session.started && !a.session.paused && !a.session.just_resumed && key_pressed(.ENTER) {
		if a.g.world.sector.key == .RAM_Bank_01 {
			session_pause(&a.session, &a.audio); a.menu.page, a.menu.selected = .Root, 3
		} else if session_end_record(&a.session, &a.g) && game.advance_campaign(&a.g) {
			session_resume(&a.session, &a.g, &a.audio)
			session_save(&a.saves, &a.g, .Checkpoint, &a.menu)
		}
	}
	if a.prefs.data.display != a.applied.display { a.session.just_resumed = true }
	apply_preferences(&a.prefs.data, &a.applied, &a.audio)
	a.applied = a.prefs.data
	a.renderer.render_scale = a.prefs.data.render_scale
	when ODIN_OS != .JS {
		if rl.IsWindowResized() && a.prefs.data.display == .Window {
			width, height := int(rl.GetScreenWidth()), int(rl.GetScreenHeight())
			if width != a.prefs.data.width || height != a.prefs.data.height {
				a.prefs.data.width, a.prefs.data.height, a.prefs.dirty = width, height, true
				a.applied = a.prefs.data
			}
		}
	}
	if a.prefs.dirty && (a.menu.page == .Root || (a.session.started && !a.session.paused)) {
		if err := settings.flush(&a.prefs); err.kind != .None {
			menu_notice(&a.menu, "Could not write settings.", true)
			fmt.eprintf("Settings write failed (%s): %s / %v\n", a.prefs.path, storage.error_text(err), err.system)
			a.prefs.dirty = false
		}
	}
	if a.record_path != "" && a.session.started && a.tape.initial == nil {
		if err := replay.begin(&a.tape, &a.g); err != .None { fmt.eprintln(replay.error_text(err)); a.quit = true }
	}
	if !showing_frontend && !a.session.death.active && a.session.started && !a.session.paused && !a.g.won && (!a.session.just_resumed || a.smoke) {
		input: game.Input
		if !a.tape.playing { input = smoke_input(&a.g, &a.session, a.frames) if a.smoke else session_input(&a.session, &a.g, &a.prefs.data) }
		if a.smoke { game.change_focus(&a.g, a.session.was_focused, input.focus) }
		was_won := a.g.won
		sim_start := rl.GetTime()
		session_simulate(&a.session, &a.g, input, dt, &a.audio)
		a.sim_ms = a.sim_ms*0.9+(rl.GetTime()-sim_start)*1000*0.1
		if a.g.checkpoint_sequence != a.session.checkpoint_sequence || (a.g.won && !was_won) {
			session_save(&a.saves, &a.g, .Checkpoint, &a.menu)
			a.session.checkpoint_sequence = a.g.checkpoint_sequence
		}
		if a.g.won { rl.EnableCursor() }
	}
	if a.tape.recording && a.tape.full {
		if !session_end_record(&a.session, &a.g) { menu_notice(&a.menu, "Could not write input recording.", true) }
	}
	if a.tape.playing && a.tape.cursor == a.tape.count {
		err := replay.verify(&a.tape, &a.g)
		fmt.printf("REPLAY %s: ticks=%d build=%s\n", replay.error_text(err), a.tape.cursor, game.BUILD_ID)
		if err != .None { a.exit_code = 1 }
		return false
	}
	alpha := f32(1)
	if a.session.started && !a.session.paused && !a.g.won { alpha = clamp(a.session.accumulator/game.STEP, 0, 1) }
	game.render_snapshot(&a.view, &a.g, &a.session.history, alpha)
	time := a.view.time
	if !a.session.started { time = 4 if a.capture_menu else f32(rl.GetTime()) }
	cam := game.camera(&a.view, a.session.was_focused)
	if !a.session.started {
		angle := f32(0.2)+math.sin(time*0.07)*0.12
		cam.position, cam.target = {41*math.cos(angle), 27, 20+41*math.sin(angle)}, {0, 4, -15}
		if a.g.world.kind == .RAM { cam.position = a.g.world.spawn+game.Vec3{6+math.sin(time*0.1)*0.3, 2.8, 1}; cam.target = a.g.world.spawn+game.Vec3{-3, 1.4, -26} }
		cam.forward, cam.fov = game.normalized(cam.target-cam.position), 55
	}
	frontend_audio := showing_frontend || !a.session.started
	audio_update_streams(&a.audio, &a.g, frontend_audio, rl.IsWindowFocused() && (frontend_audio || (!a.session.paused && !a.session.death.active)))
  rl.BeginDrawing()
  if showing_frontend {
   render_frontend(&a.renderer, &a.opening)
   draw_frontend_text(&a.renderer, &a.opening)
  } else if a.session.death.active {
   draw_death_screen(&a.renderer, a.session.death)
  } else {
   if !a.session.started {
    background := front.State{phase = .Intro, scene = 1, elapsed = 3, animation = time}
    render_frontend(&a.renderer, &background, background = true)
   } else { render_scene(&a.renderer, &a.view, cam, time) }
	draw_debug_ai(&a.renderer, &a.g, cam)
	if !a.session.started || a.session.paused {
		draw_menu_panel(&a.renderer, &a.g, a.session.started, &a.menu, &a.saves, &a.prefs)
	} else {
		draw_markers(&a.renderer, &a.g, cam)
		draw_hud(&a.renderer, &a.g, a.session.was_focused, a.debug, a.audio.muted, a.sim_ms, a.frame_ms, a.p95, &a.prefs.data)
		if a.g.won { draw_win(&a.renderer, &a.g) }
	}
	draw_notice(&a.renderer, &a.menu, a.session.started && !a.session.paused)
  }
	cpu_ms := (rl.GetTime()-frame_start)*1000
	a.frame_ms = a.frame_ms*0.92+cpu_ms*0.08
	a.samples[a.frames % len(a.samples)] = cpu_ms
	if a.frames > 0 && a.frames % 240 == 0 {
		ordered := a.samples
		for i in 1..<len(ordered) {
			value := ordered[i]
			j := i-1
			for j >= 0 && ordered[j] > value { ordered[j+1] = ordered[j]; j -= 1 }
			ordered[j+1] = value
		}
		a.p95 = ordered[228]
	}
	rl.EndDrawing()
	a.frames += 1
	if a.smoke && a.frames == 70 { rl.TakeScreenshot("build/gameplay.png") }
	if a.smoke && a.frames == 175 { rl.TakeScreenshot("build/third-person.png") }
	if a.smoke && a.frames == 188 { rl.TakeScreenshot("build/scope.png") }
	if a.smoke && a.frames == 240 { rl.TakeScreenshot("build/tunnel.png") }
	if a.smoke && a.frames == 250 { rl.TakeScreenshot("build/explosion-light.png") }
	if a.smoke && a.frames == 315 { rl.TakeScreenshot("build/camera-wall.png") }
	if a.capture_menu && a.frames == 3 { rl.TakeScreenshot("build/menu.png"); return false }
	if a.smoke && a.frames == 330 {
		fmt.printf("SMOKE OK: frames=%d shots=%d jumps=%d glides=%d lands=%d position=%v frame_cpu=%.2fms sim_cpu=%.3fms\n", a.frames, a.g.shot_sequence, a.g.jump_sequence, a.g.glide_sequence, a.g.land_sequence, a.g.player.position, a.frame_ms, a.sim_ms)
		assert(a.g.shot_sequence > 0 && a.g.jump_sequence > 0 && a.g.glide_sequence > 0 && a.g.land_sequence > 0)
		return false
	}
 return !a.quit
}
