package main

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import game "game"
import settings "settings"
import storage "storage"
import loc "locale"

Menu_Page :: enum { Root, New_Game, Settings, Controls }
Menu_Command :: enum { None, Resume, Continue, New_Game, Save, Load, Intro, Quit }
Menu_State :: struct {
	page: Menu_Page,
	selected: int,
	binding: int,
	notice: [160]u8,
	notice_length: int,
	notice_time: f32,
	notice_error: bool,
}
Menu_Item :: struct { title: loc.Key, command: Menu_Command, enabled: bool }
CONTROL_COUNT :: len([settings.Action]int{})
CONTROL_ROWS :: (CONTROL_COUNT+1)/2
@(rodata) CONTROL_ACTIONS := [CONTROL_COUNT]settings.Action{.Forward, .Backward, .Left, .Right, .Jump, .Dash, .Fire, .Scope, .Use, .Kick, .Repeater, .Shotgun, .Fragmentator, .Quick_Save, .Quick_Load}

menu_notice :: proc(m: ^Menu_State, text: string, bad: bool = false) {
	m.notice_length = min(len(text), len(m.notice))
	copy(m.notice[:m.notice_length], transmute([]u8)text[:m.notice_length])
	m.notice_time, m.notice_error = 6, bad
}

menu_items :: proc(paused: bool, saves: ^storage.Store) -> ([6]Menu_Item, int) {
	_, available := storage.latest(saves)
	if paused {
		return {{.Resume, .Resume, true}, {.Quick_Save, .Save, saves.enabled}, {.Quick_Load, .Load, saves.slots[.Quick].valid}, {.New_Game, .New_Game, true}, {.Settings, .None, true}, {.Quit, .Quit, true}}, 6
	}
	return {{.Continue, .Continue, available}, {.New_Game, .New_Game, true}, {.Settings, .None, true}, {.Intro, .Intro, true}, {.Quit, .Quit, true}, {}}, 5
}

menu_row :: proc(ui: UI, page: Menu_Page, index: int) -> rl.Rectangle {
	x, y, width := ui.width*0.5-200, f32(466+index*42), f32(400)
	if page != .Root { x, y, width = 64, f32(252+index*44), 580 }
	if page == .New_Game { x, y, width = ui.width*0.5-260, f32(370+index*52), 520 }
	if page == .Controls {
		if index < CONTROL_COUNT { x, y, width = 64+f32(index/CONTROL_ROWS)*560, 254+f32(index%CONTROL_ROWS)*43, 520
		} else { y = 616+f32(index-CONTROL_COUNT)*46 }
	}
	return {x*ui.scale, y*ui.scale, width*ui.scale, 36*ui.scale}
}

menu_select :: proc(m: ^Menu_State, ui: UI, count: int) -> bool {
	step := int(key_pressed(.DOWN))-int(key_pressed(.UP))
	if m.page == .Controls && m.selected < CONTROL_COUNT {
		if key_pressed(.LEFT) && m.selected >= CONTROL_ROWS { step = -CONTROL_ROWS }
		if key_pressed(.RIGHT) && m.selected+CONTROL_ROWS < CONTROL_COUNT { step = CONTROL_ROWS }
	}
	m.selected = (m.selected+step+count)%count
	mouse := rl.GetMouseDelta()
	clicked := rl.IsMouseButtonPressed(.LEFT)
	if mouse != (rl.Vector2{}) || clicked {
		for i in 0..<count {
			if rl.CheckCollisionPointRec(rl.GetMousePosition(), menu_row(ui, m.page, i)) {
				m.selected = i
				if clicked { return true }
			}
		}
	}
	return key_pressed(.ENTER)
}

menu_back :: proc(m: ^Menu_State) -> bool {
	if m.binding >= 0 { m.binding = -1; return true }
	if m.page == .Controls { m.page, m.selected = .Settings, 9; return true }
	if m.page != .Root { m.page, m.selected = .Root, 0; return true }
	return false
}

