package main

import "core:math"
import rl "vendor:raylib"
import game "game"

// Profiles are radius/height. These small authored surfaces are uploaded once.
enemy_lathe :: proc(m: ^Mesh_Builder, profile: []game.Vec2, color: rl.Color, sides: int = 12, surface: f32 = SURFACE_PAINT) {
	for p, ring in profile[:len(profile)-1] {
		q := profile[ring+1]
		for side in 0..<sides {
			a, b := f32(side)*2*math.PI/f32(sides), f32(side+1)*2*math.PI/f32(sides)
			v0, v1 := game.Vec3{p.x*math.cos(a), p.y, p.x*math.sin(a)}, game.Vec3{p.x*math.cos(b), p.y, p.x*math.sin(b)}
			v2, v3 := game.Vec3{q.x*math.cos(b), q.y, q.x*math.sin(b)}, game.Vec3{q.x*math.cos(a), q.y, q.x*math.sin(a)}
			mesh_quad(m, nil, v0, v3, v2, v1, color, surface, 10)
			if ring == 0 { mesh_triangle(m, nil, {0, p.y, 0}, v0, v1, color, surface, 10) }
			if ring == len(profile)-2 { mesh_triangle(m, nil, {0, q.y, 0}, v2, v3, color, surface, 10) }
		}
	}
}

kettle_body :: proc(m: ^Mesh_Builder) {
	profile := [5]game.Vec2{{0.34, -0.54}, {0.52, -0.43}, {0.63, -0.08}, {0.55, 0.34}, {0.34, 0.55}}
	enemy_lathe(m, profile[:], {165, 158, 128, 255})
	band := [2]game.Vec2{{0.635, -0.10}, {0.621, 0.04}}
	enemy_lathe(m, band[:], {66, 77, 72, 255})

 // Blackened cast base, patched enamel and riveted repair strips. The repair
 // follows the vessel's actual facets instead of floating rectangular decals.
 base := [3]game.Vec2{{0.34, -0.555}, {0.526, -0.43}, {0.56, -0.32}}
 enemy_lathe(m, base[:], {64, 62, 52, 255}, 12, SURFACE_IRON)
 for side in ([3]int{0, 4, 8}) {
  a, b := f32(side)*math.PI/6+0.03, f32(side+1)*math.PI/6-0.03
  low, high := f32(0.588), f32(0.623)
  v0, v1 := game.Vec3{math.cos(a)*low, -0.26, math.sin(a)*low}, game.Vec3{math.cos(b)*low, -0.26, math.sin(b)*low}
  v2, v3 := game.Vec3{math.cos(b)*high, 0.09, math.sin(b)*high}, game.Vec3{math.cos(a)*high, 0.09, math.sin(a)*high}
  mesh_quad(m, nil, v0, v3, v2, v1, {89, 81, 66, 255}, SURFACE_IRON, 10)
  mesh_beam(m, v0, v3, 0.014, 0.014, {135, 111, 78, 255}, SURFACE_IRON, 5)
  mesh_beam(m, v1, v2, 0.014, 0.014, {135, 111, 78, 255}, SURFACE_IRON, 5)
 }
	// A bent copper spout and hollow handle make the silhouette unmistakable.
	mesh_beam(m, {0, -0.05, -0.43}, {0, 0.12, -0.83}, 0.18, 0.13, {101, 75, 54, 255}, 0, 8)
	mesh_beam(m, {0, 0.12, -0.83}, {0, 0.51, -1.0}, 0.13, 0.09, {121, 107, 79, 255}, 0, 8)
	mesh_beam(m, {0, 0.507, -1.0}, {0, 0.522, -1.005}, 0.066, 0.066, {25, 34, 33, 255}, 0, 8)
	for i in 0..<10 {
		a, b := f32(i)*math.PI/10-math.PI/2, f32(i+1)*math.PI/10-math.PI/2
		p, q := game.Vec3{0, math.sin(a)*0.5, 0.50+math.cos(a)*0.50}, game.Vec3{0, math.sin(b)*0.5, 0.50+math.cos(b)*0.50}
		mesh_beam(m, p, q, 0.083, 0.083, {49, 57, 49, 255}, 0, 6)
	}
	// Two disgruntled rivets stare over the spout.
	enemy_box(m, {0, -0.23, -0.585}, {0.62, 0.23, 0.07}, {36, 25, 26, 255}, 0.035)
	for tooth in 0..<7 {
		x := f32(tooth-3)*0.075
		mesh_beam(m, {x, -0.13, -0.632}, {x+0.016, -0.25-f32(tooth%2)*0.04, -0.643}, 0.031, 0.005, {184, 168, 117, 255}, 0, 4)
	}
	for sign in ([2]f32{-1, 1}) {
		enemy_box(m, {sign*0.22, 0.22, -0.52}, {0.13, 0.085, 0.05}, {37, 54, 47, 255}, 0.01)
		enemy_box(m, {sign*0.22, 0.215, -0.552}, {0.07, 0.032, 0.02}, {190, 57, 27, 255}, 0, SURFACE_LIGHT)
		mesh_beam(m, {sign*0.13, 0.24, -0.552}, {sign*0.33, 0.33, -0.47}, 0.041, 0.033, {93, 73, 47, 255}, 0, 5)
		// Reinforced straps and broad rivets around a battered pressure vessel.
		for i in 0..<5 {
			a := f32(i)*0.35-0.7
			p := game.Vec3{sign*math.cos(a)*0.59, -0.07, math.sin(a)*0.59}
			mesh_beam(m, p-game.Vec3{0, 0.045, 0}, p+game.Vec3{0, 0.045, 0}, 0.045, 0.045, {116, 88, 54, 255}, 0, 6)
		}
	}
	mesh_beam(m, {-0.28, 0.43, -0.31}, {-0.33, 0.60, -0.46}, 0.065, 0.055, {125, 90, 49, 255}, 0, 8)
	enemy_box(m, {-0.33, 0.66, -0.47}, {0.25, 0.23, 0.09}, {45, 51, 49, 255}, 0.04)
	enemy_box(m, {-0.33, 0.66, -0.523}, {0.19, 0.16, 0.018}, {214, 203, 160, 255}, 0.025)
	mesh_beam(m, {-0.33, 0.62, -0.54}, {-0.38, 0.71, -0.54}, 0.009, 0.009, {74, 35, 29, 255}, 0, 4)
}

