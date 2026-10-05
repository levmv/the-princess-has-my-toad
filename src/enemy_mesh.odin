package main

import "core:math"
import rl "vendor:raylib"
import game "game"

core_cage :: proc(m: ^Mesh_Builder) {
	for y in ([2]f32{-0.69, 0.69}) {
		profile := [2]game.Vec2{{0.75, y-0.10}, {0.75, y+0.10}}
		enemy_lathe(m, profile[:], {122, 112, 88, 255}, 8, SURFACE_IRON)
	}
	for i in 0..<4 {
		a := f32(i)*math.PI*0.5
		d := game.Vec3{math.cos(a), 0, math.sin(a)}
		mesh_beam(m, d*0.65-game.Vec3{0, 0.69, 0}, d+game.Vec3{0, 0.05, 0}, 0.075, 0.065, {81, 81, 68, 255}, SURFACE_IRON, 5)
		mesh_beam(m, d+game.Vec3{0, 0.05, 0}, d*0.65+game.Vec3{0, 0.69, 0}, 0.065, 0.075, {81, 81, 68, 255}, SURFACE_IRON, 5)
	}
}

mechanical_weak_point :: proc(r: ^Renderer, point, right, up, forward: game.Vec3, radius: f32, exposed: bool, cold: rl.Color) {
	model_sphere(r, point, radius*0.92, 4, 8, ORANGE if exposed else cold, SURFACE_LIGHT if exposed else SURFACE_IRON)
	object_instance(r, .CoreCage, point, right*radius, up*radius, -forward*radius, rl.WHITE)
}

// A single scale drives mesh, weak spots and swept collision. World-space
// attack markers and support links are drawn after the model transform.
draw_enemy :: proc(r: ^Renderer, e: game.Enemy_Pose, time: f32) {
	start := r.objects.count
	draw_enemy_model(r, e, time)
	scale := game.enemy_scale(e.kind)
	if e.phase == .Hatching { scale *= 0.4+0.6*clamp(1-e.phase_time/game.RABBIT_HATCH_TIME, 0, 1) }
	for &command in r.objects.commands[start:r.objects.count] {
		instance := &command.instance
		for axis in 0..<3 {
			instance.transform[3][axis] = e.position[axis]+(instance.transform[3][axis]-e.position[axis])*scale
			for row in 0..<3 {
				instance.transform[axis][row] *= scale
				instance.normal[axis][row] /= scale
			}
		}
	}
	if e.kind == .Kettle && (e.phase == .Windup || e.phase == .Attack) {
		ring3(r, e.attack_target, game.KETTLE_RADIUS, ORANGE)
		for i in 0..<8 {
			a := f32(i)*math.PI/4
			direction := game.Vec3{math.cos(a), 0, math.sin(a)}
			model_line(r, e.attack_target+direction*(game.KETTLE_RADIUS-0.5), e.attack_target+direction*game.KETTLE_RADIUS, ORANGE)
		}
	}
	if e.shielding {
		point, _, _ := game.enemy_weak_spot(e)
		model_line(r, point, e.support_position, MINT)
		ring3(r, e.support_position, 1.0+math.sin(time*4)*0.08, MINT)
	}
}

draw_enemy_model :: proc(r: ^Renderer, e: game.Enemy_Pose, time: f32) {
	if game.rabbit_kind(e.kind) { draw_rabbit(r, e, time); return }
	if e.kind == .Crab { draw_crab(r, e, time); return }
	if e.kind == .Kettle { draw_kettle(r, e, time); return }
	if e.kind == .Nanny { draw_nanny(r, e, time); return }
	draw_fairy(r, e, time)
}
