package main

import "core:math"
import rl "vendor:raylib"
import game "game"
import front "front"
import settings "settings"

// A small shared stage, generated once. The cinematic reuses the game's lit,
// shadowed meshes; it needs no video, textures or separate rendering backend.
theatre_init :: proc(w: ^game.World, seed: u32) {
 w.seed = seed
 game.add_block(w, {0, -0.22, 0}, {100, 0.4, 100}, 12)
 append(&w.lamps, game.Vec3{-3, 4, -4}, game.Vec3{4, 5, -1}, game.Vec3{0, 10, -2})
 game.world_commit(w)
}

stage_ellipsoid :: proc(r: ^Renderer, p, size: game.Vec3, color: rl.Color) {
 object_instance(r, .Enemy, p, {size.x, 0, 0}, {0, size.y, 0}, {0, 0, size.z}, color)
}

stage_frog :: proc(r: ^Renderer, base: game.Vec3, time, scale: f32) {
 green := rl.Color{111, 165, 72, 255}
 belly := rl.Color{188, 194, 95, 255}
 breathe := 1+math.sin(time*1.4)*0.015
 stage_ellipsoid(r, base+game.Vec3{0, 0.40, 0}*scale, game.Vec3{0.45, 0.34*breathe, 0.32}*scale, green)
 stage_ellipsoid(r, base+game.Vec3{0, 0.35, -0.19}*scale, game.Vec3{0.32, 0.25, 0.18}*scale, belly)
 stage_ellipsoid(r, base+game.Vec3{0, 0.64, -0.08}*scale, game.Vec3{0.39, 0.23, 0.28}*scale, green)
 model_cube(r, base+game.Vec3{0, 0.575, -0.335}*scale, game.Vec3{0.48, 0.015, 0.018}*scale, {39, 56, 34, 255})
 blink := 0.13 if math.mod(time, 4.6) < 0.16 else f32(1)
 for sign in ([2]f32{-1, 1}) {
  stage_ellipsoid(r, base+game.Vec3{sign*0.25, 0.805, -0.125}*scale, game.Vec3{0.13, 0.12, 0.13}*scale, green)
  stage_ellipsoid(r, base+game.Vec3{sign*0.25, 0.82, -0.216}*scale, game.Vec3{0.088, 0.082*blink, 0.061}*scale, {236, 207, 99, 255})
  model_cube(r, base+game.Vec3{sign*0.25, 0.82, -0.275}*scale, game.Vec3{0.10, 0.025*blink, 0.01}*scale, INK)
  stage_ellipsoid(r, base+game.Vec3{sign*0.4, 0.18, 0.12}*scale, game.Vec3{0.26, 0.17, 0.28}*scale, green)
  line3(r, base+game.Vec3{sign*0.28, 0.40, -0.05}*scale, base+game.Vec3{sign*0.28, 0.065, -0.36}*scale, 0.048*scale, green)
  for i in 0..<3 {
   a := base+game.Vec3{sign*0.30, 0.045, -0.35}*scale
   b := base+game.Vec3{sign*0.30+f32(i-1)*0.09, 0.026, -0.54}*scale
   line3(r, a, b, 0.022*scale, green)
  }
 }
 // A tiny travelling case. The victim appears to have packed for the occasion.
 model_cube(r, base+game.Vec3{0.62, 0.13, -0.16}*scale, game.Vec3{0.18, 0.25, 0.22}*scale, {112, 66, 37, 255})
}

stage_cage :: proc(r: ^Renderer, base: game.Vec3, width, height, depth: f32) {
 color := rl.Color{106, 109, 99, 255}
 model_cube(r, base+game.Vec3{0, 0.03, 0}, {width, 0.06, depth}, color)
 model_cube(r, base+game.Vec3{0, height, 0}, {width, 0.07, depth}, color)
 for side in ([2]f32{-1, 1}) {
  for i in 0..<6 {
   x := (f32(i)/5-0.5)*width
   z := side*depth*0.5
   line3(r, base+game.Vec3{x, 0, z}, base+game.Vec3{x, height, z}, 0.016, color)
  }
 }
}