kettle_lid :: proc(m: ^Mesh_Builder) {
	profile := [3]game.Vec2{{0.40, 0}, {0.34, 0.075}, {0.1, 0.16}}
	enemy_lathe(m, profile[:], {98, 104, 89, 255})
	mesh_beam(m, {0, 0.13, 0}, {0, 0.26, 0}, 0.07, 0.07, {147, 102, 69, 255}, 0, 8)
}

draw_kettle :: proc(r: ^Renderer, e: game.Enemy_Pose, time: f32) {
	right, up, f := game.enemy_basis(e.facing)
	charge := game.enemy_charge(e)
	squat := charge*0.13
	position := e.position-up*squat
	tint := rl.WHITE if e.flash > 0 else rl.Color{246, 235, 218, 255}
	object_instance(r, .KettleBody, position, right, up, -f, tint)
	shake := math.sin(time*48)*charge*0.025
	object_instance(r, .KettleLid, position+up*(0.55+charge*0.12)+right*shake, right, up, -f, tint)
	weak, radius, open := game.enemy_model_weak_spot(e)
	model_beam(r, .Beam, position+up*0.69, weak, 0.085, {66, 65, 55, 255}, SURFACE_IRON)
	mechanical_weak_point(r, weak, right, up, f, radius, open && e.health > 0, {75, 69, 53, 255})
	for sign in ([2]f32{-1, 1}) {
		leg := math.sin(e.gait_phase+sign*math.PI*0.5)*0.10
		foot := e.position+right*(sign*0.32)-up*0.85+f*leg
		object_instance(r, .Cube, foot, right*0.35, up*0.10, -f*0.43, {54, 64, 59, 255})
		for coil in 0..<12 {
			a, b := f32(coil)*math.PI/2, f32(coil+1)*math.PI/2
			p := foot+up*(0.08+f32(coil)*(0.028-squat*0.035))+right*(math.cos(a)*0.11)+f*(math.sin(a)*0.11)
			q := foot+up*(0.08+f32(coil+1)*(0.028-squat*0.035))+right*(math.cos(b)*0.11)+f*(math.sin(b)*0.11)
			model_beam(r, .Beam, p, q, 0.025, {156, 155, 116, 255})
		}
	}
	if e.phase == .Windup || e.phase == .Attack {
		for i in 0..<3 {
			puff := math.mod(time*2+f32(i)*0.31, 1)
			model_sphere(r, e.position+up*(0.9+puff*0.9)+right*(puff*0.18), 0.03+puff*0.08, 4, 6, MUTED)
		}
	}
}

draw_floor_hazards :: proc(r: ^Renderer, g: ^game.Render_Snapshot, time: f32) {
	for h in g.hazards {
		if h.life <= 0 { continue }
		radius := h.radius*min(1, h.life*3)
		ring3(r, h.position, radius, ORANGE)
		for i in 0..<18 {
			a := f32(i)*2.39996+time*0.1
			distance := math.sqrt(f32(i)/18)*radius
			p := h.position+game.Vec3{math.cos(a)*distance, 0, math.sin(a)*distance}
			v := min(0.45, h.life)*0.5*(1+math.sin(time*8+f32(i)))
			model_beam(r, .Beam, p, p+game.Vec3{0, 0.05+v, 0}, 0.10, ORANGE if h.warmup <= 0 else MUTED, SURFACE_LIGHT if h.warmup <= 0 else SURFACE_IRON)
		}
	}
}
