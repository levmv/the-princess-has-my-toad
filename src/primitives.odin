package main

import "core:math"
import rl "vendor:raylib"
import game "game"

lit_triangle :: proc(r: ^Renderer, a, b, c: game.Vec3, color: rl.Color) {
	n := game.normalized(game.cross(b-a, c-a))
	object_instance(r, .Triangle, a, b-a, c-a, n, color)
}

model_beam :: proc(r: ^Renderer, kind: Model_Kind, a, b: game.Vec3, radius: f32, color: rl.Color, surface: f32 = -1) {
	direction := game.normalized(b-a)
	helper := game.Vec3{0, 1, 0} if abs(direction.y) < 0.9 else game.Vec3{1, 0, 0}
	u := game.normalized(game.cross(direction, helper))
	v := game.cross(direction, u)
	object_instance(r, kind, a, u*radius, b-a, -v*radius, color, surface)
}

model_sphere :: proc(r: ^Renderer, p: game.Vec3, radius: f32, rings, slices: int, color: rl.Color, surface: f32 = -1) {
	kind := Model_Kind.Shot
	if rings == 5 { kind = .Enemy } else if slices == 8 { kind = .Eye }
	object_instance(r, kind, p, {radius, 0, 0}, {0, radius, 0}, {0, 0, radius}, color, surface)
}

model_cube :: proc(r: ^Renderer, p, size: game.Vec3, color: rl.Color, surface: f32 = -1) {
	object_instance(r, .Cube, p, {size.x, 0, 0}, {0, size.y, 0}, {0, 0, size.z}, color, surface)
}

model_line :: proc(r: ^Renderer, a, b: game.Vec3, color: rl.Color) {
	direction := game.normalized(b-a)
	helper := game.Vec3{0, 1, 0} if abs(direction.y) < 0.9 else game.Vec3{1, 0, 0}
	u := game.normalized(game.cross(direction, helper))
	object_instance(r, .Line, a, u, b-a, game.cross(u, direction), color)
}

ring3 :: proc(r: ^Renderer, center: game.Vec3, radius: f32, color: rl.Color, vertical: bool = false, phase: f32 = 0, fraction: f32 = 1) {
	c, s := math.cos(phase)*radius, math.sin(phase)*radius
	x, y, z := game.Vec3{c, 0, s}, game.Vec3{0, 1, 0}, game.Vec3{-s, 0, c}
	if vertical { x, y, z = {c, s, 0}, {0, 0, -1}, {-s, c, 0} }
	object_instance(r, .Ring if fraction == 1 else .Arc, center, x, y, z, color)
}
