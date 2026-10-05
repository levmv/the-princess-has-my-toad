package front

import game "../game"

// Cinematic state is independent of the run. Starting or cancelling the intro
// cannot mutate a checkpoint; only the final character confirmation starts play.
Phase :: enum { None, Intro, Fighter }
Result :: enum { None, Begin, Back, Watched }
State :: struct {
 phase: Phase,
 scene: int,
 elapsed, animation: f32,
 hero: game.Character,
 replay_only: bool,
}
Input :: struct { next, skip, back, confirm: bool, choose: int, focused: bool }
@(rodata) DURATION := [3]f32{3.6, 3, 4}

start :: proc(s: ^State, hero: game.Character, replay_only: bool = false) {
 s^ = {phase = .Intro, hero = hero, replay_only = replay_only}
}

update :: proc(s: ^State, input: Input, dt: f32) -> Result {
 if s.phase == .None || !input.focused { return .None }
 step := clamp(dt, 0, 0.1)
 s.elapsed += step
 s.animation += step
 switch s.phase {
 case .None:
 case .Intro:
  // A short input guard keeps the menu's confirming click out of the first shot.
  if s.elapsed >= 0.25 && (input.next || s.elapsed >= DURATION[s.scene]) { s.scene += 1; s.elapsed = 0 }
  if input.skip || s.scene >= len(DURATION) {
   if s.replay_only { s.phase = .None; return .Watched }
   s.phase, s.elapsed, s.animation = .Fighter, 0, 0
  }
 case .Fighter:
  if input.back { s.phase = .None; return .Back }
  if input.choose != 0 { s.hero = game.Character((int(s.hero)+input.choose%2+2)%2); s.animation = 0 }
  if input.confirm && s.elapsed >= 0.25 { s.phase = .None; return .Begin }
 }
 return .None
}