stage_princess :: proc(r: ^Renderer, base: game.Vec3, time: f32) {
 purple := rl.Color{111, 52, 129, 255}
 skin := rl.Color{212, 167, 127, 255}
 // An angular bell skirt, an enormous collar, and a crown worn at a bad angle.
 for i in 0..<8 {
  a, b := f32(i)*math.PI/4, f32(i+1)*math.PI/4
  p := base+game.Vec3{math.cos(a)*0.46, 0.025, math.sin(a)*0.36}
  q := base+game.Vec3{math.cos(b)*0.46, 0.025, math.sin(b)*0.36}
  tip := base+game.Vec3{0, 0.93, 0}
  lit_triangle(r, p, tip, q, purple)
 }
 stage_ellipsoid(r, base+game.Vec3{0, 1.02, 0}, {0.25, 0.32, 0.15}, purple)
 stage_ellipsoid(r, base+game.Vec3{0, 1.20, 0.04}, {0.41, 0.12, 0.22}, PAPER)
 stage_ellipsoid(r, base+game.Vec3{0, 1.45, 0}, {0.20, 0.25, 0.18}, skin)
 stage_ellipsoid(r, base+game.Vec3{0, 1.59, 0.06}, {0.22, 0.18, 0.18}, {172, 112, 45, 255})
 for sign in ([2]f32{-1, 1}) {
  stage_ellipsoid(r, base+game.Vec3{sign*0.078, 1.49, -0.157}, {0.059, 0.041, 0.032}, PAPER)
  model_cube(r, base+game.Vec3{sign*0.060, 1.482, -0.190}, {0.022, 0.046, 0.014}, INK)
  // Low inner brows and a lopsided grin read even in the short close shot.
  line3(r, base+game.Vec3{sign*0.027, 1.518, -0.195}, base+game.Vec3{sign*0.134, 1.565, -0.157}, 0.018, {63, 39, 35, 255})
  line3(r, base+game.Vec3{sign*0.23, 1.16, 0}, base+game.Vec3{sign*0.38, 0.86, -0.06}, 0.068, purple)
 }
 stage_ellipsoid(r, base+game.Vec3{0, 1.436, -0.182}, {0.030, 0.042, 0.054}, skin)
 line3(r, base+game.Vec3{-0.080, 1.380, -0.154}, base+game.Vec3{0.024, 1.355, -0.171}, 0.014, {103, 40, 43, 255})
 line3(r, base+game.Vec3{0.024, 1.355, -0.171}, base+game.Vec3{0.098, 1.400, -0.140}, 0.014, {103, 40, 43, 255})
 hand := base+game.Vec3{0.51, 1.10+0.08*math.sin(time*1.3), -0.3}
 line3(r, base+game.Vec3{0.38, 0.86, -0.06}, hand, 0.05, skin)
 // The royal sceptre is a spoon.
 line3(r, hand, hand+game.Vec3{0.08, 0.48, 0}, 0.022, PAPER)
 stage_ellipsoid(r, hand+game.Vec3{0.09, 0.50, 0}, {0.064, 0.10, 0.018}, PAPER)
 crown := rl.Color{225, 170, 49, 255}
 for i in 0..<7 {
  a, b := f32(i)*2*math.PI/7, f32(i+1)*2*math.PI/7
  mid := (a+b)*0.5
  p := base+game.Vec3{math.cos(a)*0.22, 1.71, math.sin(a)*0.22}
  q := base+game.Vec3{math.cos(b)*0.22, 1.71, math.sin(b)*0.22}
  tip := base+game.Vec3{math.cos(mid)*0.25, 1.97, math.sin(mid)*0.25}
  lit_triangle(r, p, tip, q, crown); lit_triangle(r, q, tip, p, crown)
 }
}

