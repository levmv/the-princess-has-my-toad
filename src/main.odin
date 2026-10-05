#+build !js
package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:strconv"
import game "game"

main :: proc() {
 app := application_create()
 defer free(app)
	for arg in os.args[1:] {
		switch {
		case arg == "--version": fmt.printf("THE PRINCESS HAS MY TOAD %s / %s\n", game.BUILD_VERSION, game.BUILD_ID); return
		case arg == "--help" || arg == "-h":
			fmt.println("THE PRINCESS HAS MY TOAD / Cold Boot\n\nWASD: move | Mouse: look | LMB: fire | RMB: scope\nSpace: jump; release and press again in air for wing | Shift: dash\nE: use | F: kick | 1/2/3 or wheel: weapon\nF5/F9: quick save/load | Esc: pause | M: mute | F3: timings | F11: fullscreen\nBindings, sensitivity, sound and display can be changed in Settings.\n\n--seed=N --difficulty=hard|brutal|nightmare --sector=ram/bank-01\n--sector=ram/combat-lab: combat fixture | --sector=ram/transfer: unfinished transition\n--language=ru|en --hero=duke|lora (developer/autostart)\n--arena: original flight range | --start: skip menu and intro | --continue: load latest valid slot\n--save-dir=PATH --config-dir=PATH --no-save --mute --no-audio --msaa --scale=0.5..1\n--room=ID: developer entry, disables persistence\n--debug=collision|nav|ai|all: developer overlays\n--record=FILE: input recording, up to 30 minutes; ends on loading/new game/sector change\n--replay=FILE: exact-build playback, checks final state, then exits; Esc aborts\n--smoke-test --menu-screenshot --menu-page=root|settings|controls|new\nDefault data: $XDG_DATA_HOME/the-princess-has-my-toad or ~/.local/share/the-princess-has-my-toad\nDefault settings: $XDG_CONFIG_HOME/the-princess-has-my-toad or ~/.config/the-princess-has-my-toad")
			return
		case strings.has_prefix(arg, "--seed="):
			value, ok := strconv.parse_u64(arg[7:])
			if !ok || value > 0xFFFFFFFF { fmt.eprintln("Invalid seed; expected a 32-bit unsigned integer."); os.exit(1) }
			app.seed = u32(value)
		case strings.has_prefix(arg, "--sector="):
			app.sector = game.sector_by_path(arg[9:])
			if app.sector == .None { fmt.eprintln("Unknown sector. Available: ram/bank-01, ram/combat-lab, ram/transfer."); os.exit(1) }
		case strings.has_prefix(arg, "--difficulty="):
			value, ok := game.difficulty_by_name(arg[13:])
			if !ok { fmt.eprintln("Unknown difficulty. Available: hard, brutal, nightmare."); os.exit(1) }
			app.difficulty, app.difficulty_explicit = value, true
		case strings.has_prefix(arg, "--language="):
   switch arg[11:] {
   case "ru": app.language = .Russian
   case "en": app.language = .English
   case: fmt.eprintln("Language must be ru or en."); os.exit(1)
   }
   app.language_explicit = true
  case strings.has_prefix(arg, "--hero="):
   switch arg[7:] {
   case "duke": app.hero = .Duke
   case "lora": app.hero = .Lora
   case: fmt.eprintln("Hero must be duke or lora."); os.exit(1)
   }
   app.hero_explicit = true
  case strings.has_prefix(arg, "--save-dir="): app.save_dir = arg[11:]
		case strings.has_prefix(arg, "--record="): app.record_path = arg[9:]
		case strings.has_prefix(arg, "--replay="): app.replay_path = arg[9:]
		case strings.has_prefix(arg, "--room="):
			value, ok := strconv.parse_int(arg[7:])
			if !ok || value <= 0 || value > 65535 { fmt.eprintln("Room must be a positive content ID."); os.exit(1) }
			app.room_id = game.Room_ID(value)
		case strings.has_prefix(arg, "--scale="):
			value, ok := strconv.parse_f32(arg[8:])
			if !ok || !(value >= 0.5 && value <= 1) { fmt.eprintln("Render scale must be between 0.5 and 1."); os.exit(1) }
			app.render_scale = value
		case strings.has_prefix(arg, "--debug="):
			switch arg[8:] {
			case "collision": app.debug_view = .Collision
			case "nav": app.debug_view = .Navigation
			case "ai": app.debug_view = .Perception
			case "all": app.debug_view = .All
			case: fmt.eprintln("Debug views: collision, nav, ai, all."); os.exit(1)
			}
		case strings.has_prefix(arg, "--config-dir="): app.config_dir = arg[13:]
		case strings.has_prefix(arg, "--menu-page="):
			switch arg[12:] {
			case "root": app.capture_page = .Root
			case "settings": app.capture_page = .Settings
			case "controls": app.capture_page = .Controls
			case "new": app.capture_page = .New_Game
			case: fmt.eprintln("Unknown menu page."); os.exit(1)
			}
		case arg == "--smoke-test": app.smoke, app.muted = true, true
		case arg == "--menu-screenshot": app.capture_menu, app.muted = true, true
		case arg == "--mute": app.muted = true
		case arg == "--no-audio": app.no_audio = true
		case arg == "--msaa": app.window_msaa = true
		case arg == "--arena": app.arena = true
		case arg == "--no-save": app.no_save = true
		case arg == "--start": app.autostart = true
		case arg == "--continue": app.continue_game = true
		case: fmt.eprintf("Unknown option: %s\n", arg); os.exit(1)
		}
	}
	if (app.record_path != "" && app.replay_path != "") || ((app.record_path != "" || app.replay_path != "") && (app.smoke || app.capture_menu)) { fmt.eprintln("Record and replay are separate modes and cannot be combined with smoke/menu capture."); os.exit(1) }
	if app.record_path != "" || app.replay_path != "" { app.autostart = true }
	if app.replay_path != "" { app.no_save, app.continue_game = true, false }
	if app.room_id != 0 {
		if app.replay_path != "" || app.continue_game || app.smoke || app.capture_menu || app.arena { fmt.eprintln("A room launch cannot be combined with loading, replay or the old arena."); os.exit(1) }
		app.no_save, app.autostart = true, true
	}
 if !application_init(app) { os.exit(1) }
 for application_frame(app) {}
 application_destroy(app)
 if app.exit_code != 0 { os.exit(app.exit_code) }
}