menu_update :: proc(m: ^Menu_State, r: ^Renderer, paused: bool, saves: ^storage.Store, prefs: ^settings.Store) -> Menu_Command {
	if m.binding >= 0 {
		key := int(native_events.keys[0]) if native_events.count > 0 else 0
		for button in 0..<7 { if rl.IsMouseButtonPressed(rl.MouseButton(button)) { key = -1-button } }
		if key != 0 && settings.bind(&prefs.data, settings.Action(m.binding), key) {
			prefs.dirty, m.binding = true, -1
		}
		return .None
	}
	ui := ui_context(r)
	switch m.page {
	case .Root:
		items, count := menu_items(paused, saves)
		if menu_select(m, ui, count) && items[m.selected].enabled {
			command := items[m.selected].command
			if command == .New_Game { m.page, m.selected = .New_Game, 1; return .None }
			if command == .None { m.page, m.selected = .Settings, 0 }
			return command
		}
	case .New_Game:
		activate := menu_select(m, ui, 3)
		change := int(key_pressed(.RIGHT))-int(key_pressed(.LEFT))
		if m.selected == 0 && (activate || change != 0) {
			prefs.data.difficulty = game.Difficulty((int(prefs.data.difficulty)+(1 if activate else change)+3)%3)
			prefs.dirty = true
		}
		if activate && m.selected == 1 { return .New_Game }
		if activate && m.selected == 2 { menu_back(m) }
	case .Settings:
		activate := menu_select(m, ui, 11)
		change := int(key_pressed(.RIGHT))-int(key_pressed(.LEFT))
		if activate { change = 1 }
		if change != 0 && m.selected < 9 && (ODIN_OS != .JS || (m.selected != 6 && m.selected != 7)) {
			d := &prefs.data
			switch m.selected {
			case 0: d.sensitivity = clamp(d.sensitivity+f32(change)*0.0002, 0.0002, 0.012)
			case 1: d.invert_y = !d.invert_y
			case 2: d.effects = clamp(d.effects+f32(change)*0.05, 0, 1)
			case 3: d.voice = clamp(d.voice+f32(change)*0.05, 0, 1)
			case 4: d.ambience = clamp(d.ambience+f32(change)*0.05, 0, 1)
			case 5: d.music = clamp(d.music+f32(change)*0.05, 0, 1)
			case 6: d.display = .Borderless if d.display == .Window else .Window
			case 7:
				sizes := [6][2]int{{960, 600}, {1280, 800}, {1600, 900}, {1920, 1080}, {2560, 1440}, {3840, 2160}}
				index := 1
				for size, i in sizes { if size[0] == d.width && size[1] == d.height { index = i; break } }
				index = (index+change+len(sizes))%len(sizes)
				d.width, d.height = sizes[index][0], sizes[index][1]
			case 8: d.render_scale = clamp(d.render_scale+f32(change)*0.25, 0.5, 1)
			}
			prefs.dirty = true
		}
		if activate && m.selected == 9 { m.page, m.selected = .Controls, 0 }
		if activate && m.selected == 10 { menu_back(m) }
	case .Controls:
		if menu_select(m, ui, CONTROL_COUNT+2) {
			if m.selected < CONTROL_COUNT { m.binding = int(CONTROL_ACTIONS[m.selected]) }
			if m.selected == CONTROL_COUNT { prefs.data.bindings, prefs.dirty = settings.defaults().bindings, true }
			if m.selected == CONTROL_COUNT+1 { menu_back(m) }
		}
	}
	return .None
}

binding_name :: proc(key: int, bytes: []u8) -> string {
	if key < 0 { return fmt.bprintf(bytes, "MOUSE %d", -key) }
	if key >= 290 && key <= 301 { return fmt.bprintf(bytes, "F%d", key-289) }
	switch key {
	case 32: return "SPACE"
	case 258: return "TAB"
	case 259: return "BACKSPACE"
	case 262: return "RIGHT"
	case 263: return "LEFT"
	case 264: return "DOWN"
	case 265: return "UP"
	case 340: return "LEFT SHIFT"
	case 341: return "LEFT CTRL"
	case 342: return "LEFT ALT"
	case 344: return "RIGHT SHIFT"
	case 345: return "RIGHT CTRL"
	case 346: return "RIGHT ALT"
	}
	if key >= 32 && key <= 126 { return fmt.bprintf(bytes, "%c", rune(key)) }
	return fmt.bprintf(bytes, "KEY %d", key)
}

