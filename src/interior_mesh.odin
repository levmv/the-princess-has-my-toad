package main

import "core:math"
import rl "vendor:raylib"
import game "game"

// Surface dressing is baked into the existing culled world chunks. It never
// changes collision, navigation, the gameplay random stream or saved sectors.
// Shallow covers sit against the wall; frames stop outside the door openings.
interior_plate :: proc(m: ^Mesh_Builder, p, right, normal: game.Vec3, width, height, depth: f32, color: rl.Color, surface: f32 = SURFACE_IRON) {
	shape := game.Block{center = p, size = {abs(right.x)*width+abs(normal.x)*depth, height, abs(right.z)*width+abs(normal.z)*depth}}
	game.bevel_block(&shape, min(0.035, depth*0.3), min(0.08, height*0.2))
	mesh_block(m, nil, shape, color, color, surface, 10)
}

interior_clear :: proc(s: game.Section_Recipe, side: game.Door_Side, from, to, bottom, top: f32) -> bool {
	for door_index in 0..<s.door_count {
		door := s.doors[door_index]
		if door.side != side { continue }
		if to > door.offset-door.width*0.5-0.35 && from < door.offset+door.width*0.5+0.35 && top > door.bottom-0.2 && bottom < door.bottom+door.height+0.3 { return false }
	}
	return true
}

interior_service_panel :: proc(m: ^Mesh_Builder, p, right, normal: game.Vec3, color: rl.Color, variant: int) {
	up := game.Vec3{0, 1, 0}
	interior_plate(m, p, right, normal, 2.3, 1.26, 0.035, {33, 38, 39, 255})
	interior_plate(m, p+normal*0.026, right, normal, 2.16, 1.12, 0.02, color)
	for side in ([2]f32{-1, 1}) {
		for y in ([2]f32{-0.47, 0.47}) {
			q := p+right*(side*0.98)+up*y+normal*0.044
			mesh_beam(m, q-normal*0.012, q+normal*0.008, 0.045, 0.033, {157, 149, 125, 255}, SURFACE_IRON, 6)
		}
	}
	if variant == 0 {
		// Recessed slats and projecting upper lips read as depth from a distance.
		for i in 0..<5 {
			q := p+up*(-0.36+f32(i)*0.18)+normal*0.044
			interior_plate(m, q, right, normal, 1.65, 0.095, 0.008, {23, 27, 29, 255})
			mesh_beam(m, q-right*0.83+up*0.052, q+right*0.83+up*0.052, 0.027, 0.027, color, SURFACE_IRON, 4)
		}
	} else if variant == 1 {
		q := p-right*0.3+normal*0.045
		interior_plate(m, q, right, normal, 1.1, 0.76, 0.007, {35, 40, 37, 255})
		for i in 0..<12 {
			a, b := f32(i)*math.PI/6, f32(i+1)*math.PI/6
			mesh_beam(m, q+right*(math.cos(a)*0.31)+up*(math.sin(a)*0.31), q+right*(math.cos(b)*0.31)+up*(math.sin(b)*0.31), 0.032, 0.032, {113, 103, 85, 255}, SURFACE_IRON, 5)
		}
		for y in ([3]f32{-0.19, 0, 0.19}) {
			mesh_beam(m, q-right*0.36+up*y+normal*0.015, q+right*0.36+up*y+normal*0.015, 0.022, 0.022, {102, 101, 87, 255}, SURFACE_IRON, 4)
		}
		interior_plate(m, p+right*0.64+normal*0.046, right, normal, 0.17, 0.37, 0.012, {154, 117, 71, 255})
	} else {
		// A crooked replacement cover, retaining straps and a faded paint mark.
		for side in ([2]f32{-1, 1}) {
			mesh_beam(m, p+right*(side*0.58)-up*0.49+normal*0.046, p+right*(side*0.58+0.07)+up*0.49+normal*0.046, 0.055, 0.055, {66, 66, 61, 255}, SURFACE_IRON, 4)
		}
		interior_plate(m, p+normal*0.047, right, normal, 0.53, 0.20, 0.004, {155, 133, 88, 255}, SURFACE_PAINT)
	}
}

