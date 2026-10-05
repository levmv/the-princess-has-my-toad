package main

import "core:unicode/utf8"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// Paper and cut-out type are drawn at UI resolution. Only the photograph uses
// the existing 3D target, so the title remains sharp at reduced scene resolution.
paper_transform :: proc(ui: UI, x, y, angle: f32) {
	rlgl.PushMatrix()
	rlgl.Translatef(x*ui.scale, y*ui.scale, 0)
	rlgl.Rotatef(angle, 0, 0, 1)
}

paper_sheet :: proc(ui: UI, width, height: f32, seed: u32, color: rl.Color) {
	rect(ui, -width*0.5+8, -height*0.5+13, width, height, {0, 0, 0, 70})
	rect(ui, -width*0.5+3, -height*0.5+5, width, height, {0, 0, 0, 95})
	rect(ui, -width*0.5, -height*0.5, width, height, color)
	// Deterministic fibres; no image asset, random state or frame allocation.
	noise := seed
	for i in 0..<96 {
		noise = noise*1664525+1013904223
		x := f32(noise&65535)/65535*(width-10)-width*0.5+5
		noise = noise*1664525+1013904223
		y := f32(noise&65535)/65535*(height-8)-height*0.5+4
		rect(ui, x, y, min(f32(2+i%11), width*0.5-x-2), 0.6, {101, 76, 45, 26})
	}
}

ransom_line :: proc(ui: UI, text: string, y, size, width: f32, seed: int) {
	count := utf8.rune_count_in_string(text)
	cell := min(size*0.93, width/f32(count))
	x := -f32(count)*cell*0.5
	index := 0
	for point in text {
		defer index += 1
		defer x += cell
		if point == ' ' { continue }
		style := (index*7+seed)%11
		bytes, n := utf8.encode_rune(point)
		glyph := string(bytes[:n])
		face := style%3
		font_size := min(size, (cell-5)/text_width(ui, glyph, 1, face, 0))
		paper_transform(ui, x+cell*0.5, y+f32(style%3-1)*2, f32(style%7-3)*1.8)
		paper, ink := rl.Color{218, 213, 191, 255}, rl.Color{36, 32, 30, 255}
		if style == 0 || style == 4 { paper, ink = {37, 35, 34, 255}, {241, 228, 202, 255} }
		if style == 7 { paper, ink = {144, 38, 43, 255}, {250, 234, 203, 255} }
		rect(ui, -cell*0.5, -3, cell-1, size+8, {49, 32, 28, 38})
		rect(ui, -cell*0.5-1, -4, cell-1, size+7, paper)
		label(ui, glyph, -text_width(ui, glyph, font_size, face)*0.5-1, (size-font_size)*0.5-1, font_size, ink, face)
		rlgl.PopMatrix()
	}
}

draw_missing_poster :: proc(r: ^Renderer, elapsed: f32) {
	ui := ui_context(r)
	ink := rl.Color{43, 38, 32, 255}
	rl.DrawRectangleGradientV(0, 0, r.width, r.height, {36, 47, 53, 255}, {13, 23, 29, 255})
	// Offset the two overlapping sheets as a single composition on any aspect.
	center_x, center_y := ui.width*0.5, (97+ui.height-206)*0.5
	paper_transform(ui, center_x-184, center_y, -4)
	paper_sheet(ui, 416, 442, 14, {222, 211, 181, 255})
	center_label(ui, tr(ui, .Missing), 0, -203, 55, {133, 36, 36, 255}, 1)
	rect(ui, -184, -137, 368, 3, ink)
	// Crop a portrait from the same world render target instead of allocating a
	// second texture. A fixed pose makes this read as a photograph, not a window.
	tw, th := f32(r.target.texture.width), f32(r.target.texture.height)
	ph := min(th*0.81, tw*238/362)
	pw := ph*362/238
	rect(ui, -185, -128, 370, 246, {247, 240, 216, 255})
	rl.DrawTexturePro(r.target.texture, {(tw-pw)*0.5, (th-ph)*0.5, pw, -ph}, {-181*ui.scale, -124*ui.scale, 362*ui.scale, 238*ui.scale}, {}, 0, {233, 228, 210, 255})
	center_label(ui, tr(ui, .Missing_Line), 0, 133, 18, ink, 1)
	rect(ui, -184, 165, 368, 1, {140, 127, 103, 255})
	// Tear-off tabs carry a tiny frog footprint, rather than a fake phone number.
	for i in 0..<9 {
		x := f32(i)*41-164
		rect(ui, x+19, 174, 1, 43, {149, 137, 111, 255})
		rl.DrawCircleV({x*ui.scale, 197*ui.scale}, 4*ui.scale, ink)
		for toe in 0..<3 { rl.DrawCircleV({(x+f32(toe-1)*7)*ui.scale, (185+f32(abs(toe-1))*3)*ui.scale}, 2*ui.scale, ink) }
	}
	rect(ui, -163, -235, 84, 28, {185, 163, 111, 175})
	rect(ui, 104, -228, 64, 23, {185, 163, 111, 175})
	rlgl.PopMatrix()

	t := clamp((elapsed-0.16)/0.35, 0, 1)
	settle := t*t*(3-2*t)
	paper_transform(ui, center_x+174+(1-settle)*130, center_y+64, 5+(1-settle)*9)
	paper_sheet(ui, 462, 246, 117, {237, 226, 202, 255})
	// A folded sheet, flattened hastily over the missing poster.
	rect(ui, -1, -122, 2, 244, {145, 120, 84, 35})
	rect(ui, 1, -122, 1, 244, {255, 254, 235, 140})
	rect(ui, -230, 0, 460, 1, {132, 108, 80, 33})
	ransom_line(ui, tr(ui, .Ransom_0), -83, 31, 414, 7)
	ransom_line(ui, tr(ui, .Ransom_1), -29, 31, 414, 3)
	ransom_line(ui, tr(ui, .Ransom_Signature), 62, 23, 320, 5)
	rlgl.PopMatrix()
}