stage_tower :: proc(r: ^Renderer, time: f32) {
 plastic := rl.Color{184, 174, 144, 255}
 front_color := rl.Color{204, 195, 163, 255}
 dark := rl.Color{47, 49, 48, 255}
 model_cube(r, {0, 3.12, 0}, {4.4, 6.2, 3.5}, plastic)
 model_cube(r, {0, 3.12, -1.80}, {4.12, 6.04, 0.16}, front_color)
 model_cube(r, {0, 6.34, 0}, {4.55, 0.20, 3.70}, front_color)
 model_cube(r, {0, 8.67, 0}, {4.55, 0.28, 3.70}, front_color)
 model_cube(r, {0, 7.4, 1.64}, {4.4, 2.6, 0.22}, plastic)
 for sign in ([2]f32{-1, 1}) {
  model_cube(r, {sign*2.06, 7.4, 0}, {0.26, 2.45, 3.5}, plastic)
  model_cube(r, {sign*1.75, 0.04, -0.6}, {0.5, 0.12, 3}, dark)
 }
 for i in 0..<3 {
  y := 5.5-f32(i)*0.63
  model_cube(r, {-0.14, y, -1.91}, {3.43, 0.53, 0.10}, {157, 151, 128, 255})
  model_cube(r, {-0.31, y+0.025, -2.06}, {2.8, 0.063, 0.08}, dark)
  model_cube(r, {1.35, y-0.145, -1.985}, {0.22, 0.07, 0.028}, front_color)
 }
 for i in 0..<10 { model_cube(r, {0, 0.63+f32(i)*0.16, -2.03}, {3.0, 0.052, 0.10}, dark) }
 model_cube(r, {-1.15, 3.10, -1.91}, {0.54, 0.28, 0.06}, dark)
 // Two seven-segment digits make the overclocked front display readable.
 for digit in 0..<2 {
  x := -1.28+f32(digit)*0.26
  for y in ([3]f32{2.99, 3.10, 3.21}) { model_cube(r, {x, y, -1.947}, {0.15, 0.017, 0.012}, MINT) }
  for sign in ([2]f32{-1, 1}) { for y in ([2]f32{3.045, 3.155}) { model_cube(r, {x+sign*0.082, y, -1.947}, {0.015, 0.088, 0.012}, MINT) } }
 }
 model_cube(r, {0.80, 3.1, -1.93}, {0.22, 0.22, 0.10}, {196, 180, 147, 255})
 model_cube(r, {1.33, 3.1, -1.94}, {0.06, 0.06, 0.03}, ORANGE if int(time*4)%3 == 0 else MINT)
 stage_princess(r, {-0.92, 6.45, 0}, time)
 stage_frog(r, {0.85, 6.45, -0.17}, time, 0.85)
 stage_cage(r, {0.85, 6.44, -0.13}, 1.45, 1.28, 1.23)
 // A trailing power cable and an absurdly small door at ground level.
 line3(r, {2.2, 0.2, 1}, {3.5, 0.06, 1.6}, 0.075, dark)
 line3(r, {3.5, 0.06, 1.6}, {6.0, 0.06, -0.4}, 0.075, dark)
 model_cube(r, {0, 0.44, -1.94}, {0.50, 0.85, 0.08}, INK)
}

frontend_camera :: proc(s: ^front.State) -> game.Camera {
 p, target, fov := game.Vec3{}, game.Vec3{}, f32(45)
 if s.phase == .Fighter {
  p, target, fov = {1.7, 1.05, -3.4}, {0.88, 0.86, 0.30}, 39
 } else if s.scene == 0 {
  p, target, fov = {0.65, 0.94, -3.4}, {0.06, 0.62, -0.05}, 31
 } else {
  // The second caption and the reveal share one set. Even an early manual
  // advance starts at precisely the close shot, without a fade or camera cut.
  p, target, fov = {0.15, 7.70, -4.8}, {0, 7.22, -0.1}, 41
  if s.scene == 2 {
   t := clamp((s.elapsed-0.12)/2.5, 0, 1)
   ease := t*t*(3-2*t)
   p += (game.Vec3{7, 1.2, -19}-p)*ease
   target += (game.Vec3{0, 3.65, -0.1}-target)*ease
   fov += 2*ease
  }
 }
 return {position = p, target = target, forward = game.normalized(target-p), fov = fov}
}

render_frontend :: proc(r: ^Renderer, s: ^front.State) {
 camera := frontend_camera(s)
 time := s.animation
 v := game.Render_Snapshot{world = &r.theatre, hero = s.hero}
 v.player = {position = {0, 0.02, 0}, grounded = true, yaw = -0.15+math.sin(time*0.28)*0.28, pitch = -0.10, idle_time = 5+time}
 sync_world_mesh(r, &r.theatre)
 resize_render_target(r)
 order_chunks(r, camera.position)
 r.shadow_center, r.shadow_extent = {0, 4, 0}, 24
 r.objects.count, r.objects.ranges, r.objects.passes = 0, {}, WORLD_PASS|SHADOW_PASS
 r.hero.active = false
 if s.phase == .Fighter {
  object_instance(r, .Vent, {0, -0.02, 0}, {1.15, 0, 0}, {0, 0.045, 0}, {0, 0, 1.15}, {56, 63, 64, 255})
  ring3(r, {0, 0.03, 0}, 1.11, MINT if s.hero == .Lora else ORANGE)
  prepare_hero(r, &v, time, camera)
 } else if s.scene == 0 { stage_frog(r, {}, 1.2, 1.3) }
 else { stage_tower(r, time) }
 upload_instances(r)
 render_shadow(r, &v, camera, time)
 update_lighting(r, &v, camera)
 render_world_pass(r, &v, camera, time)
 if s.phase == .Intro && s.scene == 0 { draw_missing_poster(r, s.elapsed) }
 else { render_post_pass(r) }
}

