package main

import "core:math"
import rl "vendor:raylib"
import game "game"

enemy_box :: proc(m: ^Mesh_Builder, center, size: game.Vec3, color: rl.Color, bevel: f32 = 0.03, surface: f32 = SURFACE_PAINT) {
	b := game.Block{center = center, size = size}
	game.bevel_block(&b, min(bevel, min(size.x, size.z)*0.25), min(bevel, size.y*0.25))
	mesh_block(m, nil, b, color, color, surface)
}

crab_shell :: proc(m: ^Mesh_Builder) {
	rings := [4]game.Vec3{{-0.30, 0.62, 0.67}, {0, 0.79, 0.78}, {0.32, 0.68, 0.65}, {0.43, 0.46, 0.43}}
	for ring in 0..<len(rings)-1 {
		p, q := rings[ring], rings[ring+1]
		for side in 0..<12 {
			a, b := f32(side)*math.PI/6, f32(side+1)*math.PI/6
			v0, v1 := game.Vec3{math.cos(a)*p.y, p.x, math.sin(a)*p.z}, game.Vec3{math.cos(b)*p.y, p.x, math.sin(b)*p.z}
			v2, v3 := game.Vec3{math.cos(b)*q.y, q.x, math.sin(b)*q.z}, game.Vec3{math.cos(a)*q.y, q.x, math.sin(a)*q.z}
			color := rl.Color{47, 57, 59, 255} if ring > 0 else rl.Color{27, 35, 37, 255}
			if side%3 == 0 && ring > 0 { color = {76, 80, 72, 255} }
			// Open rear service bay, framed below; the heavy plate is at the front.
			if ring == 1 && (side == 2 || side == 3) { continue }
			mesh_quad(m, nil, v0, v3, v2, v1, color, 0, 10)
			if ring == 0 { mesh_triangle(m, nil, {0, p.x, 0}, v0, v1, {32, 39, 42, 255}, 0, 10) }
			if ring == len(rings)-2 { mesh_triangle(m, nil, {0, q.x, 0}, v2, v3, {64, 71, 66, 255}, 0, 10) }
		}
	}
	// Six black memory packages and copper tracks form the shell's silhouette.
	for side in 0..<2 {
		for chip in 0..<3 {
			x, z := f32(side*2-1)*0.28, f32(chip-1)*0.30
			enemy_box(m, {x, 0.43, z}, {0.20, 0.09, 0.22}, {28, 35, 38, 255}, 0.02)
			mesh_beam(m, {x, 0.44, z-0.12}, {x, 0.44, z+0.12}, 0.018, 0.018, {223, 173, 81, 255}, 0, 4)
			for pin in 0..<3 {
				mesh_beam(m, {x-0.13, 0.43, z+f32(pin-1)*0.07}, {x+0.13, 0.43, z+f32(pin-1)*0.07}, 0.011, 0.011, {187, 143, 75, 255}, 0, 4)
			}
		}
	}
 // Recessed optics sit beneath a heavy brow. No ball eyes on stalks.
 for sign in ([2]f32{-1, 1}) {
  enemy_box(m, {sign*0.29, 0.265, -0.635}, {0.24, 0.13, 0.12}, {38, 41, 37, 255}, 0.025)
  enemy_box(m, {sign*0.29, 0.25, -0.705}, {0.13, 0.027, 0.018}, {152, 57, 34, 255}, 0.006, SURFACE_LIGHT)
  mesh_beam(m, {sign*0.16, 0.34, -0.69}, {sign*0.49, 0.35, -0.54}, 0.071, 0.035, {133, 125, 94, 255}, SURFACE_IRON, 5)
  // Only the front shoulder carries a skirt. The flank shows copper pipes,
  // cable and dark machinery instead of repeating the shield's armour colour.
  for i in 0..<3 {
   z := f32(i-1)*0.36
   if i == 0 {
    mesh_beam(m, {sign*0.59, 0.20, z}, {sign*0.80, -0.12, z-0.07}, 0.09, 0.065, {92, 95, 74, 255}, SURFACE_IRON, 5)
   } else {
    mesh_beam(m, {sign*0.70, 0.25, z-0.10}, {sign*0.79, -0.09, z-0.10}, 0.045, 0.045, {174, 104, 59, 255}, SURFACE_IRON, 6)
    mesh_beam(m, {sign*0.79, -0.09, z-0.10}, {sign*0.73, -0.18, z+0.08}, 0.045, 0.045, {174, 104, 59, 255}, SURFACE_IRON, 6)
    mesh_beam(m, {sign*0.78, 0.18, z-0.04}, {sign*0.79, -0.14, z+0.08}, 0.034, 0.034, {88, 43, 35, 255}, 0, 5)
   }
   mesh_beam(m, {sign*0.72, -0.01, z-0.04}, {sign*0.745, -0.01, z-0.04}, 0.042, 0.032, {171, 151, 106, 255}, SURFACE_IRON, 6)
  }
 }
 enemy_box(m, {0, 0.14, 0.63}, {0.72, 0.32, 0.08}, {22, 29, 30, 255}, 0.015)
 for sign in ([2]f32{-1, 1}) {
  mesh_beam(m, {sign*0.38, -0.02, 0.68}, {sign*0.38, 0.31, 0.68}, 0.043, 0.043, {93, 101, 96, 255}, SURFACE_IRON, 5)
 }
 for i in 0..<5 {
  x := f32(i-2)*0.13
  mesh_beam(m, {x, 0.025, 0.70}, {x, 0.255, 0.70}, 0.035, 0.035, {184, 112, 63, 255}, SURFACE_IRON, 6)
 }
 mesh_beam(m, {-0.31, 0.08, 0.74}, {0.31, 0.08, 0.74}, 0.045, 0.045, {88, 43, 35, 255}, 0, 6)
}

