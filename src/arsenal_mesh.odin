package main

import "core:math"
import rl "vendor:raylib"
import game "game"

shotgun_mesh :: proc(m: ^Mesh_Builder) {
	// Twin steel bores, a worn receiver and a wooden stock. Local -Z is forward.
	steel, wood := rl.Color{86, 86, 80, 255}, rl.Color{99, 57, 34, 255}
	enemy_box(m, {0, -0.025, 0.58}, {0.25, 0.20, 0.33}, steel, 0.035, SURFACE_IRON)
	enemy_box(m, {0, -0.13, 0.92}, {0.18, 0.27, 0.42}, wood, 0.05, SURFACE_CLOTH)
	enemy_box(m, {0, -0.13, 1.14}, {0.19, 0.28, 0.04}, {33, 31, 28, 255}, 0.012, SURFACE_CLOTH)
	enemy_box(m, {0, -0.10, 0.30}, {0.22, 0.14, 0.28}, wood, 0.022, SURFACE_CLOTH)
	for side in ([2]f32{-1, 1}) {
		x := side*0.066
		mesh_beam(m, {x, 0, 0.49}, {x, 0, 0}, 0.064, 0.053, steel, SURFACE_IRON, 10)
		mesh_beam(m, {x, 0, -0.002}, {x, 0, -0.006}, 0.037, 0.037, {12, 11, 10, 255}, SURFACE_IRON, 10)
		mesh_beam(m, {side*0.117, -0.10, 0.46}, {side*0.117, -0.16, 0.62}, 0.017, 0.017, steel, SURFACE_IRON, 5)
	}
	enemy_box(m, {0, 0.061, 0.04}, {0.016, 0.032, 0.045}, {183, 148, 92, 255}, 0.005, SURFACE_IRON)
	for i in 0..<5 { enemy_box(m, {0, -0.172, 0.19+f32(i)*0.043}, {0.19, 0.012, 0.011}, {52, 34, 26, 255}, 0, SURFACE_CLOTH) }
}

shell_packet :: proc(m: ^Mesh_Builder) {
	enemy_box(m, {0, -0.15, 0}, {0.48, 0.20, 0.31}, {78, 62, 42, 255}, 0.018, SURFACE_CLOTH)
	for i in 0..<4 {
		x, z := f32(i%2)*0.22-0.11, f32(i/2)*0.15-0.075
		mesh_beam(m, {x, -0.10, z}, {x, 0.18, z}, 0.065, 0.065, {112, 31, 22, 255}, SURFACE_PAINT, 8)
		mesh_beam(m, {x, -0.12, z}, {x, -0.05, z}, 0.072, 0.072, {180, 131, 58, 255}, SURFACE_IRON, 8)
	}
}

fragment_shell :: proc(m: ^Mesh_Builder) {
	profile := [6]game.Vec2{{0.065, -0.26}, {0.11, -0.20}, {0.11, 0.09}, {0.085, 0.19}, {0.035, 0.28}, {0.008, 0.30}}
	enemy_lathe(m, profile[:], {92, 91, 76, 255}, 10, SURFACE_IRON)
	enemy_lathe(m, []game.Vec2{{0.117, -0.15}, {0.117, -0.09}}, {182, 127, 52, 255}, 10, SURFACE_IRON)
	for i in 0..<4 {
		a := f32(i)*math.PI*0.5
		d := game.Vec3{math.cos(a), 0, math.sin(a)}
		mesh_triangle(m, nil, d*0.08-game.Vec3{0, 0.08, 0}, d*0.17-game.Vec3{0, 0.23, 0}, d*0.07-game.Vec3{0, 0.26, 0}, {64, 63, 55, 255}, SURFACE_IRON, 10)
		mesh_triangle(m, nil, d*0.08-game.Vec3{0, 0.08, 0}, d*0.07-game.Vec3{0, 0.26, 0}, d*0.17-game.Vec3{0, 0.23, 0}, {64, 63, 55, 255}, SURFACE_IRON, 10)
	}
}

gib_chunk :: proc(m: ^Mesh_Builder, bone: bool) {
	if bone {
		mesh_beam(m, {-0.12, -0.36, 0}, {0.09, 0.32, 0.06}, 0.13, 0.095, {183, 154, 119, 255}, SURFACE_BONE, 5)
		mesh_beam(m, {0.09, 0.19, 0.06}, {0.14, 0.43, 0.02}, 0.17, 0.08, {103, 24, 20, 255}, SURFACE_SKIN, 5)
	} else {
		fairy_loft(m, []Fairy_Ring{{-0.35, 0.18, 0.16, 0.05, 0}, {-0.17, 0.46, 0.30, -0.02, 0.05}, {0.14, 0.34, 0.41, 0, -0.05}, {0.29, 0.18, 0.21, -0.07, 0}}, {120, 26, 28, 255}, SURFACE_SKIN)
		mesh_beam(m, {-0.1, 0.16, 0.07}, {0.1, 0.40, 0.12}, 0.10, 0.065, {168, 134, 102, 255}, SURFACE_BONE, 5)
	}
}

draw_gibs :: proc(r: ^Renderer, g: ^game.Render_Snapshot) {
	r.objects.passes = WORLD_PASS|SHADOW_PASS
	for p, i in g.gibs {
		if p.life <= 0 { continue }
		angle := game.dot(p.position, {2.1, 3.5, 1.7})+f32(i)
		x := game.Vec3{math.cos(angle), math.sin(angle), 0}
		y := game.Vec3{-math.sin(angle), math.cos(angle), 0}
		scale := p.size*(2.4 if p.kind == 2 else f32(1.6))*min(1, p.life)
		kind := Model_Kind.FairyHead if p.kind == 2 else (.GibBone if p.kind == 1 else .GibFlesh)
		object_instance(r, kind, p.position, x*scale, y*scale, {0, 0, scale}, rl.WHITE, SURFACE_BONE if p.kind == 2 else -1)
	}
}

draw_gibbed_corpse :: proc(r: ^Renderer, dead: game.Enemy_Pose) {
	p := dead.position-game.Vec3{0, game.enemy_extent(dead.kind).y-0.16, 0}
	for i in 0..<3 {
		angle := f32(i)*2.2
		q := p+game.Vec3{math.cos(angle)*0.28, 0, math.sin(angle)*0.22}
		object_instance(r, .GibFlesh, q, {0.47, 0, 0}, {0, 0.32, 0}, {0, 0, 0.48}, rl.WHITE)
	}
	distance := game.world_ray(r.world_source, dead.position, {0, -1, 0}, game.enemy_extent(dead.kind).y+0.12)
	if distance < game.enemy_extent(dead.kind).y+0.10 {
		object_instance(r, .BloodSplat, dead.position-game.Vec3{0, distance-0.02, 0}, {0.85, 0, 0}, {0, 1, 0}, {0, 0, 0.66}, {94, 8, 14, 255})
	}
}
