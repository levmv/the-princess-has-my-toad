package main

import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "game"

noise_hash :: proc(x, y: int, seed: u32) -> f32 {
	h := u32(x)*0x45D9F3B+u32(y)*0x27D4EB2D+seed
	h = (h ~ (h>>16))*0x45D9F3B
	h ~= h>>16
	return f32(h & 65535)/65535
}

tile_noise :: proc(x, y: f32, cells: int, seed: u32, rows: int = 0) -> f32 {
	rows := rows if rows > 0 else cells
	px, py := x*f32(cells), y*f32(rows)
	ix, iy := int(px), int(py)
	fx, fy := px-f32(ix), py-f32(iy)
	u, v := fx*fx*(3-2*fx), fy*fy*(3-2*fy)
	a, b := noise_hash(ix%cells, iy%rows, seed), noise_hash((ix+1)%cells, iy%rows, seed)
	c, d := noise_hash(ix%cells, (iy+1)%rows, seed), noise_hash((ix+1)%cells, (iy+1)%rows, seed)
	return (a+(b-a)*u)*(1-v)+(c+(d-c)*u)*v
}

generate_materials :: proc(r: ^Renderer, seed: u32) {
	pixels: [256*256]rl.Color
	for &pixel, i in pixels {
		x, y := f32(i%256)/256, f32(i/256)/256
		coarse := tile_noise(x, y, 4, seed)*0.56+tile_noise(x, y, 16, seed+91)*0.29+tile_noise(x, y, 64, seed+317)*0.15
		fine := tile_noise(x, y, 64, seed+47)*0.72+noise_hash(i%256, i/256, seed+1453)*0.28
		// Both coordinates wrap: mipmaps cannot expose seams in triplanar wear.
		brush := tile_noise(x, y, 64, seed+761, 8)*0.65+tile_noise(x, y, 32, seed+723)*0.35
		corrosion := tile_noise(x, y, 8, seed+851)*0.7+tile_noise(x, y, 32, seed+972)*0.3
		pixel = {u8(coarse*255), u8(fine*255), u8(brush*255), u8(corrosion*255)}
	}
	img := rl.Image{data = &pixels[0], width = 256, height = 256, mipmaps = 1, format = .UNCOMPRESSED_R8G8B8A8}
	r.grain = rl.LoadTextureFromImage(img)
	rl.GenTextureMipmaps(&r.grain)
	rl.SetTextureFilter(r.grain, .TRILINEAR)
	rl.SetTextureWrap(r.grain, .REPEAT)
	glow: [64*64]rl.Color
	for &pixel, i in glow {
		x, y := (f32(i%64)-31.5)/31.5, (f32(i/64)-31.5)/31.5
		a := max(0, 1-math.sqrt(x*x+y*y))
		pixel = {255, 255, 255, u8(a*a*a*255)}
	}
	img = rl.Image{data = &glow[0], width = 64, height = 64, mipmaps = 1, format = .UNCOMPRESSED_R8G8B8A8}
	r.glow = rl.LoadTextureFromImage(img)
	rl.SetTextureFilter(r.glow, .BILINEAR)
}

Light_Set :: struct {
	positions, colors: [12][4]f32,
	priority: [12]f32,
	count: i32,
}

include_light :: proc(lights: ^Light_Set, eye, position, color: game.Vec3, radius, strength: f32) {
	score := strength*radius/max(2, game.length(position-eye))
	index := int(lights.count)
	if index == len(lights.positions) {
		index = 0
		for i in 1..<len(lights.positions) { if lights.priority[i] < lights.priority[index] { index = i } }
		if score <= lights.priority[index] { return }
	} else { lights.count += 1 }
	lights.positions[index] = {position.x, position.y, position.z, radius}
	lights.colors[index] = {color.x, color.y, color.z, strength}
	lights.priority[index] = score
}

// Coloured lamps still identify the districts, with a broad neutral component
// so bone, copper and cloth keep their own colours beneath a bright fixture.
lamp_radiance :: proc(w: ^game.World, p: game.Vec3) -> game.Vec3 {
 return game.ram_lamp_color(w, p)*0.55+game.Vec3{0.98, 0.91, 0.78}*0.45
}