crab_plate :: proc(m: ^Mesh_Builder) {
	enemy_box(m, {0, -0.25, 0}, {1.27, 0.60, 0.13}, {144, 136, 105, 255}, 0.05)
	enemy_box(m, {0, -0.24, -0.082}, {0.84, 0.32, 0.045}, {56, 61, 49, 255}, 0.025)
	for stripe in 0..<2 {
		y := -0.16-f32(stripe)*0.16
		mesh_beam(m, {-0.31, y+0.07, -0.111}, {0, y-0.02, -0.111}, 0.032, 0.032, {203, 160, 73, 255}, 0, 4)
		mesh_beam(m, {0, y-0.02, -0.111}, {0.31, y+0.07, -0.111}, 0.032, 0.032, {203, 160, 73, 255}, 0, 4)
	}
 for sign in ([2]f32{-1, 1}) {
  for y in ([2]f32{-0.02, -0.48}) {
   mesh_beam(m, {sign*0.52, y, -0.064}, {sign*0.52, y, -0.093}, 0.049, 0.038, {72, 72, 58, 255}, SURFACE_IRON, 6)
  }
  mesh_beam(m, {sign*0.39, -0.49, -0.074}, {sign*0.16, -0.32, -0.078}, 0.018, 0.003, {195, 173, 125, 255}, SURFACE_IRON, 4)
 }

}

crab_claw :: proc(m: ^Mesh_Builder) {
	enemy_box(m, {0, 0, 0}, {0.32, 0.25, 0.44}, {140, 117, 76, 255}, 0.05)
	for side in 0..<2 {
		sign := f32(side*2-1)
		mesh_beam(m, {sign*0.13, 0, -0.12}, {sign*0.22, 0, -0.38}, 0.11, 0.08, {117, 103, 76, 255}, 0, 5)
		mesh_beam(m, {sign*0.22, 0, -0.38}, {sign*0.06, 0, -0.61}, 0.08, 0.025, {177, 164, 126, 255}, 0, 5)
		for tooth in 0..<3 {
			z := -0.22-f32(tooth)*0.11
			mesh_beam(m, {sign*0.17, 0, z}, {sign*0.035, 0.005, z-0.08}, 0.045, 0.003, {198, 188, 143, 255}, 0, 4)
		}
	}
}

draw_crab :: proc(r: ^Renderer, e: game.Enemy_Pose, time: f32) {
	right, up, f := game.enemy_basis(game.Vec3{e.facing.x, 0, e.facing.z})
	tint := rl.WHITE if e.flash > 0 else rl.Color{226, 239, 218, 255}
	object_instance(r, .CrabShell, e.position, right, up, -f, tint)
	charge := game.enemy_charge(e)
	open := clamp(charge*2.3, 0, 1)
	if e.phase == .Recover || e.exposed > 0 { open = 1 }
	angle := open*1.6
	object_instance(r, .CrabPlate, e.position+f*1.05+up*0.42, right, up*math.cos(angle)-f*math.sin(angle), -f*math.cos(angle)-up*math.sin(angle), tint)
	core, radius, exposed := game.enemy_model_weak_spot(e)
	mechanical_weak_point(r, core, right, up, f, radius, exposed && e.health > 0, {43, 76, 54, 255})
	// Physical contacts frame the exposed insert. Only the critical front core
	// lights up; ordinary vulnerable machinery at the sides/back stays matte.
	for sign in ([2]f32{-1, 1}) {
		point := core+right*(sign*radius*1.28)+f*0.04
		lit := exposed && e.health > 0
		color := rl.Color{255, u8(140+30*math.sin(time*12)), 43, 255} if lit else rl.Color{53, 60, 58, 255}
		model_beam(r, .Beam, point-up*radius*0.7, point+up*radius*0.7, 0.032, color, SURFACE_LIGHT if lit else SURFACE_IRON)
	}
	for side in 0..<2 {
		sign := f32(side*2-1)
		for leg in 0..<3 {
			phase := e.gait_phase+f32(leg)*math.PI*0.67+f32(side)*math.PI
			z := f32(leg-1)*0.46
			a := e.position+right*(sign*0.53)-f*z-up*0.10
			knee := e.position+right*(sign*1.00)-f*(z+math.sin(phase)*0.10)-up*0.22
			foot := e.position+right*(sign*1.14)-f*(z+math.sin(phase)*0.18)-up*(0.60-max(0, math.cos(phase))*0.16)
			model_beam(r, .Beam, a, knee, 0.10, {128, 119, 90, 255})
			model_beam(r, .Beam, knee, foot, 0.06, {103, 110, 94, 255})
			object_instance(r, .Cube, foot, right*0.16, up*0.08, -f*0.23, {39, 47, 43, 255})
		}
		reach := f32(1.0) if e.phase == .Attack else (-charge*0.30)
		shoulder := e.position+right*(sign*0.55)+f*0.20
		claw := e.position+right*(sign*(0.88+charge*0.2))+f*(0.83+reach)+up*(charge*0.26)
		model_beam(r, .Beam, shoulder, claw, 0.11, {133, 144, 114, 255})
		object_instance(r, .CrabClaw, claw, right, up, -f, tint)
	}
}
