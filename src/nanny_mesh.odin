package main

import "core:math"
import rl "vendor:raylib"
import game "game"

nanny_body :: proc(m: ^Mesh_Builder) {
	enemy_box(m, {0, -0.32, 0}, {1.14, 0.68, 1.43}, {84, 64, 71, 255}, 0.12)
	enemy_box(m, {0, 0.02, 0}, {1.25, 0.12, 1.54}, {142, 129, 107, 255}, 0.05)
	for side in 0..<2 {
		sign := f32(side*2-1)
		for rib in 0..<7 {
			mesh_beam(m, {sign*0.58, -0.53, f32(rib-3)*0.18}, {sign*0.59, -0.04, f32(rib-3)*0.18}, 0.025, 0.025, {127, 107, 91, 255}, 0, 4)
		}
		mesh_beam(m, {sign*0.40, -0.23, 0.48}, {sign*0.40, 0.39, 0.98}, 0.045, 0.045, {109, 136, 128, 255}, 0, 6)
	}
	mesh_beam(m, {-0.4, 0.39, 0.98}, {0.4, 0.39, 0.98}, 0.068, 0.068, {53, 67, 65, 255}, 0, 6)
	// The passenger is a stubborn little processor in a blanket.
	enemy_box(m, {0, 0.19, -0.13}, {0.52, 0.42, 0.51}, {91, 96, 80, 255}, 0.08)
	enemy_box(m, {0, 0.10, -0.395}, {0.30, 0.13, 0.035}, {37, 18, 29, 255}, 0.015)
	for tooth in 0..<5 {
		x := f32(tooth-2)*0.052
		mesh_beam(m, {x, 0.16, -0.42}, {x+0.008, 0.045, -0.429}, 0.022, 0.003, {218, 185, 136, 255}, 0, 4)
	}
	for sign in ([2]f32{-1, 1}) { enemy_box(m, {sign*0.12, 0.28, -0.393}, {0.065, 0.065, 0.02}, {173, 89, 47, 255}, 0, SURFACE_LIGHT) }
	mesh_beam(m, {0, 0.02, 0.38}, {0, 0.92, 0.38}, 0.028, 0.028, {184, 167, 137, 255}, 0, 6)
}

nanny_umbrella :: proc(m: ^Mesh_Builder) {
 for i in 0..<10 {
  a, b := f32(i)*math.PI/5, f32(i+1)*math.PI/5
  p, q := game.Vec3{math.cos(a)*0.93, -0.38, math.sin(a)*0.93}, game.Vec3{math.cos(b)*0.93, -0.38, math.sin(b)*0.93}
  mid := (p+q)*0.40+game.Vec3{0, 0.06, 0}
  color := rl.Color{86, 48, 58, 255} if i%3 != 0 else rl.Color{133, 118, 94, 255}
  // Scalloped, torn cloth on exposed ribs instead of alternating candy panels.
  fairy_sheet(m, {}, q, mid, color)
  fairy_sheet(m, {}, mid, p, color)
  if i%3 != 1 { fairy_sheet(m, p, mid, (p+q)*0.52-game.Vec3{0, 0.07, 0}, color) }
  mesh_beam(m, {}, p, 0.015, 0.012, {131, 119, 94, 255}, SURFACE_IRON, 4)
  mesh_beam(m, p, p*1.16-game.Vec3{0, 0.06, 0}, 0.026, 0.002, {128, 114, 90, 255}, SURFACE_IRON, 5)
 }
}

nanny_wheel :: proc(m: ^Mesh_Builder) {
	for i in 0..<12 {
		a, b := f32(i)*math.PI/6, f32(i+1)*math.PI/6
		p, q := game.Vec3{0, math.cos(a)*0.23, math.sin(a)*0.23}, game.Vec3{0, math.cos(b)*0.23, math.sin(b)*0.23}
		mesh_beam(m, p, q, 0.046, 0.046, {58, 58, 60, 255}, 0, 6)
		if i%2 == 0 { mesh_beam(m, {}, p, 0.013, 0.013, {202, 181, 137, 255}, 0, 4) }
	}
}

draw_nanny :: proc(r: ^Renderer, e: game.Enemy_Pose, time: f32) {
	right, up, f := game.enemy_basis(e.facing)
	tint := rl.WHITE if e.flash > 0 else rl.Color{241, 230, 225, 255}
	object_instance(r, .NannyBody, e.position, right, up, -f, tint)
	open := f32(0.25)
	if e.phase == .Windup { open = 0.25+0.75*game.enemy_charge(e) }
	if e.phase == .Attack { open = 1 }
	object_instance(r, .NannyUmbrella, e.position+up*0.90-f*0.38, right*open, up*(1.5-open*0.5), -f*open, tint)
	for side in 0..<2 {
		for axle in 0..<2 {
			p := e.position+right*(f32(side*2-1)*0.64)-f*(f32(axle*2-1)*0.49)-up*0.84
			rotation := -e.gait_phase*1.24
			object_instance(r, .NannyWheel, p, right, up*math.cos(rotation)+f*math.sin(rotation), -f*math.cos(rotation)+up*math.sin(rotation), tint)
		}
	}
	point, radius, exposed := game.enemy_model_weak_spot(e)
	model_beam(r, .Beam, e.position+up*0.2, point, 0.037, MUTED)
	mechanical_weak_point(r, point, right, up, f, radius, exposed && e.health > 0, {89, 90, 67, 255})
}