update_lighting :: proc(r: ^Renderer, g: ^game.Render_Snapshot, camera: game.Camera) {
	lights: Light_Set
	lamps := g.world.lamps
	for p in lamps { include_light(&lights, camera.position, p, lamp_radiance(g.world, p), 11, 5.0) }
	for vent in g.world.vents {
		if game.vent_running(vent, g.lift_started) { include_light(&lights, camera.position, vent.position+game.Vec3{0, 0.8, 0}, {0.16, 0.9, 0.72}, 5.5, 1.1) }
	}
	if g.world.sector.mechanism == .Shot_Lift {
		include_light(&lights, camera.position, g.world.lift.button, {0.15, 1, 0.65} if g.lift_started else game.Vec3{1, 0.4, 0.08}, 4, 2)
	}
	for e in g.enemies[:g.enemy_count] {
		if e.health > 0 && e.phase == .Windup { include_light(&lights, camera.position, e.position, {1, 0.18, 0.1}, 2.6, 1.5) }
	}
	if g.boss.id != 0 && game.boss_open(g.boss) {
		include_light(&lights, camera.position, game.boss_core(g.world)+game.Vec3{0, 0, 0.4}, {1, 0.5, 0.12}, 9, 5)
	}
	if g.boss.phase == .Sweep { include_light(&lights, camera.position, game.boss_brush_position(g.boss)+game.Vec3{0, 1, 0}, {1, 0.22, 0.06}, 5, 3) }
	for flash in g.flashes {
		if flash.life <= 0 { continue }
		decay := flash.life/flash.max_life
		include_light(&lights, camera.position, flash.position, flash.color, flash.radius, flash.strength*decay*decay)
	}
	for bullet in g.projectiles {
		if bullet.life <= 0 { continue }
		color := game.Vec3{1, 0.35, 0.06}
		if bullet.source == .Nanny { color = {0.2, 0.85, 0.5} }
		if bullet.source == .GC { color = {0.65, 0.3, 1} }
		include_light(&lights, camera.position, bullet.position, color, 2.3, 1.6)
	}
	for h in g.hazards {
		if h.life > 0 { include_light(&lights, camera.position, h.position+game.Vec3{0, 0.25, 0}, {1, 0.34, 0.04}, h.radius+1, min(1, h.life)*1.5) }
	}
	for fragment in g.fragments {
		if fragment.life > 0 { include_light(&lights, camera.position, fragment.position, {0.9, 0.66, 0.1}, 3, 2) }
	}
	rl.SetShaderValue(r.scene, r.light_count_location, &lights.count, .INT)
	rl.SetShaderValueV(r.scene, r.light_position_location, &lights.positions[0], .VEC4, lights.count)
	rl.SetShaderValueV(r.scene, r.light_color_location, &lights.colors[0], .VEC4, lights.count)
	eye := camera.position
	rl.SetShaderValue(r.scene, r.eye_location, &eye, .VEC3)
	rl.SetShaderValueMatrix(r.scene, r.light_vp_location, r.light_vp)
}

render_shadow :: proc(r: ^Renderer, g: ^game.Render_Snapshot, camera: game.Camera, time: f32) {
	direction := game.normalized(game.Vec3{-0.45, 0.8, 0.35})
	target := r.shadow_center
	extent := r.shadow_extent
	if g.world.kind == .RAM {
		// Long sectors retain local shadow resolution instead of stretching one
		// map across the entire route. Snap in light space to avoid shimmering.
		extent = 112
		target = g.player.position+game.normalized(game.Vec3{camera.forward.x, 0, camera.forward.z})*18+game.Vec3{0, 4, 0}
		u := game.normalized(game.cross(direction, game.Vec3{0, 1, 0}))
		v := game.cross(u, direction)
		texel := extent/2048
		axes := [2]game.Vec3{u, v}
		for axis in axes {
			coordinate := game.dot(target, axis)
			target += axis*(math.round(coordinate/texel)*texel-coordinate)
		}
	}
	light_camera := rl.Camera3D{target+direction*(extent*0.8), target, {0, 1, 0}, extent, .ORTHOGRAPHIC}
	rl.BeginTextureMode(r.shadow)
	rl.ClearBackground(rl.WHITE)
	rlgl.SetClipPlanes(0.1, f64(max(250, extent*2+64)))
	rl.BeginMode3D(light_camera)
	r.light_vp = rlgl.GetMatrixProjection()*rlgl.GetMatrixModelview()
	rl.BeginShaderMode(r.depth)
	material := r.material
	material.shader = r.depth
	r.visible_shadow_chunks = draw_chunks(r, material, r.light_vp)
	draw_instances(r, true)
	hero_draw(r, true)
	rl.EndShaderMode()
	rl.EndMode3D()
	rl.EndTextureMode()
	rlgl.SetClipPlanes(f64(game.CAMERA_NEAR), 250)
}

draw_light_glows :: proc(r: ^Renderer, g: ^game.Render_Snapshot, camera: game.Camera) {
	cam := rl.Camera3D{camera.position, camera.target, {0, 1, 0}, camera.fov, .PERSPECTIVE}
	rl.BeginBlendMode(.ADDITIVE)
	rlgl.DisableDepthMask()
	lamps := g.world.lamps
	for p in lamps {
		color := lamp_radiance(g.world, p)
		rl.DrawBillboard(cam, r.glow, p, 1.4, {u8(color.x*255), u8(color.y*255), u8(color.z*255), 110})
	}
	for flash in g.flashes {
		if flash.life <= 0 || flash.radius < 8 { continue }
		t := flash.life/flash.max_life
		size := 0.5+(1-t)*5
		rl.DrawBillboard(cam, r.glow, flash.position, size, fade({255, 134, 42, 255}, t*0.9))
		rl.DrawBillboard(cam, r.glow, flash.position, size*0.4, fade({255, 237, 174, 255}, t))
	}
	rlgl.DrawRenderBatchActive()
	rlgl.EnableDepthMask()
	rl.EndBlendMode()
}
