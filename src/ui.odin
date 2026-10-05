package main

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import game "game"
import settings "settings"
import loc "locale"

UI :: struct {
	r: ^Renderer,
	scale, width, height: f32,
}

ui_context :: proc(r: ^Renderer) -> UI {
	w, h := f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())
	s := min(w/1280, h/800)
	return {r, s, w/s, h/s}
}

label :: proc(ui: UI, text: string, x, y, size: f32, color: rl.Color = PAPER, face: int = 0, spacing: f32 = 0.3) {
	buffer: [512]u8
	n := min(len(text), len(buffer)-1)
	copy(buffer[:n], text[:n])
	font := ui.r.font
	if face == 1 { font = ui.r.display }
	if face == 2 { font = ui.r.mono }
	rl.DrawTextEx(font, cstring(&buffer[0]), {x*ui.scale, y*ui.scale}, size*ui.scale, spacing*ui.scale, color)
}

text_width :: proc(ui: UI, text: string, size: f32, face: int = 0, spacing: f32 = 0.3) -> f32 {
 buffer: [512]u8
 copy(buffer[:len(buffer)-1], text)
 font := ui.r.font
 if face == 1 { font = ui.r.display }
 if face == 2 { font = ui.r.mono }
 return rl.MeasureTextEx(font, cstring(&buffer[0]), size, spacing).x
}

center_label :: proc(ui: UI, text: string, x, y, size: f32, color: rl.Color = PAPER, face: int = 0) {
 label(ui, text, x-text_width(ui, text, size, face)*0.5, y, size, color, face)
}

tr :: proc(ui: UI, key: loc.Key) -> string { return loc.text(ui.r.language, key) }

rect :: proc(ui: UI, x, y, w, h: f32, color: rl.Color) {
	rl.DrawRectangleRec({x*ui.scale, y*ui.scale, w*ui.scale, h*ui.scale}, color)
}

rule :: proc(ui: UI, x, y, w: f32, color: rl.Color) {
	rect(ui, x, y, w, 1, color)
}

diamond :: proc(ui: UI, x, y, radius: f32, color: rl.Color, filled: bool = false) {
	if filled {
		rl.DrawPoly({x*ui.scale, y*ui.scale}, 4, radius*ui.scale, 0, color)
	} else {
		rl.DrawPolyLinesEx({x*ui.scale, y*ui.scale}, 4, radius*ui.scale, 0, ui.scale, color)
	}
}

draw_markers :: proc(r: ^Renderer, g: ^game.State, cam: game.Camera) {
	ui := ui_context(r)
	rcam := rl.Camera3D{cam.position, cam.target, {0, 1, 0}, cam.fov, .PERSPECTIVE}
	if g.world.kind == .RAM { return }
	for core, i in g.cores[:g.core_count] {
		if core.collected { continue }
		p := core.position+game.Vec3{0, 1.3, 0}
		if game.dot(p-cam.position, cam.forward) <= 0 { continue }
		screen := rl.GetWorldToScreen(p, rcam)/ui.scale
		if screen.x < 30 || screen.x > ui.width-30 || screen.y < 100 || screen.y > ui.height-140 { continue }
		diamond(ui, screen.x, screen.y, 7, MINT)
		buf: [64]u8
		label(ui, fmt.bprintf(buf[:], "0%d / %.0f M", i+1, game.length(g.player.position-core.position)), screen.x+14, screen.y-7, 11, MINT, 2)
	}
	if g.collected == g.core_count {
		p := g.world.exit+game.Vec3{0, 4.7, 0}
		if game.dot(p-cam.position, cam.forward) > 0 {
			screen := rl.GetWorldToScreen(p, rcam)/ui.scale
			label(ui, "UPLINK / EXIT", screen.x-65, screen.y, 13, MINT, 2)
		}
	}
}

draw_scope :: proc(ui: UI) {
	cx, cy := ui.width*0.5, ui.height*0.5
	radius := ui.height*0.37
	center := rl.Vector2{cx, cy}*ui.scale
	rl.DrawRing(center, radius*ui.scale, (ui.width+ui.height)*ui.scale, 0, 360, 128, {3, 12, 17, 248})
	rl.DrawCircleLines(i32(center.x), i32(center.y), radius*ui.scale, fade(MINT, 0.7))
	rl.DrawCircleLines(i32(center.x), i32(center.y), (radius-5)*ui.scale, fade(MINT, 0.18))
	color := fade(MINT, 0.55)
	rule(ui, cx-radius+12, cy, radius-42, color)
	rule(ui, cx+30, cy, radius-42, color)
	rect(ui, cx, cy-radius+12, 1, radius-42, color)
	rect(ui, cx, cy+30, 1, radius-42, color)
	for i in 1..<5 {
		offset := f32(i)*radius*0.15
		signs := [2]f32{-1, 1}
		for sign in signs {
			rect(ui, cx+offset*sign, cy-4, 1, 9, color)
			rule(ui, cx-4, cy+offset*sign, 9, color)
		}
	}
	label(ui, "OPTIC / 2.9X", cx-radius+30, cy-radius+55, 11, MINT, 2)
}

