package tests

import "core:testing"
import game "../src/game"
import front "../src/front"
import loc "../src/locale"

@(test)
death_screen_requires_a_fresh_press_and_pauses_without_focus :: proc(t: ^testing.T) {
 s: front.Death_Screen
 front.death_begin(&s, .Fairy)
 for _ in 0..<20 { testing.expect(t, !front.death_update(&s, 0.1, true, true, true)) }
 testing.expect(t, s.active && !s.armed && s.cause == .Fairy, "Held fire and key repeats cannot dismiss death")
 front.death_update(&s, 0.1, true, false, false)
 age := s.age
 testing.expect(t, !front.death_update(&s, 0.1, false, false, true) && s.age == age && !s.armed)
 testing.expect(t, !front.death_update(&s, 0.1, true, true, true), "Focus regain with a held key is not confirmation")
 front.death_update(&s, 0.1, true, false, false)
 testing.expect(t, front.death_update(&s, 0.1, true, true, true) && !s.active)
 front.death_begin(&s, .Void)
 testing.expect(t, !front.death_update(&s, 0.1, true, false, true), "A newly opened screen has a short minimum display time")
 testing.expect(t, s.active && s.cause == .Void)
}

@(test)
intro_skip_cancel_and_replay_are_separate_from_character_confirmation :: proc(t: ^testing.T) {
 s: front.State
 front.start(&s, .Duke)
 // The click that opened the intro cannot consume its first shot.
 front.update(&s, {focused = true, next = true}, 0)
 testing.expect(t, s.scene == 0 && s.phase == .Intro)
 for _ in 0..<20 { front.update(&s, {}, 0.1) }
 testing.expect(t, s.elapsed == 0, "Focus loss pauses the story")
 front.update(&s, {focused = true, skip = true}, 0.1)
 testing.expect(t, s.phase == .Fighter)
 for _ in 0..<3 { front.update(&s, {focused = true}, 0.1) }
 front.update(&s, {focused = true, choose = 1}, 0)
 testing.expect(t, s.hero == .Lora)
 testing.expect_value(t, front.update(&s, {focused = true, confirm = true}, 0), front.Result.Begin)
 testing.expect(t, s.phase == .None && s.hero == .Lora)
 front.start(&s, .Lora)
 front.update(&s, {focused = true, skip = true}, 0)
 testing.expect_value(t, front.update(&s, {focused = true, back = true}, 0), front.Result.Back)
 front.start(&s, .Lora, replay_only = true)
 testing.expect_value(t, front.update(&s, {focused = true, skip = true}, 0), front.Result.Watched)
 front.start(&s, .Duke)
 testing.expect_value(t, len(front.DURATION), 3)
 for scene in 0..<3 {
  testing.expect(t, s.scene == scene && s.phase == .Intro)
  // A manual cut also keeps the actors' animation clock continuous.
  front.update(&s, {focused = true}, 0.1)
  front.update(&s, {focused = true}, 0.1)
  before := s.animation
  front.update(&s, {focused = true, next = true}, 0.1)
  if scene < 2 { testing.expect(t, s.elapsed == 0 && s.animation >= before) }
 }
 testing.expect(t, s.phase == .Fighter && s.hero == .Duke)
 front.start(&s, .Duke)
 for _ in 0..<109 { front.update(&s, {focused = true}, 0.1) }
 testing.expect(t, s.phase == .Fighter, "All three timed shots finish in under eleven seconds")
 for language in loc.Language { for key in loc.Key { testing.expect(t, len(loc.text(language, key)) > 0, "Every UI string has both translations") } }
}

@(test)
hero_persists_through_disk_checkpoint_and_campaign :: proc(t: ^testing.T) {
 w: game.World
 game.world_init_ram(&w)
 defer game.world_destroy(&w)
 for hero in game.Character {
  g := game.State{world = &w, hero = hero}
  game.init(&g)
  game.update(&g, {move = {0, 1}, jump_pressed = true}, game.STEP)
  saved, restored: game.Save_Data
  testing.expect_value(t, game.save_capture(&saved, &g, .Quick, 1), game.Save_Error.None)
  buffer: [game.SAVE_LIMIT]u8
  count, err := game.save_encode(&saved, buffer[:])
  testing.expect_value(t, err, game.Save_Error.None)
  testing.expect_value(t, game.save_decode(buffer[:count], &restored), game.Save_Error.None)
  g.hero = .Duke if hero == .Lora else .Lora
  testing.expect_value(t, game.save_restore(&g, &restored), game.Save_Error.None)
  testing.expect(t, g.hero == hero && g.restart.run.hero == hero)
  game.respawn(&g)
  testing.expect(t, g.hero == hero)
  // A mismatched restart must not silently switch protagonist after dying.
  restored.restart.state.hero = .Duke if hero == .Lora else .Lora
  testing.expect_value(t, game.save_restore(&g, &restored), game.Save_Error.Content)
  testing.expect(t, g.hero == hero)
  g.won = true
  testing.expect(t, game.advance_campaign(&g))
  testing.expect(t, g.hero == hero && g.restart.run.hero == hero)
  game.world_init_ram(&w)
 }
}
