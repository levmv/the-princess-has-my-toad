package main

import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "game"
import loc "locale"

INK :: rl.Color{9, 23, 29, 255}
PAPER :: rl.Color{226, 229, 216, 255}
MUTED :: rl.Color{126, 160, 160, 255}
MINT :: rl.Color{114, 246, 206, 255}
ORANGE :: rl.Color{255, 132, 72, 255}
RED :: rl.Color{255, 83, 91, 255}

Renderer :: struct {
	language: loc.Language,
	theatre: game.World,
	other_geometry: Geometry_Cache,
	corpses: [game.ENEMY_CAPACITY]Corpse_Cache,
	debug: Debug_Render,
	objects: Object_Renderer,
	hero: Hero_Renderer,
	scene, post, depth: rl.Shader,
	sky_shader: rl.Shader,
	sky_texture: rl.Texture2D,
	sky_forward_location, sky_right_location, sky_up_location, sky_scale_location: i32,
	sky_refresh_location: i32,
	target, shadow: rl.RenderTexture2D,
	grain, glow: rl.Texture2D,
	blast_fire, blast_smoke: rl.Texture2D,
	chunks: [dynamic]Render_Chunk,
	draw_order: []int,
	chunk_distance: []f32,
	near_first: bool,
	render_scale: f32,
	architecture_vertices, visible_world_chunks, visible_shadow_chunks: int,
	world_revision: u64,
	world_source: ^game.World,
	geometry_seed: u32,
	material_seed: u32,
	culling_enabled: bool,
	shadow_center: game.Vec3,
	shadow_extent: f32,
	material: rl.Material,
	light_vp: rl.Matrix,
	font, display, mono: rl.Font,
	logo: rl.Texture2D,
	eye_location, grain_location, resolution_location: i32,
	damage_location: i32,
	damage_flash: f32,
	shadow_location, light_vp_location, baked_location: i32,
	light_count_location, light_position_location, light_color_location: i32,
	width, height: i32,
}

renderer_init :: proc(r: ^Renderer, g: ^game.State) {
	for stage in 0..<5 { renderer_init_stage(r, g.world.seed, stage) }
	sync_world_mesh(r, g.world)
}

