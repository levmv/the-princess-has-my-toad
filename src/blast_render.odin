package main

import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "game"

blast_textures_init :: proc(r: ^Renderer) {
	pixels: [128*128]rl.Color
	for fire in ([2]bool{false, true}) {
		for &pixel, i in pixels {
			x, y := f32(i%128)/127, f32(i/128)/127
			q := game.Vec2{x*2-1, y*2-1}
			distance := math.sqrt(q.x*q.x+q.y*q.y)
			coarse := tile_noise(x, y, 7, 35141)
			noise := coarse*0.65+tile_noise(x, y, 22, 97531)*0.25+tile_noise(x, y, 64, 717)*0.10
			alpha := clamp((0.86-distance+(coarse-0.5)*0.38)*5, 0, 1)*(0.45+noise*0.55)
			shade := clamp(noise*0.75-y*0.16+0.2, 0, 1)
			pixel = {u8(55+shade*78), u8(52+shade*69), u8(46+shade*60), u8(alpha*180)}
			if fire {
				heat := clamp((1-distance)*0.60+noise*0.55, 0, 1)
				pixel = {u8(178+heat*77), u8(30+heat*175), u8(8+math.pow(heat, 6)*165), u8(alpha*230)}
			}
		}
		img := rl.Image{data = &pixels[0], width = 128, height = 128, mipmaps = 1, format = .UNCOMPRESSED_R8G8B8A8}
		texture := rl.LoadTextureFromImage(img)
		rl.GenTextureMipmaps(&texture)
		rl.SetTextureFilter(texture, .TRILINEAR)
		if fire { r.blast_fire = texture } else { r.blast_smoke = texture }
	}
}

// Sort the small bounded particle pool, draw with depth tests but without depth
// writes. Clouds cannot hide later clouds with opaque polygon silhouettes.
draw_blast_clouds :: proc(r: ^Renderer, g: ^game.Render_Snapshot, camera: game.Camera) {
	order: [game.PARTICLE_CAPACITY]int
	distances: [game.PARTICLE_CAPACITY]f32
	count := 0
	for p, i in g.particles {
		if p.life <= 0 || p.kind < 5 { continue }
		d := game.dot(p.position-camera.position, p.position-camera.position)
		at := count
		for at > 0 && distances[at-1] < d { order[at], distances[at] = order[at-1], distances[at-1]; at -= 1 }
		order[at], distances[at] = i, d
		count += 1
	}
	if count == 0 { return }
	cam := rl.Camera3D{camera.position, camera.target, {0, 1, 0}, camera.fov, .PERSPECTIVE}
	rlgl.DisableDepthMask()
	for i in order[:count] {
		p := g.particles[i]
		age := 1-p.life/p.max_life
		size := p.size*2*(1+age*2.0)
		texture := r.blast_fire if p.kind == 6 else r.blast_smoke
		alpha := (1-age)*0.9 if p.kind == 6 else min(1, p.life*2.5)*0.74
		rl.DrawBillboardPro(cam, texture, {0, 0, 128, 128}, p.position, {0, 1, 0}, {size, size}, {size*0.5, size*0.5}, f32(i)*137+age*30, fade(rl.WHITE, alpha))
	}
	rlgl.DrawRenderBatchActive()
	rlgl.EnableDepthMask()
}