menu_button :: proc(ui: UI, m: ^Menu_State, index: int, title: string, value: string = "", enabled: bool = true) {
	bounds := menu_row(ui, m.page, index)
	x, y, w := bounds.x/ui.scale, bounds.y/ui.scale, bounds.width/ui.scale
	selected := m.selected == index
	if m.page == .Root || m.page == .New_Game {
		if selected {
			rl.DrawRectangleRec(bounds, fade(INK, 0.6))
			if enabled {
				rect(ui, x+15, y+17, 12, 2, ORANGE)
				rect(ui, x+w-27, y+17, 12, 2, ORANGE)
			}
		}
		buffer: [160]u8
		text := fmt.bprintf(buffer[:], "%s   < %s >", title, value) if len(value) > 0 else title
		center_label(ui, text, x+w*0.5, y+9, 16, (ORANGE if selected else PAPER) if enabled else MUTED, 2)
		return
	}
	if selected { rl.DrawRectangleRec(bounds, fade(ORANGE, 0.96) if enabled else fade(PAPER, 0.13)) }
	color := (INK if selected else PAPER) if enabled else MUTED
	label(ui, title, x+14, y+9, 16, color, 2)
	if len(value) > 0 { label(ui, value, x+w-190, y+9, 15, color, 2) }
}

render_menu_background :: proc(r: ^Renderer, time: f32) {
	// The opening owns the tower reveal. The title needs only the existing sky,
	// without building a stage, uploading meshes or rendering a shadow pass.
	resize_render_target(r)
	camera := game.Camera{forward = game.normalized({math.sin(time*0.006), 0.2, -math.cos(time*0.006)}), fov = 58}
	r.damage_flash = 0
	rl.BeginTextureMode(r.target)
	draw_sky(r, camera)
	rl.EndTextureMode()
	render_post_pass(r)
}

