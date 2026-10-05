package game

import "core:math"

DECOR_MINT :: [3]u8{114, 246, 206}
DECOR_ORANGE :: [3]u8{255, 132, 72}

add_decor_beam :: proc(w: ^World, a, b: Vec3, radius_a, radius_b: f32, color: [3]u8, material: f32 = 0, sides: int = 6) {
	append(&w.decor_beams, Decor_Beam{a, b, radius_a, radius_b, color, material, sides})
}

// Level authoring owns placement. The renderer only consumes this description.
build_decoration :: proc(w: ^World) {
	clear(&w.decor_blocks)
	clear(&w.decor_beams)
	seed := w.seed+0xC84631
	if seed == 0 { seed = 1 }
	for i in 0..<28 {
		a := f32(i)*2.39996+(random_stream(&seed)-0.5)*0.2
		radius := 58+random_stream(&seed)*28
		height := 18+random_stream(&seed)*25
		b := Block{center = {math.cos(a)*radius, -24+height*0.5, -13+math.sin(a)*radius}, size = {3+random_stream(&seed)*4, height, 3+random_stream(&seed)*4}}
		bevel_block(&b, min(b.size.x, b.size.z)*0.28, 0.3)
		append(&w.decor_blocks, Decor_Block{b, {35, 56, 73}, {96, 121, 128}})
	}
	for block, i in w.blocks[:min(11, len(w.blocks))] {
		y := block.center.y+block.size.y*0.5
		// Recessed edge rails stop before the bevels; broad decks stay uncluttered.
		for side in 0..<2 {
			sign := f32(side*2-1)
			a := block.center+Vec3{-block.size.x*0.31, block.size.y*0.5-0.40, sign*(block.size.z*0.5+0.015)}
			b := a+Vec3{block.size.x*0.62, 0, 0}
			add_decor_beam(w, a, b, 0.06, 0.06, DECOR_MINT if block.style == 2 else DECOR_ORANGE, 3, 4)
		}
		if i < 5 {
			add_decor_beam(w, {block.center.x, -23, block.center.z}, {block.center.x, y-block.size.y, block.center.z}, 1.4, min(block.size.x, block.size.z)*0.22, {48, 67, 81}, 0, 8)
			// A pair of tapered buttresses breaks up the flat underside silhouette.
			for side in 0..<2 {
				sign := f32(side*2-1)
				add_decor_beam(w, {block.center.x, y-6, block.center.z}, {block.center.x+sign*block.size.x*0.32, y-1.2, block.center.z}, 0.48, 0.30, {83, 98, 108})
			}
		}
	}
	for visual in w.decor_blocks {
		b := visual.shape
		add_decor_beam(w, b.center+Vec3{0, -b.size.y*0.42, b.size.z*0.5+0.03}, b.center+Vec3{0, b.size.y*0.4, b.size.z*0.5+0.03}, 0.035, 0.035, {55, 151, 170}, 3, 4)
	}
	profile := TUNNEL_PROFILE
	for rib in 0..<5 {
		z := TUNNEL_Z_FAR+f32(rib)*3
		for i in 0..<len(profile)-1 {
			a := Vec3{profile[i].x+TUNNEL_X, profile[i].y, z}
			b := Vec3{profile[i+1].x+TUNNEL_X, profile[i+1].y, z}
			add_decor_beam(w, a, b, 0.105, 0.105, {53, 70, 85}, 0, 6)
		}
	}
	for side in 0..<2 {
		x := TUNNEL_X+f32(side*2-1)*2.55
		add_decor_beam(w, {x, 0.45, TUNNEL_Z_FAR}, {x, 0.45, TUNNEL_Z_NEAR}, 0.045, 0.045, DECOR_MINT, 3, 4)
		add_decor_beam(w, {x, 4.55, TUNNEL_Z_FAR}, {x, 4.55, TUNNEL_Z_NEAR}, 0.07, 0.07, {132, 94, 57}, 0, 6)
	}
	lamps := w.lamps
	for p in lamps {
		add_decor_beam(w, p-Vec3{0.6, -0.08, 0}, p+Vec3{0.6, 0.08, 0}, 0.13, 0.13, {48, 61, 69}, 0, 6)
		add_decor_beam(w, p-Vec3{0.48, 0, 0}, p+Vec3{0.48, 0, 0}, 0.075, 0.075, {255, 200, 127}, 3, 6)
	}
	// Massive, segmented arches beyond the exit replace the wire-only backdrop.
	for arch in 0..<2 {
		center := Vec3{0, 17, -47-f32(arch)*3}
		radius := f32(16)+f32(arch)*2.5
		for i in 0..<32 {
			a := f32(i)*math.PI*1.65/32-0.32
			b := f32(i+1)*math.PI*1.65/32-0.32
			p := center+Vec3{math.cos(a)*radius, math.sin(a)*radius, 0}
			q := center+Vec3{math.cos(b)*radius, math.sin(b)*radius, 0}
			add_decor_beam(w, p, q, 0.44, 0.44, {85, 106, 116}, 0, 6)
			if i%4 == 0 { add_decor_beam(w, p, p+Vec3{0, 0, 0.6}, 0.47, 0.40, DECOR_ORANGE, 3, 6) }
		}
	}
}
