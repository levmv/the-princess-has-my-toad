package main

import "core:math"
import rl "vendor:raylib"
import game "game"

fragment_barrel :: proc(m: ^Mesh_Builder) {
	profile := [4]game.Vec2{{0.14, -0.34}, {0.20, -0.25}, {0.19, -0.08}, {0.16, 0}}
		enemy_lathe(m, profile[:], {97, 99, 91, 255}, 10, SURFACE_IRON)
	// Dark bore, copper collar and raised cooling fins.
	mesh_beam(m, {0, 0, 0}, {0, 0.008, 0}, 0.11, 0.11, {22, 32, 31, 255}, 0, 10)
	for i in 0..<5 {
		a := f32(i)*2*math.PI/5
		v := game.Vec3{math.cos(a), 0, math.sin(a)}*0.195
		mesh_beam(m, v-game.Vec3{0, 0.24, 0}, v-game.Vec3{0, 0.08, 0}, 0.022, 0.022, {211, 150, 69, 255}, 0, 4)
	}
}

pickup_diskette :: proc(m: ^Mesh_Builder) {
	enemy_box(m, {}, {0.66, 0.68, 0.10}, {44, 116, 92, 255}, 0.04)
	enemy_box(m, {0, 0.21, -0.064}, {0.41, 0.21, 0.025}, {173, 185, 165, 255}, 0.01)
	enemy_box(m, {0, -0.1, -0.065}, {0.50, 0.30, 0.025}, {205, 218, 177, 255}, 0.01)
	enemy_box(m, {0, -0.1, -0.085}, {0.21, 0.06, 0.012}, {51, 145, 101, 255}, 0)
	enemy_box(m, {0, -0.1, -0.088}, {0.065, 0.22, 0.012}, {51, 145, 101, 255}, 0)
	mesh_beam(m, {0, 0.20, -0.09}, {0, 0.20, -0.093}, 0.047, 0.047, {34, 43, 45, 255}, 0, 8)
}

ammo_packet :: proc(m: ^Mesh_Builder) {
	enemy_box(m, {0, -0.02, 0}, {0.58, 0.20, 0.38}, {72, 90, 85, 255}, 0.03)
	for sign in ([2]f32{-1, 1}) {
		mesh_beam(m, {sign*0.15, -0.27, 0}, {sign*0.15, 0.27, 0}, 0.11, 0.10, {172, 121, 60, 255}, 0, 8)
		mesh_beam(m, {sign*0.15, 0.24, 0}, {sign*0.15, 0.33, 0}, 0.083, 0.05, {222, 182, 89, 255}, 0, 8)
	}
}

launcher_pickup :: proc(m: ^Mesh_Builder) {
	enemy_box(m, {0, 0, -0.15}, {0.69, 0.36, 0.85}, {65, 82, 80, 255}, 0.06)
	enemy_box(m, {0, -0.08, -0.72}, {0.54, 0.49, 0.29}, {33, 43, 46, 255}, 0.04)
	enemy_box(m, {0, -0.28, -0.37}, {0.18, 0.4, 0.26}, {181, 117, 55, 255}, 0.04)
	for side in ([2]f32{-1, 1}) {
		x := side*0.22
		mesh_beam(m, {x, 0.04, -0.24}, {x, 0.04, 0.77}, 0.18, 0.18, {124, 139, 124, 255}, 0, 10)
		mesh_beam(m, {x, 0.04, 0.76}, {x, 0.04, 0.79}, 0.13, 0.13, {22, 31, 31, 255}, 0, 10)
		for ring in 0..<3 {
			z := f32(ring)*0.23+0.02
			mesh_beam(m, {x, 0.04, z}, {x, 0.04, z+0.055}, 0.205, 0.205, {207, 147, 62, 255}, 0, 10)
		}
	}
	enemy_box(m, {0, 0.28, -0.09}, {0.15, 0.16, 0.3}, {39, 52, 53, 255}, 0.02)
}

draw_weapons_and_pickups :: proc(r: ^Renderer, g: ^game.Render_Snapshot, time: f32) {
	r.objects.passes = WORLD_PASS|SHADOW_PASS
	for pickup in g.pickups {
		if pickup.collected { continue }
		angle := time*0.55
		x, z := game.Vec3{math.cos(angle), 0, -math.sin(angle)}, game.Vec3{math.sin(angle), 0, math.cos(angle)}
		position := pickup.position+game.Vec3{0, math.sin(time*2.2)*0.06, 0}
		kind := Model_Kind.Diskette if pickup.kind == .Health else (.LauncherPickup if pickup.kind == .Launcher else .AmmoPacket)
		if pickup.kind == .Shotgun { kind = .ShotgunBody }
		if pickup.kind == .Shells { kind = .ShellPacket }
		object_instance(r, kind, position, x, {0, 1, 0}, z, rl.WHITE)
	}
	r.objects.passes = WORLD_PASS
	for fragment in g.fragments {
		if fragment.life <= 0 { continue }
		direction := game.normalized(fragment.velocity)
		right := game.normalized(game.cross(direction, {0, 1, 0}))
		if game.length(right) < 0.5 { right = {1, 0, 0} }
		up := game.cross(right, direction)
		object_instance(r, .FragmentShell, fragment.position, right, direction, up, rl.WHITE)
	}
}
