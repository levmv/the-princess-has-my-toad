package main

import "core:math"
import rl "vendor:raylib"
import game "game"

gc_fittings :: proc(m: ^Mesh_Builder) {
	metal := rl.Color{131, 157, 150, 255}
	dark := rl.Color{31, 49, 54, 255}
	for y in ([3]f32{1.5, 3.0, 6.4}) {
		for i in 0..<8 {
			a, b := (f32(i)*2+1)*math.PI/8, (f32(i+1)*2+1)*math.PI/8
			radius := f32(3.05)
			mesh_beam(m, {math.cos(a)*radius, y, math.sin(a)*radius}, {math.cos(b)*radius, y, math.sin(b)*radius}, 0.10, 0.10, metal, 2, 6)
		}
	}
	for x in ([2]f32{-2.0, 2.0}) {
		for z in ([3]f32{-1.8, 0, 1.8}) {
			mesh_beam(m, {x, 1.7, z}, {x*1.2, 0.6, z}, 0.16, 0.11, metal, 0, 6)
			mesh_beam(m, {x*1.2-0.22, 0.43, z}, {x*1.2+0.22, 0.43, z}, 0.40, 0.40, dark, 0, 10)
		}
	}
	// A graduation cap far too large for the little optical face.
	enemy_box(m, {0, 6.62, 0}, {3.7, 0.35, 3.7}, dark, 0.10)
	enemy_box(m, {0, 6.92, 0}, {6.8, 0.24, 6.8}, {47, 45, 68, 255}, 0.13)
	for x in ([2]f32{-0.85, 0.85}) {
		enemy_box(m, {x, 5.65, 2.90}, {0.58, 0.72, 0.24}, dark, 0.07)
		enemy_box(m, {x+0.08, 5.68, 3.045}, {0.14, 0.36, 0.03}, {210, 232, 221, 255}, 0.01)
		// Small ear handles, one comically bent.
		mesh_beam(m, {x*3.5, 4.5, 0}, {x*4.2, 4.9, 0}, 0.18, 0.18, metal, 0, 8)
		mesh_beam(m, {x*4.2, 4.9, 0}, {x*4.2, 3.7, 0.4}, 0.18, 0.18, metal, 0, 8)
	}
	// Three pressure tanks are the readable phase indicator on the front.
	for i in 0..<3 {
		x := f32(i-1)*0.72
		enemy_box(m, {x, 2.2, 2.94}, {0.52, 0.54, 0.21}, dark, 0.08)
	}
	for side in ([2]f32{-1, 1}) {
		for i in 0..<7 {
			mesh_beam(m, {side*2.65, 3.8+f32(i)*0.24, -0.7}, {side*2.65, 3.8+f32(i)*0.24, 0.7}, 0.045, 0.045, dark, 0, 4)
		}
	}
}

gc_brush :: proc(m: ^Mesh_Builder) {
	enemy_box(m, {0, 0.45, 0}, {1, 0.45, 1.1}, {158, 119, 62, 255}, 0.12)
	enemy_box(m, {0, 0.74, 0}, {0.75, 0.18, 0.65}, {61, 77, 75, 255}, 0.07)
	for i in 0..<14 {
		x := (f32(i)+0.5)/14-0.5
		mesh_beam(m, {x, 0.33, 0.36}, {x, 0.02, 0.46}, 0.021, 0.016, {183, 210, 166, 255}, 0, 4)
		mesh_beam(m, {x, 0.33, -0.36}, {x, 0.02, -0.46}, 0.021, 0.016, {66, 86, 71, 255}, 0, 4)
	}
}

pixel_anvil :: proc(m: ^Mesh_Builder) {
	rows := [8]string{"  ##########", "############", "########### ", "    ####    ", "     ##     ", "     ##     ", "   ######   ", "  ########  "}
	for row, y in rows {
		for pixel, x in row {
			if pixel != '#' { continue }
			color := rl.Color{142, 151, 176, 255}
			if y == 0 { color = {235, 221, 233, 255} }
			if y >= 6 { color = {65, 79, 111, 255} }
			enemy_box(m, {(f32(x)-5.5)*0.15, (3.5-f32(y))*0.15, 0}, {0.15, 0.15, 1.1}, color, 0)
		}
	}
}