// Loading boundaries shared by native startup and the yielding browser loader.
renderer_init_stage :: proc(r: ^Renderer, world_seed: u32, stage: int) {
	switch stage {
	case 0:
	rlgl.SetClipPlanes(f64(game.CAMERA_NEAR), 250)
	r.scene = load_game_shader(#load("../assets/scene.vs"), #load("../assets/scene.fs"))
	r.post = load_game_shader(#load("../assets/post.vs"), #load("../assets/post.fs"))
	r.depth = load_game_shader(#load("../assets/scene.vs"), #load("../assets/shadow.fs"))
	assert(rl.IsShaderValid(r.scene) && rl.IsShaderValid(r.post) && rl.IsShaderValid(r.depth), "Shader compilation failed")
	r.eye_location = rl.GetShaderLocation(r.scene, "eye")
	r.grain_location = rl.GetShaderLocation(r.scene, "grain")
	r.resolution_location = rl.GetShaderLocation(r.post, "resolution")
	r.damage_location = rl.GetShaderLocation(r.post, "damageFlash")
	r.shadow_location = rl.GetShaderLocation(r.scene, "shadowMap")
	r.light_vp_location = rl.GetShaderLocation(r.scene, "lightVP")
	r.baked_location = rl.GetShaderLocation(r.scene, "bakedScene")
	r.light_count_location = rl.GetShaderLocation(r.scene, "lightCount")
	r.light_position_location = rl.GetShaderLocation(r.scene, "lightPosition[0]")
	r.light_color_location = rl.GetShaderLocation(r.scene, "lightColor[0]")
	assert(r.eye_location >= 0 && r.grain_location >= 0 && r.resolution_location >= 0, "Required shader uniforms are missing")
	assert(r.shadow_location >= 0 && r.light_vp_location >= 0 && r.baked_location >= 0 && r.light_count_location >= 0 && r.light_position_location >= 0 && r.light_color_location >= 0, "Lighting uniforms are missing")
	slot := i32(10)
	rl.SetShaderValue(r.scene, r.grain_location, &slot, .INT)
	slot = 11
	rl.SetShaderValue(r.scene, r.shadow_location, &slot, .INT)
	r.shadow = rl.LoadRenderTexture(2048, 2048)
	assert(rl.IsRenderTextureValid(r.shadow), "Shadow target allocation failed")
	rl.SetTextureFilter(r.shadow.texture, .POINT)
	r.material = rl.LoadMaterialDefault()
	r.material.shader = r.scene
	case 1:
	body :: #load("../assets/fonts/body.ttf")
	display :: #load("../assets/fonts/display.ttf")
	mono :: #load("../assets/fonts/mono.ttf")
	points: [166]rune
	n := 0
	for point in rune(32)..<127 { points[n] = point; n += 1 }
	for point in rune(0x410)..<0x450 { points[n] = point; n += 1 }
	for point in ([7]rune{0x401, 0x451, 0x2014, 0x2013, 0x2026, 0xab, 0xbb}) { points[n] = point; n += 1 }
	assert(n == len(points))
	r.font = rl.LoadFontFromMemory(".ttf", raw_data(body), i32(len(body)), 48, &points[0], i32(n))
	r.display = rl.LoadFontFromMemory(".ttf", raw_data(display), i32(len(display)), 128, &points[0], i32(n))
	r.mono = rl.LoadFontFromMemory(".ttf", raw_data(mono), i32(len(mono)), 32, &points[0], i32(n))
	rl.SetTextureFilter(r.font.texture, .BILINEAR)
	rl.SetTextureFilter(r.display.texture, .BILINEAR)
	rl.SetTextureFilter(r.mono.texture, .BILINEAR)
	logo :: #load("../assets/logo.png")
	logo_image := rl.LoadImageFromMemory(".png", raw_data(logo), i32(len(logo)))
	r.logo = rl.LoadTextureFromImage(logo_image)
	rl.UnloadImage(logo_image)
	rl.GenTextureMipmaps(&r.logo)
	rl.SetTextureFilter(r.logo, .TRILINEAR)
	case 2:
	generate_materials(r, world_seed)
	blast_textures_init(r)
	sky_init(r)
	r.material_seed = world_seed
	case 3:
	models_init(r)
	case 4:
	hero_init(r)
	theatre_init(&r.theatre, world_seed)
	r.culling_enabled, r.near_first = true, true
	}
}

renderer_destroy :: proc(r: ^Renderer) {
	game.world_destroy(&r.theatre)
	debug_destroy(&r.debug)
	rl.UnloadRenderTexture(r.target)
	rl.UnloadRenderTexture(r.shadow)
	models_destroy(r)
	hero_destroy(r)
	destroy_chunks(r)
	delete(r.chunks)
	r.chunks = nil
	swap_geometry(r)
	destroy_chunks(r)
	delete(r.chunks)
	// The material borrows the scene shader and raylib's default white texture.
	rl.MemFree(r.material.maps)
	rl.UnloadTexture(r.grain)
	rl.UnloadTexture(r.glow)
	rl.UnloadTexture(r.blast_fire)
	rl.UnloadTexture(r.blast_smoke)
	rl.UnloadShader(r.scene)
	rl.UnloadShader(r.post)
	rl.UnloadShader(r.depth)
	rl.UnloadShader(r.sky_shader)
	rl.UnloadTexture(r.sky_texture)
	rl.UnloadFont(r.font)
	rl.UnloadFont(r.display)
	rl.UnloadFont(r.mono)
	rl.UnloadTexture(r.logo)
}

fade :: proc(c: rl.Color, alpha: f32) -> rl.Color {
	result := c
	result.a = u8(clamp(alpha, 0, 1)*255)
	return result
}

line3 :: proc(r: ^Renderer, a, b: game.Vec3, radius: f32, color: rl.Color) {
	model_beam(r, .Beam, a, b, radius, color)
}

draw_architecture :: proc(r: ^Renderer) {
	baked := i32(1)
	rl.SetShaderValue(r.scene, r.baked_location, &baked, .INT)
	r.visible_world_chunks = draw_chunks(r, r.material, rlgl.GetMatrixProjection()*rlgl.GetMatrixModelview())
	baked = 0
	rl.SetShaderValue(r.scene, r.baked_location, &baked, .INT)
}

draw_vents :: proc(r: ^Renderer, g: ^game.Render_Snapshot, time: f32) {
	for v in g.world.vents {
		object_instance(r, .Vent, v.position+game.Vec3{0, 0.03, 0}, {v.radius, 0, 0}, {0, 0.10, 0}, {0, 0, v.radius}, {30, 83, 83, 255})
		if !game.vent_running(v, g.lift_started) { ring3(r, v.position+game.Vec3{0, 0.15, 0}, v.radius, MUTED); continue }
		ring3(r, v.position+game.Vec3{0, 0.15, 0}, v.radius, MINT)
		ring3(r, v.position+game.Vec3{0, 0.17, 0}, v.radius*0.83, MINT)
		for i in 0..<16 {
			a := f32(i)*2.39996+time*0.2
			y := math.mod(f32(i)*1.07+time*3, v.top-v.position.y)
			p := v.position+game.Vec3{math.cos(a)*v.radius*0.7, y, math.sin(a)*v.radius*0.7}
			model_line(r, p, p+game.Vec3{0, 0.8, 0}, fade(MINT, 0.15+0.45*(1-y/(v.top-v.position.y))))
		}
	}
}

draw_diamond :: proc(r: ^Renderer, p: game.Vec3, radius, time: f32, color: rl.Color) {
	for i in 0..<4 {
		a := f32(i)*math.PI*0.5+time
		b := f32(i+1)*math.PI*0.5+time
		p1 := p+game.Vec3{math.cos(a)*radius, 0, math.sin(a)*radius}
		p2 := p+game.Vec3{math.cos(b)*radius, 0, math.sin(b)*radius}
		top, bottom := p+game.Vec3{0, radius*1.8, 0}, p-game.Vec3{0, radius*1.8, 0}
		lit_triangle(r, top, p2, p1, color)
		lit_triangle(r, bottom, p1, p2, color)
	}
}

draw_actors :: proc(r: ^Renderer, g: ^game.Render_Snapshot, time: f32, camera: game.Camera) {
	r.objects.passes = WORLD_PASS|SHADOW_PASS
	for e, i in g.enemies[:g.enemy_count] {
		if e.position.y < game.VOID_HEIGHT { continue }
		if e.phase == .Dormant { continue }
		if e.health <= 0 {
			if e.phase == .Recover { draw_enemy_death(r, e, time, &r.corpses[i]) }
			continue
		}
		draw_enemy(r, e, time)
	}
	r.objects.passes = SHADOW_PASS
	if !camera.scoped && game.length(camera.position-g.player.position-game.Vec3{0, game.EYE_HEIGHT, 0}) > 0.65 { r.objects.passes |= WORLD_PASS }
	prepare_hero(r, g, time, camera)
	r.objects.passes = WORLD_PASS
}

prepare_objects :: proc(r: ^Renderer, g: ^game.Render_Snapshot, time: f32, camera: game.Camera) {
	draw_vents(r, g, time)
	draw_mission_objects(r, g, time)
	for core, i in g.cores[:g.core_count] {
		if core.collected { continue }
		p := core.position+game.Vec3{0, math.sin(time*2+f32(i))*0.12, 0}
		draw_diamond(r, p, 0.37, time, MINT)
		ring3(r, core.position-game.Vec3{0, 0.77, 0}, 1.0, MINT)
		model_line(r, p+game.Vec3{0, 0.8, 0}, p+game.Vec3{0, 7, 0}, fade(MINT, 0.4))
	}
	gate_color := MINT if g.exit_open else MUTED
	for i in 0..<2 {
		x := g.world.exit.x+f32(i*2-1)*2.3
		model_cube(r, {x, g.world.exit.y+2.1, g.world.exit.z}, {0.5, 4.2, 0.8}, PAPER)
		model_cube(r, {x, g.world.exit.y+2.1, g.world.exit.z+0.43}, {0.14, 3.8, 0.04}, gate_color, SURFACE_LIGHT)
	}
	model_cube(r, g.world.exit+game.Vec3{0, 4.2, 0}, {5.1, 0.5, 0.8}, PAPER)
	if g.exit_open {
		for i in 0..<6 {
			y := math.mod(time*2+f32(i)*0.7, 4)
			model_line(r, g.world.exit+game.Vec3{-2, y, 0}, g.world.exit+game.Vec3{2, y, 0}, fade(MINT, 0.45))
		}
	}
	draw_boss(r, g, time)
	draw_anvil(r, g, time)
	draw_actors(r, g, time, camera)
	draw_floor_hazards(r, g, time)
	draw_weapons_and_pickups(r, g, time)
	draw_gibs(r, g)
	r.objects.passes = WORLD_PASS
	for bullet in g.projectiles {
		if bullet.life <= 0 { continue }
		draw_enemy_projectile(r, bullet)
	}
	for p in g.particles {
		if p.life <= 0 { continue }
		if p.kind >= 5 { continue }
		color := ORANGE if p.kind == 0 else (rl.Color{255, 215, 148, 255} if p.kind == 2 else MINT)
		if p.kind == 3 { color = {151, 20, 39, 255} }
		if p.kind == 4 { color = {192, 180, 142, 255} }
		model_cube(r, p.position, {p.size, p.size, p.size}, fade(color, p.life/p.max_life), SURFACE_LIGHT if p.kind < 3 else (SURFACE_BONE if p.kind == 4 else SURFACE_SKIN))
	}
}

resize_render_target :: proc(r: ^Renderer) {
	w, h := rl.GetScreenWidth(), rl.GetScreenHeight()
	scale := clamp(r.render_scale, 0.5, 1) if r.render_scale > 0 else f32(1)
	sw, sh := max(1, i32(f32(w)*scale+0.5)), max(1, i32(f32(h)*scale+0.5))
	if sw != r.target.texture.width || sh != r.target.texture.height {
		if r.target.id != 0 { rl.UnloadRenderTexture(r.target) }
		r.target = rl.LoadRenderTexture(sw, sh)
		assert(rl.IsRenderTextureValid(r.target), "Scene target allocation failed")
		rl.SetTextureFilter(r.target.texture, .BILINEAR)
	}
	r.width, r.height = w, h
}

render_world_pass :: proc(r: ^Renderer, g: ^game.Render_Snapshot, camera: game.Camera, time: f32) {
	w, h := r.target.texture.width, r.target.texture.height
	rl.BeginTextureMode(r.target)
	rl.ClearBackground({12, 22, 33, 255})
	draw_sky(r, camera, time, g.world.kind == .RAM)
	rlgl.SetClipPlanes(f64(game.camera_near_clip(camera.fov, f32(w)/f32(h))), 250)
	rl.BeginMode3D({camera.position, camera.target, {0, 1, 0}, camera.fov, .PERSPECTIVE})
	// Dedicated slots stay bound for both direct mesh draws and raylib's batches.
	rlgl.ActiveTextureSlot(10)
	rlgl.EnableTexture(r.grain.id)
	rlgl.ActiveTextureSlot(11)
	rlgl.EnableTexture(r.shadow.texture.id)
	rlgl.ActiveTextureSlot(0)
	rl.BeginShaderMode(r.scene)
	draw_architecture(r)
	draw_instances(r, false)
	hero_draw(r, false)
	rl.EndShaderMode()
	rlgl.ActiveTextureSlot(10)
	rlgl.DisableTexture()
	rlgl.ActiveTextureSlot(11)
	rlgl.DisableTexture()
	rlgl.ActiveTextureSlot(0)
	draw_light_glows(r, g, camera)
	draw_blast_clouds(r, g, camera)
	draw_debug_world(r, g)
	rl.EndMode3D()
	rlgl.SetClipPlanes(f64(game.CAMERA_NEAR), 250)
	rl.EndTextureMode()
}

render_post_pass :: proc(r: ^Renderer, destination: rl.Rectangle = {}) {
	w, h := r.target.texture.width, r.target.texture.height
	bounds := destination
	if bounds.width == 0 { bounds = {0, 0, f32(r.width), f32(r.height)} }
	rl.BeginShaderMode(r.post)
	resolution := rl.Vector2{f32(w), f32(h)}
	rl.SetShaderValue(r.post, r.resolution_location, &resolution, .VEC2)
	rl.SetShaderValue(r.post, r.damage_location, &r.damage_flash, .FLOAT)
	rl.DrawTexturePro(r.target.texture, {0, 0, f32(w), -f32(h)}, bounds, {}, 0, rl.WHITE)
	rl.EndShaderMode()
}

prepare_frame :: proc(r: ^Renderer, g: ^game.Render_Snapshot, camera: game.Camera, time: f32) {
	r.damage_flash = clamp(g.player.hurt_time/0.28, 0, 1)*(0.45+0.55*g.player.hurt_strength)
	sync_world_mesh(r, g.world)
	resize_render_target(r)
	order_chunks(r, camera.position)
	r.objects.count = 0
	r.objects.ranges = {}
	r.objects.passes = WORLD_PASS
	prepare_objects(r, g, time, camera)
	upload_instances(r)
}

render_scene :: proc(r: ^Renderer, g: ^game.Render_Snapshot, camera: game.Camera, time: f32) {
	prepare_frame(r, g, camera, time)
	render_shadow(r, g, camera, time)
	update_lighting(r, g, camera)
	render_world_pass(r, g, camera, time)
	render_post_pass(r)
}
