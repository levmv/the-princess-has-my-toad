package main

import "core:math"
import rl "vendor:raylib"
import game "game"

enemy_projectile_mesh :: proc(m: ^Mesh_Builder, kind: Model_Kind) {
	#partial switch kind {
	case .FairyDart:
		// A crooked tooth with torn membranes, not a uniformly lit sphere.
		enemy_lathe(m, []game.Vec2{{0.06, -0.40}, {0.16, -0.14}, {0.12, 0.12}, {0.01, 0.55}}, {190, 173, 116, 255}, 5, SURFACE_BONE)
		for i in 0..<3 {
			a := f32(i)*2*math.PI/3
			d := game.Vec3{math.cos(a), 0, math.sin(a)}
			mesh_triangle(m, nil, d*0.09, d*0.27-game.Vec3{0, 0.48, 0}, -game.Vec3{0, 0.31, 0}, {201, 101, 24, 255}, 0, SURFACE_LIGHT)
			mesh_triangle(m, nil, d*0.09, -game.Vec3{0, 0.31, 0}, d*0.27-game.Vec3{0, 0.48, 0}, {119, 54, 20, 255}, 0, SURFACE_LIGHT)
		}
	case .NannyNeedle:
		enemy_lathe(m, []game.Vec2{{0.11, -0.42}, {0.11, -0.25}, {0.055, -0.22}, {0.055, 0.36}, {0.004, 0.62}}, {165, 177, 166, 255}, 6, SURFACE_IRON)
		enemy_lathe(m, []game.Vec2{{0.17, -0.36}, {0.17, -0.30}}, {77, 182, 122, 255}, 6, SURFACE_LIGHT)
	case .GCShard:
		for side in ([2]f32{-1, 1}) {
			enemy_box(m, {side*0.18, 0, 0}, {0.065, 0.78, 0.08}, {186, 145, 232, 255}, 0.01, SURFACE_LIGHT)
			enemy_box(m, {0, side*0.35, 0}, {0.36, 0.06, 0.08}, {222, 208, 240, 255}, 0.01, SURFACE_LIGHT)
		}
		enemy_box(m, {}, {0.17, 0.33, 0.10}, {49, 35, 63, 255}, 0.025, SURFACE_IRON)
	case: unreachable()
	}
}

draw_enemy_projectile :: proc(r: ^Renderer, bullet: game.Projectile) {
	direction := game.normalized(bullet.velocity)
	reference := game.Vec3{0, 1, 0}
	if abs(direction.y) > 0.98 { reference = {1, 0, 0} }
	right := game.normalized(game.cross(reference, direction))
	up := game.cross(right, direction)
	kind := Model_Kind.FairyDart
	if bullet.source == .Nanny { kind = .NannyNeedle }
	if bullet.source == .GC { kind = .GCShard }
	object_instance(r, kind, bullet.position, right, direction, up, rl.WHITE)
}