draw_boss :: proc(r: ^Renderer, g: ^game.Render_Snapshot, time: f32) {
	b := g.boss
	if b.id == 0 { return }
	p := game.boss_origin(g.world)
	r.objects.passes = WORLD_PASS|SHADOW_PASS
	object_instance(r, .GCFittings, p, {1, 0, 0}, {0, 1, 0}, {0, 0, 1}, rl.WHITE)
	dead := b.phase == .Dead
	open := clamp((b.duration-b.timer)/0.18, 0, 1) if b.phase == .Exposed else f32(0)
	if dead { open = 1 }
	for side in ([2]f32{-1, 1}) {
		model_cube(r, p+game.Vec3{side*(0.36+open*0.96), 4, 3.74}, {0.71, 1.5, 0.20}, {73, 110, 112, 255})
		model_cube(r, p+game.Vec3{side*(0.36+open*0.96), 4.34, 3.86}, {0.42, 0.10, 0.04}, ORANGE if !dead else MUTED)
	}
	color := MUTED if dead else (PAPER if b.flash > 0 else ORANGE)
	model_sphere(r, game.boss_core(g.world), 0.65 if open > 0.5 else 0.3, 6, 12, color, SURFACE_LIGHT if !dead && open > 0.5 else SURFACE_IRON)
	for i in 0..<3 {
		lit := b.health > (2-i)*12
		model_cube(r, p+game.Vec3{f32(i-1)*0.72, 2.2, 3.07}, {0.29, 0.33, 0.03}, MINT if lit else INK, SURFACE_LIGHT if lit else SURFACE_PAINT)
	}
	// A swinging tassel, not a UI name tag, identifies this as the trainee.
	end := p+game.Vec3{3.3, 5.55, math.sin(time*1.4)*0.32}
	model_beam(r, .Beam, p+game.Vec3{0, 7.07, 0}, p+game.Vec3{3.3, 7.07, 0}, 0.045, ORANGE)
	model_beam(r, .Beam, p+game.Vec3{3.3, 7.07, 0}, end, 0.045, ORANGE)
	model_beam(r, .Beam, end, end-game.Vec3{0, 0.42, 0}, 0.14, ORANGE)
	if dead {
		// The enormous pacifier is the absurd clue left by the collector.
		q := p+game.Vec3{0, 0.72, 4.3}
		object_instance(r, .Ring, q, {1.6, 0, 0}, {0, 0, -1}, {0, 1.1, 0}, ORANGE)
		model_sphere(r, q+game.Vec3{0, 0.5, -0.5}, 0.7, 6, 10, PAPER)
		model_cube(r, q+game.Vec3{0, 0.5, 0}, {2.6, 0.55, 0.3}, {206, 116, 144, 255})
	}
	if b.phase == .Mark || b.phase == .Sweep {
		lane := b.lanes[b.pass]
		f := game.normalized(lane.b-lane.a)
		x := game.cross(game.Vec3{0, 1, 0}, f)
		q := game.boss_brush_position(b)
		if b.phase == .Mark { q.y += 1.2+min(1, b.timer)*2 }
		object_instance(r, .GCBrush, q, x*lane.width, {0, 1, 0}, f, rl.WHITE)
		// An articulated overhead hose stops above head height; it is trim.
		elbow := (p+q)*0.5+game.Vec3{0, 10, 0}
		model_beam(r, .Beam, p+game.Vec3{0, 6, 0}, elbow, 0.23, {39, 57, 63, 255})
		model_beam(r, .Beam, elbow, q+game.Vec3{0, 2.6, 0}, 0.18, {47, 74, 80, 255})
		r.objects.passes = WORLD_PASS
		for i in b.pass..<b.lane_count {
			strip := b.lanes[i]
			d := game.normalized(strip.b-strip.a)
			right := game.cross(d, game.Vec3{0, 1, 0})
			ink := ORANGE if i > b.pass else (RED if b.phase == .Sweep else rl.Color{255, 197, 83, 255})
			start := q if i == b.pass && b.phase == .Sweep else strip.a
			start.y = strip.a.y
			for side in ([2]f32{-1, 1}) { model_beam(r, .Beam, start+right*(side*strip.width*0.5), strip.b+right*(side*strip.width*0.5), 0.055, ink) }
			for segment in 0..<12 {
				point := strip.a+(strip.b-strip.a)*(f32(segment)+0.5)/12
				if game.dot(point-start, d) < 0 { continue }
				model_line(r, point-right*0.45-d*0.4, point+d*0.35, ink)
				model_line(r, point+right*0.45-d*0.4, point+d*0.35, ink)
			}
		}
	}
	r.objects.passes = WORLD_PASS
}

draw_anvil :: proc(r: ^Renderer, g: ^game.Render_Snapshot, time: f32) {
	a := g.anvil
	if a.phase == .Idle { return }
	r.objects.passes = WORLD_PASS
	if a.phase == .Warning || a.phase == .Falling {
		ring3(r, a.target+game.Vec3{0, 0.03, 0}, 1.3, ORANGE)
		for side in ([2]f32{-1, 1}) {
			model_line(r, a.target+game.Vec3{-0.6, 0.04, side*0.6}, a.target+game.Vec3{0.6, 0.04, -side*0.6}, ORANGE)
		}
	}
	r.objects.passes = WORLD_PASS|SHADOW_PASS
	scale := clamp(a.timer/0.5, 0.02, 1) if a.phase == .Rest else f32(1)
	object_instance(r, .PixelAnvil, a.position, {scale, 0, 0}, {0, scale, 0}, {0, 0, scale}, rl.WHITE)
	r.objects.passes = WORLD_PASS
}
