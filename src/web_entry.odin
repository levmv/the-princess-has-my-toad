#+build js
package main

import "base:runtime"
import "core:mem"
import rl "vendor:raylib"
import loc "locale"
import settings "settings"
import front "front"

web_context: runtime.Context
web_app: ^Application
web_lost_pointer: bool

web_boot_stage: int
web_audio_stage: int
web_boot_failed: bool
web_boot_times: [10]f64
web_bake: Architecture_Bake

@export
toad_prepare :: proc "c" (language: i32) {
	context = runtime.default_context()
	if web_app != nil { return }
	context.allocator = {web_allocate, nil}
	runtime.init_global_temporary_allocator(2*mem.Megabyte)
	web_context = context
	web_app = application_create()
	if language >= 0 { web_app.language_explicit, web_app.language = true, loc.Language(language) }
}

@export
toad_boot_step :: proc "c" () -> f64 {
	context = web_context
	if web_boot_failed { return -1 }
	if web_boot_stage >= len(web_boot_times) { return 1 }
	a := web_app
	start := emscripten_get_now()
	finished := true
	switch web_boot_stage {
	case 0:
		if !application_init(a, prepare_renderer = false, prepare_audio = false) { web_boot_failed = true; return -1 }
		rl.SetTargetFPS(0)
	case 1, 2, 3, 4, 5:
		renderer_init_stage(&a.renderer, a.g_world.seed, web_boot_stage-1)
	case 6:
		finished = false
		for emscripten_get_now()-start < 8 {
			if bake_architecture_step(&web_bake, &a.renderer, &a.g_world) {
				finish_world_mesh(&a.renderer, &a.g_world)
				finished = true
				break
			}
		}
	case 7:
		sync_world_mesh(&a.renderer, &a.renderer.theatre)
	case 8:
		finished = false
		for emscripten_get_now()-start < 8 {
			finished = audio_init_step(&a.audio, a.prefs.data.muted, web_audio_stage)
			web_audio_stage += 1
			if finished { apply_preferences(&a.prefs.data, &a.prefs.data, &a.audio); break }
		}
	case 9:
		a.renderer.language = a.prefs.data.language
		a.renderer.render_scale = a.prefs.data.render_scale
		preview := front.State{phase = .Intro, scene = 1, elapsed = 3}
		rl.BeginDrawing()
		render_frontend(&a.renderer, &preview, background = true)
		rl.EndDrawing()
	}
	web_boot_times[web_boot_stage] += emscripten_get_now()-start
	if finished { web_boot_stage += 1 }
	free_all(context.temp_allocator)
	if web_boot_stage < 6 { return f64(web_boot_stage)*0.04 }
	if web_boot_stage == 6 { return 0.24+f64(bake_architecture_progress(&web_bake, &a.g_world))*0.60 }
	return 0.84+(f64(web_boot_stage-7)+(f64(web_audio_stage)/f64(AUDIO_LOAD_STEPS) if web_boot_stage == 8 else 0))*(0.16/3.0)
}

@export
toad_start :: proc "c" (language: i32) -> bool {
	context = web_context
	if web_app == nil || web_boot_stage < len(web_boot_times) { return false }
	a := web_app
	if language >= 0 && a.prefs.data.language != loc.Language(language) {
		a.prefs.data.language, a.prefs.dirty = loc.Language(language), true
	}
	a.quit, web_lost_pointer = false, false
	for rl.GetKeyPressed() != .KEY_NULL {}
	native_events = {}
	return true
}

@export
toad_suspend :: proc "c" () {
	context = web_context
	a := web_app
	if a == nil { return }
	if a.session.started { session_pause(&a.session, &a.audio) }
	audio_pause(&a.audio)
	settings.flush(&a.prefs)
	a.quit = false
	a.menu.page, a.menu.selected, a.menu.binding = .Root, 0, -1
	rl.EnableCursor()
}

@export
toad_frame :: proc "c" () -> bool {
	context = web_context
	if web_app == nil { return false }
	result := application_frame(web_app)
	free_all(context.temp_allocator)
	return result
}

@export
toad_playing :: proc "c" () -> bool {
	return web_app != nil && web_app.session.started && !web_app.session.paused && !web_app.session.death.active && !web_app.g.won
}

@export
toad_pointer_lost :: proc "c" () { web_lost_pointer = true }

web_prepare_frame :: proc(a: ^Application) {
	if !web_lost_pointer { return }
	web_lost_pointer = false
	native_events.pressed[int(rl.KeyboardKey.ESCAPE)] = false
	if a.session.started && !a.session.paused && !a.session.death.active {
		session_pause(&a.session, &a.audio)
		a.menu.page, a.menu.selected, a.menu.binding = .Root, 0, -1
	}
}

@export
toad_resize :: proc "c" (width, height: i32) {
	context = web_context
	if web_app == nil { return }
	// The page owns CSS size and DPR; raylib gets actual backing-store pixels.
	w, h := max(1, width), max(1, height)
	rl.SetWindowSize(w, h)
	// Backing pixels are transient browser state, not native window preferences.
	// Small canvases and high DPR must not invalidate unrelated saved settings.
}

@export
toad_end :: proc "c" () {
	context = web_context
	if web_app != nil { application_destroy(web_app); free(web_app); web_app = nil }
}

// Emscripten hosts frames; Odin still emits its normal runtime startup entry.
main :: proc() {}

// Read-only counters for the browser regression/performance harness.
@export
toad_metric :: proc "c" (field: i32) -> f64 {
	if web_app == nil { return 0 }
	a := web_app
	switch field {
	case 0: return f64(a.frames)
	case 1: return f64(a.g.time)
	case 2: return f64(a.g.player.position.x)
	case 3: return f64(a.g.player.position.y)
	case 4: return f64(a.g.player.position.z)
	case 5: return f64(a.g.player.health)
	case 6: return f64(a.g.shot_sequence)
	case 7: return f64(int(a.session.paused))
	case 8: return f64(int(a.opening.phase))
	case 9: return f64(int(a.g.hero))
	case 10: return f64(a.g.player.yaw)
	case 11: return f64(a.g.player.pitch)
	case 12: return f64(int(a.session.death.active))
	case 13: return f64(int(a.g.player.weapon))
	case 14: return f64(a.g.player.shotgun_ammo)
	case 15: return f64(a.g.player.fragment_ammo)
	case 16: return f64(int(a.audio.ready))
	case 17: return f64(a.g.glide_sequence)
	case 18: return f64(a.g.jump_sequence)
	case 19: return f64(a.frame_ms)
	case 20: return f64(a.sim_ms)
	case 21: return f64(a.g.player.shot_cooldown)
	case 22: return f64(a.prefs.data.sensitivity)
	case 23: return f64(web_boot_stage)
	case 24: return f64(a.renderer.width)
	case 25: return f64(a.renderer.height)
	case 26: return f64(a.renderer.target.texture.width)
	case 27: return f64(a.renderer.target.texture.height)
	case 28: return f64(a.prefs.data.render_scale)
	case 29: return f64(int(a.prefs.data.language))
	case 30..<40: return web_boot_times[field-30]
	}
	return 0
}