draw_hud :: proc(r: ^Renderer, g: ^game.State, focused, debug, muted: bool, sim_ms, frame_ms, p95: f64, preferences: ^settings.Data = nil) {
	ui := ui_context(r)
	buf: [128]u8
	p := &g.player
	if focused { draw_scope(ui) }
	rl.DrawRectangleGradientV(0, 0, r.width, i32(128*ui.scale), {4, 17, 23, 205}, {4, 17, 23, 0})
	rl.DrawRectangleGradientV(0, r.height-i32(190*ui.scale), r.width, i32(190*ui.scale), {4, 17, 23, 0}, {4, 17, 23, 225})
	if g.world.kind == .RAM {
		use_key := binding_name(preferences.bindings[.Use], buf[:]) if preferences != nil else "E"
		draw_mission_hud(ui, g, use_key)
	} else {
		label(ui, "TOAD / RAM ARRAY", 34, 29, 17, PAPER, 1)
		label(ui, "REACH THE UPLINK" if g.collected == g.core_count else "RECOVER THE SIGNALS", 35, 59, 11, MINT, 2, 0.8)
		for i in 0..<min(g.core_count, 5) {
			diamond(ui, ui.width-227+f32(i)*27, 42, 7, MINT if g.cores[i].collected else MUTED, g.cores[i].collected)
		}
		label(ui, fmt.bprintf(buf[:], "%d / %d", g.collected, g.core_count), ui.width-129, 31, 23, PAPER, 2)
	}
	label(ui, fmt.bprintf(buf[:], "%02d:%02d", int(g.time)/60, int(g.time)%60), ui.width-105, 67, 12, MUTED, 2)
	cx, cy := ui.width*0.5, ui.height*0.5
	color := ORANGE if p.hit_marker > 0 else PAPER
	gap := 5+p.recoil*2.5+(p.weapon_bloom*5 if !focused else 0)
	rule(ui, cx-14, cy, 14-gap, color)
	rule(ui, cx+gap, cy, 14-gap, color)
	rect(ui, cx, cy-14, 1, 14-gap, color)
	rect(ui, cx, cy+gap, 1, 14-gap, color)
	rect(ui, cx-1, cy-1, 2, 2, MINT)
	if p.hit_marker > 0 {
		for i in 0..<4 {
			a := (f32(i)*math.PI*0.5+math.PI*0.25)
			v := rl.Vector2{math.cos(a), math.sin(a)}
			rl.DrawLineEx((rl.Vector2{cx, cy}+v*17)*ui.scale, (rl.Vector2{cx, cy}+v*24)*ui.scale, ui.scale*2, ORANGE)
		}
	}
	label(ui, tr(ui, .Health), 35, ui.height-118, 10, MUTED, 2, 1.3)
	label(ui, fmt.bprintf(buf[:], "%03d", int(p.health)), 33, ui.height-99, 35, PAPER, 1)
	for i in 0..<10 {
		segment_color := fade(MUTED, 0.3)
		if f32(i)*10 < p.health { segment_color = MINT if p.health > 30 else RED }
		rect(ui, 36+f32(i)*15, ui.height-48, 11, 4, segment_color)
	}
	mode := tr(ui, .Grounded)
	if !p.grounded { mode = tr(ui, .Airborne) }
	if p.gliding { mode = tr(ui, .Gliding) }
	if p.gliding && p.in_current { mode = tr(ui, .Updraft) }
	center_label(ui, mode, cx, 30, 13, MINT if p.gliding else PAPER, 2)
	label(ui, fmt.bprintf(buf[:], "%.0f M/S   /   ALT %.0f M", game.length(p.velocity), p.position.y), cx-95, 54, 11, MUTED, 2)
	for i in 0..<16 {
		ready := f32(i)/16 < 1-p.dash_cooldown/game.DASH_COOLDOWN
		rect(ui, cx-64+f32(i)*8, 80, 5, 3, ORANGE if ready else fade(MUTED, 0.25))
	}
	label(ui, tr(ui, .Shotgun if p.weapon == .Shotgun else (.Fragmentator if p.weapon == .Fragmentator else .Repeater)), ui.width-193, ui.height-116, 12, MUTED, 2)
	rounds := p.shotgun_ammo if p.weapon == .Shotgun else p.fragment_ammo
	ammo := fmt.bprintf(buf[:], "%02d %s", rounds, tr(ui, .Shells if p.weapon == .Shotgun else .Charges)) if p.weapon != .Repeater else tr(ui, .Unlimited)
	label(ui, ammo, ui.width-223, ui.height-92, 21, PAPER if p.weapon == .Repeater || rounds > 0 else ORANGE, 1)
	if p.shotgun_unlocked { label(ui, fmt.bprintf(buf[:], "02 / %02d", p.shotgun_ammo), ui.width-193, ui.height-135, 10, ORANGE, 2) }
	if p.fragment_unlocked { label(ui, fmt.bprintf(buf[:], "03 / %02d", p.fragment_ammo), ui.width-103, ui.height-135, 10, ORANGE, 2) }
	label(ui, fmt.bprintf(buf[:], "%s  %d / %d", tr(ui, .Hostiles), g.kills, g.enemy_total), ui.width-194, ui.height-51, 11, MUTED, 2)
	if muted { label(ui, tr(ui, .Muted), ui.width-83, ui.height-22, 10, MUTED, 2) }
	draw_level_title(ui, g)
	if g.message_time > 0 && (g.world.kind == .Arena || g.message >= 10 && g.message <= 13) {
		text := "JUMP, RELEASE, THEN PRESS + HOLD TO GLIDE. RIDE THE GREEN UPDRAFTS."
		if g.message == 2 { text = "SIGNAL RECOVERED / BACK AT YOUR LAST CHECKPOINT" }
		if g.message == 3 { text = "SIGNAL ACQUIRED / CHECKPOINT SAVED" }
		if g.message == 4 { text = "UPLINK ONLINE / REACH THE HIGHEST PLATFORM" }
		if g.message == 10 { text = tr(ui, .Premise) }
		if g.message == 11 { text = tr(ui, .Secret) }
		if g.message == 12 { text = tr(ui, .Anvil) }
		if g.message == 13 { text = tr(ui, .Pacifier) }
		center_label(ui, text, cx, 105, 12, MINT, 2)
	}
	if debug {
		rect(ui, 30, 143, 315, 120, {3, 13, 18, 220})
		label(ui, fmt.bprintf(buf[:], "FPS %d    FIXED SIM 120 HZ", rl.GetFPS()), 42, 155, 12, MINT, 2)
		label(ui, fmt.bprintf(buf[:], "SIM CPU    %.3f MS", sim_ms), 42, 181, 12, PAPER, 2)
		label(ui, fmt.bprintf(buf[:], "FRAME CPU  %.2f MS", frame_ms), 42, 206, 12, PAPER, 2)
		label(ui, fmt.bprintf(buf[:], "CPU P95    %.2f MS", p95), 42, 231, 12, PAPER, 2)
	}
}

