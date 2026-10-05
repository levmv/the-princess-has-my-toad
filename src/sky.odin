package main

import "core:math"
import rl "vendor:raylib"
import game "game"

sky_init :: proc(r: ^Renderer) {
	r.sky_shader = load_game_shader(#load("../assets/post.vs"), #load("../assets/sky.fs"))
	assert(rl.IsShaderValid(r.sky_shader))
	r.sky_forward_location = rl.GetShaderLocation(r.sky_shader, "skyForward")
	r.sky_right_location = rl.GetShaderLocation(r.sky_shader, "skyRight")
	r.sky_up_location = rl.GetShaderLocation(r.sky_shader, "skyUp")
	r.sky_scale_location = rl.GetShaderLocation(r.sky_shader, "skyScale")
	r.sky_refresh_location = rl.GetShaderLocation(r.sky_shader, "skyRefresh")
	width, height := 1024, 512
	pixels := make([]rl.Color, width*height)
	defer delete(pixels)
	for &pixel, i in pixels {
		x, y := f32(i%width)/f32(width), f32(i/width)/f32(height)
		horizon := math.exp(-abs(y-0.5)*8)
		veil := tile_noise(x, y, 8, 3718)*0.7+tile_noise(x, y, 32, 2893)*0.3
		veil = max(0, veil-0.38)*18
		pixel = {u8(4+horizon*9+veil), u8(7+horizon*14+veil*1.0), u8(15+horizon*19+veil*2.1), 255}
	}
	seed := u32(0x813A69)
	for _ in 0..<1500 {
		x := int(game.random_stream(&seed)*f32(width))
		y := int((math.asin(game.random_stream(&seed)*2-1)/math.PI+0.5)*f32(height))
		brightness := game.random_stream(&seed)
		brightness = 34+brightness*brightness*170
		warm := game.random_stream(&seed) < 0.14
		for dy in -1..=1 {
			for dx in -1..=1 {
				py := clamp(y+dy, 0, height-1)
				px := (x+dx+width)%width
				p := &pixels[py*width+px]
				value := brightness if dx == 0 && dy == 0 else brightness*0.055
				p.r = u8(min(255, f32(p.r)+value*(1 if warm else 0.7)))
				p.g = u8(min(255, f32(p.g)+value*0.85))
				p.b = u8(min(255, f32(p.b)+value*(0.7 if warm else 1)))
			}
		}
	}
	img := rl.Image{data = raw_data(pixels), width = i32(width), height = i32(height), mipmaps = 1, format = .UNCOMPRESSED_R8G8B8A8}
	r.sky_texture = rl.LoadTextureFromImage(img)
	rl.GenTextureMipmaps(&r.sky_texture)
	rl.SetTextureFilter(r.sky_texture, .TRILINEAR)
	rl.SetTextureWrap(r.sky_texture, .REPEAT)
}

draw_sky :: proc(r: ^Renderer, cam: game.Camera, time: f32 = 0, refresh: bool = false) {
	f := cam.forward
	right := game.normalized(game.cross(f, game.Vec3{0, 1, 0}))
	up := game.cross(right, f)
	w, h := r.target.texture.width, r.target.texture.height
	scale := game.Vec2{f32(w)/f32(h), 1}*math.tan(cam.fov*math.PI/360)
	rl.SetShaderValue(r.sky_shader, r.sky_forward_location, &f, .VEC3)
	rl.SetShaderValue(r.sky_shader, r.sky_right_location, &right, .VEC3)
	rl.SetShaderValue(r.sky_shader, r.sky_up_location, &up, .VEC3)
	rl.SetShaderValue(r.sky_shader, r.sky_scale_location, &scale, .VEC2)
	// A short discharge travels across the RAM sky. The CPU computes the
	// envelope once, and the shader skips all arc work during the quiet period.
	phase := math.mod(time, 11)
	pulse := f32(0)
	if refresh && phase < 1.2 { pulse = math.sin(phase/1.2*math.PI)*0.7 }
	charge := rl.Vector4{pulse, phase/1.2, math.floor(time/11)*0.173, 0}
	rl.SetShaderValue(r.sky_shader, r.sky_refresh_location, &charge, .VEC4)
	rl.BeginShaderMode(r.sky_shader)
	rl.DrawTexturePro(r.sky_texture, {0, 0, 1024, 512}, {0, 0, f32(w), f32(h)}, {}, 0, rl.WHITE)
	rl.EndShaderMode()
}
