package main

import "core:math"
import rl "vendor:raylib"
import game "game"

// All three generations share five cached meshes. Ragged tufts, teeth and
// scars are geometry baked once, not additional per-frame objects.
Rabbit_Ring :: struct { y, width, depth, x, z: f32 }

rabbit_loft :: proc(m: ^Mesh_Builder, rings: []Rabbit_Ring, color: rl.Color, surface: f32) {
	for ring, i in rings {
		for j in 0..<14 {
			a, b := f32(j)*2*math.PI/14, f32(j+1)*2*math.PI/14
			p := game.Vec3{ring.x+math.cos(a)*ring.width, ring.y, ring.z+math.sin(a)*ring.depth}
			q := game.Vec3{ring.x+math.cos(b)*ring.width, ring.y, ring.z+math.sin(b)*ring.depth}
			if i == 0 { mesh_triangle(m, nil, {ring.x, ring.y, ring.z}, p, q, color, surface, 10) }
			if i == len(rings)-1 { mesh_triangle(m, nil, {ring.x, ring.y, ring.z}, q, p, color, surface, 10)
			} else {
				next := rings[i+1]
				u := game.Vec3{next.x+math.cos(b)*next.width, next.y, next.z+math.sin(b)*next.depth}
				v := game.Vec3{next.x+math.cos(a)*next.width, next.y, next.z+math.sin(a)*next.depth}
				shade := f32(0.85) if (j*7+i*3)%11 < 3 else f32(1)
				tint := rl.Color{u8(f32(color.r)*shade), u8(f32(color.g)*shade), u8(f32(color.b)*shade), 255}
				mesh_quad(m, nil, p, v, u, q, tint, surface, 10)
			}
		}
	}
}

rabbit_body :: proc(m: ^Mesh_Builder) {
	fur := rl.Color{183, 174, 150, 255}
	rabbit_loft(m, []Rabbit_Ring{{-0.55, 0.27, 0.43, 0, 0}, {-0.37, 0.48, 0.61, -0.015, 0.04}, {-0.14, 0.61, 0.73, 0.01, 0.05}, {0.10, 0.64, 0.77, 0, 0.06}, {0.33, 0.54, 0.68, -0.015, 0.1}, {0.51, 0.40, 0.48, 0, 0.10}, {0.65, 0.13, 0.20, 0, 0.08}}, fur, SURFACE_CLOTH)
	for i in 0..<18 {
		a := f32(i)*2*math.PI/18
		p := game.Vec3{math.cos(a)*0.56, -0.06+f32(i%3)*0.10, math.sin(a)*0.62}
		fairy_sheet(m, p, p+game.Vec3{math.cos(a)*0.11, -0.27, math.sin(a)*0.15}, p+game.Vec3{-math.sin(a)*0.14, 0.11, math.cos(a)*0.14}, {141, 137, 118, 255})
	}
	for side in ([2]f32{-1, 1}) {
		mesh_beam(m, {side*0.45, -0.34, 0.35}, {side*0.54, -0.06, 0.24}, 0.21, 0.29, fur, SURFACE_CLOTH, 7)
		for scar in 0..<3 { mesh_beam(m, {side*0.58, f32(scar)*0.09-0.12, 0.05}, {side*0.49, f32(scar)*0.09+0.06, -0.22}, 0.018, 0.033, {98, 42, 40, 255}, SURFACE_SKIN, 5) }
	}
}

rabbit_head :: proc(m: ^Mesh_Builder) {
	rabbit_loft(m, []Rabbit_Ring{{-0.17, 0.31, 0.28, 0, -0.08}, {0.02, 0.42, 0.36, 0, -0.07}, {0.28, 0.34, 0.27, 0, 0.03}, {0.43, 0.19, 0.17, 0, 0.04}}, {194, 182, 154, 255}, SURFACE_CLOTH)
	for side in ([2]f32{-1, 1}) {
		// Small recessed eyes under an angry brow, a split lip and long incisors.
		enemy_box(m, {side*0.24, 0.17, -0.245}, {0.13, 0.08, 0.02}, {35, 21, 23, 255}, 0.025, SURFACE_SKIN)
		enemy_box(m, {side*0.24, 0.166, -0.263}, {0.031, 0.024, 0.012}, {166, 35, 21, 255}, 0.005, SURFACE_LIGHT)
		mesh_beam(m, {side*0.15, 0.21, -0.30}, {side*0.34, 0.29, -0.14}, 0.026, 0.042, {132, 125, 105, 255}, SURFACE_CLOTH, 6)
		mesh_beam(m, {side*0.075, -0.04, -0.38}, {side*0.09, -0.31, -0.39}, 0.075, 0.018, {217, 192, 144, 255}, SURFACE_BONE, 5)
		for tooth in 0..<4 {
			x := side*(0.16+f32(tooth)*0.05)
			mesh_beam(m, {x, -0.13, -0.31+f32(tooth)*0.04}, {x, -0.24-f32(tooth%2)*0.05, -0.29+f32(tooth)*0.04}, 0.034, 0.002, {200, 179, 137, 255}, SURFACE_BONE, 5)
		}
	}
	enemy_box(m, {0, -0.02, -0.40}, {0.16, 0.10, 0.09}, {75, 34, 35, 255}, 0.027, SURFACE_SKIN)
}