draw_level_title :: proc(ui: UI, g: ^game.State) {
	if g.world.sector.key == .None || g.won || g.time <= 0.35 || g.time >= 5.5 { return }
	// Use the level clock: pausing stops the fade, and loading later progress
	// does not restart an introductory caption. This needs no saved UI state.
	opacity := min(clamp((g.time-0.35)/0.65, 0, 1), clamp((5.5-g.time)/1.2, 0, 1))
	title := tr(ui, .Cold_Boot) if g.world.sector.key == .RAM_Bank_01 else game.sector_definition(g.world.sector.key).title
	center_label(ui, title, ui.width*0.5, 155, 30, fade(PAPER, opacity), 1)
}

draw_win :: proc(r: ^Renderer, g: ^game.State) {
	ui := ui_context(r)
	rect(ui, 0, 0, ui.width, ui.height, {5, 20, 27, 220})
	x := ui.width*0.5-260
	label(ui, tr(ui, .Complete), x, 172, 13, MINT, 2, 1.8)
	label(ui, tr(ui, .Frog) if g.world.kind == .RAM else "SIGNAL", x-5, 210, 65, PAPER, 1, -2)
	label(ui, tr(ui, .Not_Here) if g.world.kind == .RAM else "RESTORED.", x-5, 280, 65, PAPER, 1, -2)
	buf: [128]u8
	label(ui, fmt.bprintf(buf[:], "%02d:%02d   /   %s %d / %d", int(g.time)/60, int(g.time)%60, tr(ui, .Hostiles), g.kills, g.enemy_total), x, 380, 14, MUTED, 2)
	rule(ui, x, 422, 500, fade(MINT, 0.4))
	if g.world.sector.key == .RAM_Bank_01 {
  label(ui, tr(ui, .End_Line), x, 464, 17, PAPER)
  label(ui, tr(ui, .End_Menu), x, 529, 13, PAPER, 2)
 } else { label(ui, "ENTER / CONTINUE    ESC / MENU" if game.campaign_next(g) != .None else "ESC / MENU", x, 510, 13, PAPER, 2) }
}