bake_interior_details :: proc(m: ^Mesh_Builder, w: ^game.World, first: int = 0, section_count: int = -1) {
	if w.kind != .RAM { return }
	up := game.Vec3{0, 1, 0}
	end := w.sector.count if section_count < 0 else min(w.sector.count, first+section_count)
	for s in w.sector.sections[first:end] {
		if game.exterior_section(s.role) { continue }
		theme := game.ram_theme(s)
		panel := rl.Color{100, 105, 92, 255}
		trim := rl.Color{64, 71, 70, 255}
		switch theme {
		case .Board: panel = {63, 85, 68, 255}; trim = {84, 88, 69, 255}
		case .Copper: panel = {128, 89, 58, 255}; trim = {74, 57, 46, 255}
		case .Bridge: panel = {82, 100, 111, 255}; trim = {50, 60, 68, 255}
		case .Porcelain: panel = {154, 151, 130, 255}; trim = {74, 82, 79, 255}
		case .Machine: panel = {103, 89, 71, 255}; trim = {51, 53, 52, 255}
		case .Quarantine: panel = {108, 87, 99, 255}; trim = {75, 65, 70, 255}
		}
		for side in game.Door_Side {
			normal := game.Vec3{0, 0, 1 if side == .North else -1}
			x_wall := side == .West || side == .East
			if x_wall { normal = {1 if side == .West else -1, 0, 0} }
			right := game.cross(up, normal)
			along := game.Vec3{0, 0, 1} if x_wall else game.Vec3{1, 0, 0}
			half := (s.depth if x_wall else s.width)*0.5
			p := s.origin-normal*((s.width if x_wall else s.depth)*0.5-0.6)
			height := s.height
			if s.role == .Capacitor_Garden && (side == .South || side == .East) { height = min(height, 7.2) }
			count := max(1, int((half*2-1)/7.5))
			pitch := (half*2-1)/f32(count)
			for i in 0..<count {
				offset := -half+0.5+(f32(i)+0.5)*pitch
				q := p+along*offset
				if interior_clear(s, side, offset-pitch*0.5, offset+pitch*0.5, 0, 1.15) {
					interior_plate(m, q+up*0.49+normal*0.015, right, normal, pitch-0.045, 0.94, 0.025, trim)
					mesh_beam(m, q-right*(pitch*0.5)+up*1.01+normal*0.028, q+right*(pitch*0.5)+up*1.01+normal*0.028, 0.028, 0.028, panel, SURFACE_IRON, 4)
				}
				if interior_clear(s, side, offset-1.3, offset+1.3, 1.6, 3.1) {
					interior_service_panel(m, q+up*2.30+normal*0.02, right, normal, panel, (i+int(side)+int(s.id))%3)
				}
				// Thin structural seams form broad bays rather than a square grid.
				if height > 5 && interior_clear(s, side, offset-0.2, offset+0.2, 3.3, height) {
					interior_plate(m, q+up*((height+3.3)*0.5)+normal*0.018, right, normal, 0.11, height-3.3, 0.025, trim)
					mesh_beam(m, q+up*(height-0.35)+normal*0.02, q+right*(pitch*0.40)+up*(height-1.3)+normal*0.02, 0.045, 0.045, panel, SURFACE_IRON, 5)
				}
			}
			for door_index in 0..<s.door_count {
				door := s.doors[door_index]
				if door.side != side { continue }
				q := p+along*door.offset+up*door.bottom
				for sign in ([2]f32{-1, 1}) {
					v := q+right*(sign*(door.width*0.5+0.14))
					interior_plate(m, v+up*(door.height*0.5)+normal*0.028, right, normal, 0.23, door.height, 0.05, trim)
					for y in ([2]f32{0.35, door.height-0.35}) {
						interior_plate(m, v+up*y+normal*0.055, right, normal, 0.13, 0.15, 0.01, panel)
					}
				}
				interior_plate(m, q+up*(door.height+0.16)+normal*0.025, right, normal, door.width+0.5, 0.27, 0.04, panel)
			}
		}
	}
}