rabbit_jaw :: proc(m: ^Mesh_Builder) {
	rabbit_loft(m, []Rabbit_Ring{{-0.1, 0.23, 0.23, 0, -0.02}, {0, 0.30, 0.27, 0, 0}, {0.07, 0.26, 0.24, 0, 0}}, {108, 49, 44, 255}, SURFACE_SKIN)
	for side in ([2]f32{-1, 1}) {
		for tooth in 0..<5 {
			x := side*(0.05+f32(tooth)*0.048)
			mesh_beam(m, {x, 0.03, -0.23+f32(tooth)*0.025}, {x, 0.18+f32(tooth%2)*0.05, -0.23+f32(tooth)*0.025}, 0.033, 0.002, {206, 182, 141, 255}, SURFACE_BONE, 5)
		}
	}
}

rabbit_ear :: proc(m: ^Mesh_Builder) {
	rabbit_loft(m, []Rabbit_Ring{{0, 0.105, 0.065, 0, 0}, {0.35, 0.16, 0.055, 0, 0}, {0.79, 0.12, 0.043, 0.03, 0.04}, {1.05, 0.025, 0.02, 0.07, 0.08}}, {173, 161, 137, 255}, SURFACE_CLOTH)
	fairy_sheet(m, {-0.08, 0.17, -0.065}, {0.07, 0.84, -0.02}, {0.1, 0.24, -0.06}, {109, 56, 50, 255})
	fairy_sheet(m, {-0.12, 0.59, -0.02}, {-0.17, 0.91, 0.07}, {-0.04, 0.73, -0.01}, {117, 105, 87, 255})
}

rabbit_paw :: proc(m: ^Mesh_Builder) {
	rabbit_loft(m, []Rabbit_Ring{{-0.06, 0.16, 0.25, 0, -0.08}, {0.06, 0.18, 0.26, 0, -0.07}, {0.22, 0.1, 0.14, 0, 0}}, {140, 130, 113, 255}, SURFACE_CLOTH)
	for i in 0..<3 { mesh_beam(m, {f32(i-1)*0.09, 0.03, -0.27}, {f32(i-1)*0.10, -0.02, -0.39}, 0.027, 0.003, {157, 131, 96, 255}, SURFACE_BONE, 5) }
}

draw_rabbit :: proc(r: ^Renderer, e: game.Enemy_Pose, time: f32) {
	right, up, f := game.enemy_basis(e.facing)
	charge := game.enemy_charge(e)
	stride := math.sin(e.gait_phase)
	if e.health <= 0 { stride, charge = 0, 0 }
	p := e.position+up*(abs(stride)*0.06-charge*0.13)
	tint := rl.Color{255, 220, 202, 255} if e.flash > 0 else rl.WHITE
	object_instance(r, .RabbitBody, p, right, up, -f, tint)
	head := p+f*0.53+up*(0.24+charge*0.08)
	object_instance(r, .RabbitHead, head, right, up, -f, tint)
	gape := f32(0.12)+charge*0.21+(0.25 if e.phase == .Attack else 0)
	jaw := head-up*(0.19+gape)-f*0.02
	object_instance(r, .RabbitJaw, jaw, right, up*math.cos(gape)-f*math.sin(gape), -f*math.cos(gape)-up*math.sin(gape), tint)
	for side in ([2]f32{-1, 1}) {
		tilt := side*(0.17+charge*0.25)+math.sin(time*4+side)*0.035
		object_instance(r, .RabbitEar, head+right*(side*0.22)+up*0.30-f*0.11, right*math.cos(tilt)+up*math.sin(tilt), (up*math.cos(tilt)-right*math.sin(tilt))*(0.87 if side < 0 else f32(1)), -f, tint)
		for rear in 0..<2 {
			step := stride*(1 if rear == 0 else f32(-1))
			foot := e.position+right*(side*0.46)-up*(0.64-max(0, step)*0.13)+f*(0.42 if rear == 0 else -0.5)+f*step*0.12
			object_instance(r, .RabbitPaw, foot, right*(1 if rear == 0 else f32(1.3)), up, -f, tint)
		}
	}
}
