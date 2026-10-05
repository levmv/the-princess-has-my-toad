package main

import "core:math"
import "core:fmt"
import game "game"

draw_mission_objects :: proc(r: ^Renderer, g: ^game.Render_Snapshot, time: f32) {
	for gate in g.world.gates[:g.world.gate_count] {
		shape := game.gate_shape(gate)
		model_cube(r, shape.center, shape.size, {49, 65, 76, 255})
		for side in ([2]f32{-1, 1}) {
			p := shape.center+game.Vec3{0, 0, side*(shape.size.z*0.5+0.02)}
			size := game.Vec3{shape.size.x*0.8, 0.10, 0.04}
			if shape.size.x < shape.size.z { p = shape.center+game.Vec3{side*(shape.size.x*0.5+0.02), 0, 0}; size = {0.04, 0.10, shape.size.z*0.8} }
			model_cube(r, p, size, ORANGE)
		}
		model_beam(r, .Beam, gate.control-game.Vec3{0, 1.3, 0}, gate.control, 0.14, MUTED)
		model_cube(r, gate.control, {0.5, 0.35, 0.3}, MINT if gate.open else ORANGE, SURFACE_LIGHT)
	}
	if game.boss_exit_present(g.world) {
		shape := game.boss_exit_shape(g.world)
		model_cube(r, shape.center, shape.size, {55, 64, 65, 255}, SURFACE_IRON)
		for side in ([2]f32{-1, 1}) {
			model_cube(r, shape.center+game.Vec3{side*3.6, 0, 0.30}, {0.22, 5.7, 0.06}, ORANGE)
		}
		model_cube(r, shape.center+game.Vec3{0, 0, 0.31}, {2.3, 0.25, 0.08}, MINT if g.boss.phase == .Dead else ORANGE, SURFACE_LIGHT)
	}
	if g.world.sector.mechanism == .Shot_Lift {
		p := g.world.lift.button
		color := MINT if g.lift_started else ORANGE
		// A raised, luminous target stands proud of the dark wall bracket.
		model_sphere(r, p, game.LIFT_BUTTON_RADIUS, 6, 12, color, SURFACE_LIGHT)
		for side in ([2]f32{-1, 1}) {
			model_cube(r, p+game.Vec3{0, side*1.0, 0}, {0.16, 0.12, 1.6}, PAPER, SURFACE_LIGHT)
		}
		cable := game.lift_cable(g.world)
		for point in cable[1:] {
			model_sphere(r, point, 0.19, 4, 6, color, SURFACE_LIGHT)
		}
	}
	for vent in g.world.vents {
		running := game.vent_running(vent, g.lift_started)
		for blade in 0..<6 {
			a := f32(blade)*math.PI/3+(time*4 if running else 0)
			x := game.Vec3{math.cos(a), 0, math.sin(a)}
			z := game.Vec3{-math.sin(a), 0, math.cos(a)}
			object_instance(r, .Cube, vent.position+game.Vec3{0, 0.10, 0}+x*(vent.radius*0.5), x*(vent.radius*0.54), {0, 0.07, 0}, z*0.40, {102, 129, 130, 255})
		}
	}
}

// Physical targets need no interaction prompt.
draw_mission_hud :: proc(ui: UI, g: ^game.State, use_key: string = "E") {
	if game.gate_target(g.world, &g.player) >= 0 {
		buffer: [64]u8
		text := fmt.bprintf(buffer[:], "[%s]", use_key)
		label(ui, text, ui.width*0.5-f32(len(text))*3.8, ui.height*0.5+32, 13, PAPER, 2)
	}
}