draw_menu_panel :: proc(r: ^Renderer, g: ^game.State, paused: bool, m: ^Menu_State, saves: ^storage.Store, prefs: ^settings.Store) {
	ui := ui_context(r)
	if m.page == .Root || m.page == .New_Game {
		rl.DrawRectangleGradientV(0, 0, r.width, r.height, {6, 12, 16, 165}, {6, 12, 16, 230})
	} else {
		rl.DrawRectangleGradientH(0, 0, r.width, r.height, {6, 18, 24, 245}, {6, 18, 24, 80})
		rect(ui, 64, 47, 28, 3, ORANGE)
		label(ui, "THE PRINCESS HAS MY TOAD", 107, 38, 15, PAPER, 2, 1.2)
		rule(ui, 64, 87, ui.width-128, fade(PAPER, 0.16))
	}
	draw_language(ui)
	buf: [128]u8
	switch m.page {
	case .Root:
		if paused {
			center_label(ui, tr(ui, .Paused), ui.width*0.5, 270, 72, PAPER, 1)
		} else {
			width := f32(700)
			height := width*f32(r.logo.height)/f32(r.logo.width)
			rl.DrawTexturePro(r.logo, {0, 0, f32(r.logo.width), f32(r.logo.height)}, {(ui.width-width)*0.5*ui.scale, (252-height*0.5)*ui.scale, width*ui.scale, height*ui.scale}, {}, 0, rl.WHITE)
		}
		if game.sector_definition(g.world.sector.key).preview {
			center_label(ui, "Development fixture / unfinished sector", ui.width*0.5, 401, 13, MUTED)
		}
		items, count := menu_items(paused, saves)
		for item, i in items[:count] { menu_button(ui, m, i, tr(ui, item.title), enabled = item.enabled) }
	case .New_Game:
		center_label(ui, tr(ui, .New_Game), ui.width*0.5, 238, 52, PAPER, 1)
		if saves.slots[.Checkpoint].valid { center_label(ui, tr(ui, .New_Note), ui.width*0.5, 559, 14, MUTED) }
		menu_button(ui, m, 0, tr(ui, .Difficulty), game.difficulty_name(prefs.data.difficulty))
		menu_button(ui, m, 1, tr(ui, .Begin))
		menu_button(ui, m, 2, tr(ui, .Back))
	case .Settings:
		label(ui, tr(ui, .Settings), 60, 145, 54, PAPER, 1)
		label(ui, tr(ui, .Settings_Hint), 65, 216, 14, MUTED)
		menu_button(ui, m, 0, tr(ui, .Mouse), fmt.bprintf(buf[:], "%.1f", prefs.data.sensitivity*1000))
		menu_button(ui, m, 1, tr(ui, .Invert), tr(ui, .On) if prefs.data.invert_y else tr(ui, .Off))
		menu_button(ui, m, 2, tr(ui, .Effects), fmt.bprintf(buf[:], "%.0f %%", prefs.data.effects*100))
		menu_button(ui, m, 3, tr(ui, .Voice), fmt.bprintf(buf[:], "%.0f %%", prefs.data.voice*100))
		menu_button(ui, m, 4, tr(ui, .Ambience), fmt.bprintf(buf[:], "%.0f %%", prefs.data.ambience*100))
		menu_button(ui, m, 5, tr(ui, .Music), fmt.bprintf(buf[:], "%.0f %%", prefs.data.music*100))
		menu_button(ui, m, 6, tr(ui, .Display), tr(ui, .Browser) when ODIN_OS == .JS else (tr(ui, .Borderless) if prefs.data.display == .Borderless else tr(ui, .Window)), enabled = ODIN_OS != .JS)
		menu_button(ui, m, 7, tr(ui, .Window_Size), fmt.bprintf(buf[:], "%d x %d", prefs.data.width, prefs.data.height), enabled = ODIN_OS != .JS)
		menu_button(ui, m, 8, tr(ui, .Resolution), fmt.bprintf(buf[:], "%.0f %%", prefs.data.render_scale*100))
		menu_button(ui, m, 9, tr(ui, .Controls))
		menu_button(ui, m, 10, tr(ui, .Back))
	case .Controls:
		label(ui, tr(ui, .Controls), 60, 145, 54, PAPER, 1)
		label(ui, tr(ui, .Controls_Hint), 65, 216, 14, MUTED)
		for action, index in CONTROL_ACTIONS {
			value := tr(ui, .Press_Key) if m.binding == int(action) else binding_name(prefs.data.bindings[action], buf[:])
			menu_button(ui, m, index, tr(ui, action_text(action)), value)
		}
		menu_button(ui, m, CONTROL_COUNT, tr(ui, .Reset_Controls))
		menu_button(ui, m, CONTROL_COUNT+1, tr(ui, .Back))
	}
	label(ui, tr(ui, .Navigation), 64, ui.height-43, 11, MUTED, 2)
	label(ui, tr(ui, .Escape_Back), 400, ui.height-43, 11, MUTED, 2)
	label(ui, game.BUILD_VERSION, ui.width-234, ui.height-43, 11, MUTED, 2, 1)
}

draw_notice :: proc(r: ^Renderer, m: ^Menu_State, in_game: bool = false) {
	if m.notice_time <= 0 { return }
	ui := ui_context(r)
	width := max(160, min(ui.width-128, f32(m.notice_length)*8+24))
	x, y := f32(36) if in_game else f32(64), ui.height-(170 if in_game else f32(90))
	rect(ui, x, y, width, 31, fade(INK, 0.94))
	label(ui, string(m.notice[:m.notice_length]), x+12, y+8, 14, ORANGE if m.notice_error else MINT, 2)
}

// Keep binding IDs separate from translation IDs; neither relies on enum order.
action_text :: proc(action: settings.Action) -> loc.Key {
 switch action {
 case .Forward: return .Forward
 case .Backward: return .Backward
 case .Left: return .Left
 case .Right: return .Right
 case .Jump: return .Jump
 case .Dash: return .Dash
 case .Fire: return .Fire
 case .Scope: return .Scope
 case .Use: return .Use
 case .Kick: return .Kick
 case .Repeater: return .Repeater
 case .Fragmentator: return .Fragmentator
 case .Shotgun: return .Shotgun
 case .Quick_Save: return .Quick_Save
 case .Quick_Load: return .Quick_Load
 }
 unreachable()
}
