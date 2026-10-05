package main

import "core:fmt"
import settings "settings"

draw_wing_hint :: proc(r: ^Renderer, opacity: f32, preferences: ^settings.Data) {
	if opacity <= 0 { return }
	ui := ui_context(r)
	key_buffer: [64]u8
	text_buffer: [256]u8
	key := binding_name(preferences.bindings[.Jump], key_buffer[:])
	text := fmt.bprintf(text_buffer[:], tr(ui, .Wing_Hint_Line), key)
	width := text_width(ui, text, 18)+48
	x, y := f32(34), ui.height-250
	rect(ui, x, y, width, 76, fade(INK, opacity*0.92))
	rect(ui, x, y, 3, 76, fade(MINT, opacity*0.7))
	label(ui, tr(ui, .Wing_Hint_Title), x+24, y+13, 12, fade(MINT, opacity), 2, 1.2)
	label(ui, text, x+24, y+37, 18, fade(PAPER, opacity))
}
