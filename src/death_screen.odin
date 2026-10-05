package main

import rl "vendor:raylib"
import game "game"
import front "front"
import loc "locale"

draw_death_screen :: proc(r: ^Renderer, death: front.Death_Screen) {
	ui := ui_context(r)
	blue, paper := rl.Color{13, 27, 155, 255}, rl.Color{226, 231, 235, 255}
	// The target still contains the last gameplay frame, before the checkpoint
	// rewind. Reuse it without another world pass; resizing only crops the image.
	w, h := f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())
	factor := max(w/f32(r.target.texture.width), h/f32(r.target.texture.height))
	bw, bh := f32(r.target.texture.width)*factor, f32(r.target.texture.height)*factor
	// The usual world pass restores raylib's window viewport and projection.
	// Do that without clearing or redrawing the frozen target, also on resize.
	rl.BeginTextureMode(r.target)
	rl.EndTextureMode()
	rl.ClearBackground(INK)
	render_post_pass(r, {(w-bw)*0.5, (h-bh)*0.5, bw, bh})
	rect(ui, 0, 0, ui.width, ui.height, {0, 0, 0, 120})
	px, py := (ui.width-960)*0.5, (ui.height-480)*0.5
	rect(ui, px+7, py+7, 960, 480, {0, 0, 0, 100})
	rect(ui, px, py, 960, 480, blue)
	x, y := px+52, py+38
	rect(ui, x, y, text_width(ui, "THE PRINCESS HAS MY TOAD", 15, 2)+24, 26, paper)
	label(ui, "THE PRINCESS HAS MY TOAD", x+12, y+5, 15, blue, 2)
	label(ui, "X_X", x, y+50, 40, paper, 2)
	label(ui, tr(ui, .Death_Title), x, y+115, 20, paper, 2)
	label(ui, tr(ui, .Death_Line), x, y+152, 16, paper, 2)
	keys := [game.Death_Cause]loc.Key{.Unknown = .Killer_Unknown, .Fairy = .Killer_Fairy, .Hunter = .Killer_Hunter, .Crab = .Killer_Crab, .Kettle = .Killer_Kettle, .GC = .Killer_GC, .Fragment = .Killer_Fragment, .Void = .Killer_Void, .Anvil = .Killer_Anvil, .Nanny = .Killer_Nanny, .Rabbit = .Killer_Rabbit}
	label(ui, tr(ui, .Death_Killer), x, y+203, 17, paper, 2)
	label(ui, tr(ui, keys[death.cause]), x+143, y+203, 17, paper, 2)
	label(ui, "*** STOP: 0x00000DEAD / HERO_NOT_RESPONDING", x, y+248, 15, paper, 2)
	label(ui, tr(ui, .Death_Frog), x, y+288, 16, paper, 2)
	label(ui, tr(ui, .Death_Retry if death.age >= 0.5 else .Death_Wait), x, y+368, 16, paper, 2)
}