fighter_row :: proc(ui: UI, index: int) -> rl.Rectangle { return {64*ui.scale, f32(342+index*62)*ui.scale, 464*ui.scale, 49*ui.scale} }

frontend_input :: proc(s: ^front.State, r: ^Renderer) -> front.Input {
 input := front.Input{focused = rl.IsWindowFocused()}
 if !input.focused { return input }
 ui := ui_context(r)
 if s.phase == .Intro {
  input.next = key_pressed(.ENTER) || key_pressed(.SPACE) || (rl.IsMouseButtonPressed(.LEFT) && rl.GetMousePosition().y > 97*ui.scale)
  input.skip = key_pressed(.ESCAPE)
 } else {
  input.choose = int(key_pressed(.RIGHT) || key_pressed(.DOWN))-int(key_pressed(.LEFT) || key_pressed(.UP))
  input.confirm, input.back = key_pressed(.ENTER) || key_pressed(.SPACE), key_pressed(.ESCAPE)
  if rl.IsMouseButtonPressed(.LEFT) {
   for i in 0..<2 { if rl.CheckCollisionPointRec(rl.GetMousePosition(), fighter_row(ui, i)) { input.choose = i-int(s.hero) } }
   input.confirm = rl.CheckCollisionPointRec(rl.GetMousePosition(), {64*ui.scale, 626*ui.scale, 464*ui.scale, 50*ui.scale})
  }
 }
 return input
}

language_toggle :: proc(r: ^Renderer, prefs: ^settings.Store) {
 ui := ui_context(r)
 area := rl.Rectangle{(ui.width-203)*ui.scale, 30*ui.scale, 145*ui.scale, 35*ui.scale}
 if key_pressed(.TAB) || (rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(rl.GetMousePosition(), area)) {
  prefs.data.language = .Russian if prefs.data.language == .English else .English
  prefs.dirty = true
 }
 r.language = prefs.data.language
}

draw_language :: proc(ui: UI) {
 label(ui, "RU / EN  [TAB]", ui.width-202, 41, 13, MINT, 2)
}

draw_frontend_text :: proc(r: ^Renderer, s: ^front.State) {
 ui := ui_context(r)
 if s.phase == .Fighter {
  rl.DrawRectangleGradientH(0, 0, r.width, r.height, {6, 18, 24, 245}, {6, 18, 24, 0})
  label(ui, "THE PRINCESS HAS MY TOAD", 64, 41, 15, PAPER, 2, 1.2)
  label(ui, tr(ui, .Choose), 60, 146, 39, PAPER, 1, -1)
  label(ui, tr(ui, .Select_Hint), 64, 217, 12, MUTED, 2)
  for hero in game.Character {
   bounds := fighter_row(ui, int(hero))
   chosen := hero == s.hero
   if chosen { rl.DrawRectangleRec(bounds, ORANGE if hero == .Duke else MINT) }
   label(ui, tr(ui, .Duke if hero == .Duke else .Lora), 80, bounds.y/ui.scale+14, 20, INK if chosen else PAPER, 1)
  }
  label(ui, tr(ui, .Duke_Line if s.hero == .Duke else .Lora_Line), 65, 512, 19, PAPER)
  rect(ui, 64, 626, 464, 50, fade(PAPER, 0.12))
  label(ui, tr(ui, .Play), 81, 643, 17, PAPER, 2)
  label(ui, "ENTER", 442, 644, 13, MUTED, 2)
  label(ui, tr(ui, .Select_Back), 64, ui.height-43, 12, MUTED, 2)
 } else {
  rect(ui, 0, 0, ui.width, 97, {5, 12, 20, 255})
  rect(ui, 0, ui.height-206, ui.width, 206, {5, 12, 20, 255})
  label(ui, "THE PRINCESS HAS MY TOAD", 64, 42, 13, MUTED, 2, 1.1)
  lines := [3]string{tr(ui, .Scene_0), tr(ui, .Scene_1), tr(ui, .Scene_2)}
  center_label(ui, lines[min(s.scene, len(lines)-1)], ui.width*0.5, ui.height-145, 30, PAPER)
  label(ui, tr(ui, .Next), 64, ui.height-40, 11, MUTED, 2)
  label(ui, tr(ui, .Skip), ui.width-206, ui.height-40, 11, MUTED, 2)
  for i in 0..<len(front.DURATION) { rect(ui, ui.width*0.5-23+f32(i)*18, ui.height-32, 10, 2, ORANGE if i == s.scene else MUTED) }
  if s.scene < 2 && s.elapsed < 0.10 { rect(ui, 0, 97, ui.width, ui.height-303, fade(INK, 1-s.elapsed*10)) }
 }
 draw_language(ui)
}
