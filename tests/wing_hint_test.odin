package tests

import "core:testing"
import front "../src/front"
import game "../src/game"

@(test)
wing_hint_teaches_once_and_stops_when_the_player_already_knows :: proc(t: ^testing.T) {
	s: front.Wing_Hint
	testing.expect(t, !front.wing_hint_update(&s, false, false, false, 0.1) && !s.active)
	testing.expect(t, !front.wing_hint_update(&s, false, true, false, 0.1) && s.active)
	// Leaving the small trigger area must not snatch away a sentence mid-read.
	for _ in 0..<35 { testing.expect(t, !front.wing_hint_update(&s, false, false, false, 0.1)) }
	testing.expect(t, s.active && s.opacity == 1)
	testing.expect(t, front.wing_hint_update(&s, false, false, true, 0.1) && !s.active)
	for _ in 0..<20 { testing.expect(t, !front.wing_hint_update(&s, true, true, false, 0.1)) }
	testing.expect(t, s.opacity == 0 && !s.active, "A checkpoint revisit cannot bring the hint back")
	s = {}
	testing.expect(t, front.wing_hint_update(&s, false, false, true, 0.1) && s.opacity == 0, "Using wings before the gap suppresses the hint")
	s = {}
	completed := 0
	for _ in 0..<110 {
		if front.wing_hint_update(&s, completed > 0, true, false, 0.1) { completed += 1 }
	}
	testing.expect(t, completed == 1 && !s.active && s.opacity == 0, "No key press is required to dismiss the hint")
}

@(test)
wing_hint_anchor_is_on_the_safe_approach_and_not_the_recovery_floor :: proc(t: ^testing.T) {
	w: game.World
	w.sector = game.ram_cold_boot()
	anchor, ok := game.resolve_location(&w.sector, w.sector.wing_hint)
	testing.expect(t, ok && front.wing_hint_near(&w, anchor+game.Vec3{0, 2, 0}))
	testing.expect(t, !front.wing_hint_near(&w, anchor-game.Vec3{0, 10, 0}))
	testing.expect(t, !front.wing_hint_near(&w, anchor+game.Vec3{12, 0, 0}))
	testing.expect(t, !front.wing_hint_near(&w, w.sector.entry.offset))
	w.sector.wing_hint.room = 9999
	err, _ := game.validate_sector(&w.sector)
	testing.expect(t, err == .Location && !front.wing_hint_near(&w, anchor))
	w.sector.wing_hint = {}
	testing.expect(t, !front.wing_hint_near(&w, anchor), "A level without an authored hint has no trigger")
}
