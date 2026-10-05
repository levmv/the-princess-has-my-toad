package render_bench

import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:slice"
import gl "vendor:OpenGL"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import app "../../src"
import game "../../src/game"

main :: proc() {
	width, height := 1280, 800
	if len(os.args) >= 3 {
		w, wok := strconv.parse_int(os.args[1])
		h, hok := strconv.parse_int(os.args[2])
		assert(wok && hok && w > 0 && h > 0)
		width, height = w, h
	}
	scene := "overview"
	if len(os.args) > 3 { scene = os.args[3] }
	hero_view := scene == "hero" || scene == "hero-run" || scene == "hero-air" || scene == "hero-land" || scene == "hero-glide" || scene == "hero-back" || scene == "hero-top"
	ram_view := scene == "ram" || scene == "ram-bus" || scene == "ram-junction" || scene == "ram-lift" || scene == "ram-upper" || scene == "enemy" || scene == "ram-corridor" || scene == "ram-court" || scene == "ram-boss" || scene == "ram-mixed" || scene == "ram-flight"
	wrecks := scene == "wrecks"
	arsenal := scene == "arsenal"
	mixed := scene == "mixed-crowd" || wrecks || arsenal
	assert(hero_view || ram_view || mixed || scene == "overview" || scene == "start" || scene == "tunnel" || scene == "effects" || scene == "crowd")
	subdivisions := 0
	if len(os.args) > 4 {
		value, ok := strconv.parse_int(os.args[4])
		assert(ok && value >= 0 && value <= 2)
		subdivisions = value
	}
	msaa := len(os.args) > 5 && os.args[5] != "0"
	rl.SetTraceLogLevel(.WARNING)
	flags := rl.ConfigFlags{.WINDOW_UNDECORATED}
	headless :: #config(TOAD_HEADLESS_TEST, false)
	if headless { flags += {.WINDOW_HIDDEN} }
	if msaa { flags += {.MSAA_4X_HINT} }
	rl.SetConfigFlags(flags)
	rl.InitWindow(i32(width), i32(height), "THE PRINCESS HAS MY TOAD / renderer measurement")
	assert(rl.IsWindowReady())
	defer rl.CloseWindow()
	rl.SetTargetFPS(0)
	rl.SetWindowPosition(0, 0)
	gl.load_up_to(3, 3, proc(p: rawptr, name: cstring) { (cast(^rawptr)p)^ = rlgl.GetProcAddress(name) })
	fmt.printf("GL GPU: %s | %s | %s\n", gl.GetString(gl.VENDOR), gl.GetString(gl.RENDERER), gl.GetString(gl.VERSION))
	if headless { fmt.println("Hidden GLX test: no physical display/refresh/presentation measurement; monitor-query fallback is linked only into this test.") }
	g_world: game.World
	if ram_view { game.world_init_ram(&g_world, game.DEFAULT_SEED)
	} else if mixed { game.world_load_sector(&g_world, .RAM_Combat_Lab, game.DEFAULT_SEED)
	} else { game.world_init(&g_world, game.DEFAULT_SEED) }
	defer game.world_destroy(&g_world)
	g := game.State{world = &g_world}
	game.init(&g)
	if scene == "ram-bus" { g.player.position = {22, 0, -114}; g.player.yaw = math.PI*0.5 }
	if scene == "ram-junction" { g.player.position = {126, 0, -148} }
	if scene == "ram-lift" { g.player.position = g_world.checkpoints[4].position }
	if scene == "ram-upper" { g.player.position = g_world.checkpoints[5].position; g.lift_started = true }
	if scene == "ram-corridor" { g.player.position, g.player.yaw = {29, 0.03, -114}, math.PI*0.5 }
	if scene == "ram-court" { g.player.position, g.player.yaw = {108, 0.03, -94}, 0.3 }
	if scene == "ram-mixed" { assert(game.debug_enter_room(&g, 1015)) }
	if scene == "ram-flight" {
		assert(game.debug_enter_room(&g, 1011))
		s := g_world.sector.sections[game.room_index(&g_world.sector, 1011)]
		p, target := game.CHARGE_LANDINGS[3], game.CHARGE_LANDINGS[5]
		g.player.position = s.origin+p+game.Vec3{0, 0.04, 0}
		g.player.yaw, g.player.pitch = math.atan2(target.x-p.x, p.z-target.z), -0.12
	}
	if scene == "ram-boss" {
		g.lift_started = true
		g.player.position = game.boss_room_origin(&g_world)+game.Vec3{0, 0.03, 14}
		g.boss.stage, g.boss.health = 2, 12
		game.boss_plan(&g)
		game.boss_phase(&g.boss, .Sweep, 2)
		g.boss.timer = 1
	}
	if mixed {
		for &e in g.enemies { e.health = 0 }
		g.enemy_total = 0
		for i in 0..<game.ENEMY_CAPACITY {
			kind := game.Enemy_Kind(i%5)
			_, ok := game.spawn_enemy(&g, {f32(i%8)*3+32, game.enemy_extent(kind).y+0.04, f32(i/8)*2.2-43}, 10, 0, kind)
			assert(ok)
			g.enemies[i].phase, g.enemies[i].phase_time = .Windup, 0.27
			g.enemies[i].attack_target = g.enemies[i].position-game.Vec3{0, g.enemies[i].position.y-0.04, 0}
		}
		g.enemies[4].phase, g.enemies[4].phase_time, g.enemies[4].shield = .Attack, 1, 6
		g.enemies[4].support = {3, g.enemies[3].generation}
		for i in 0..<len(g.hazards) { assert(game.spawn_floor_hazard(&g, {f32(i%6)*3+35, 0.04, f32(i/6)*3-35}, 2.8)) }
		for &p, i in g.particles { p = {{f32(i%16)*2+29, 2, f32(i/16)*1.1-43}, {}, 1, 1, 0.06, 0} }
		for &b, i in g.projectiles { b = {{f32(i%8)*3+32, 3, f32(i/8)*3-40}, {0, 0, 10}, 1, .Fairy} }
		for &f, i in g.fragments { f = {{f32(i%4)*3+37, 2.5, f32(i/4)*3-38}, {0, 0, -20}, 1} }
		if arsenal {
			sources := [3]game.Death_Cause{.Fairy, .Nanny, .GC}
			for &p, i in g.particles { p.kind, p.size = i%7, 0.6 if i%7 >= 5 else 0.08 }
			for &b, i in g.projectiles { b.source = sources[i%3] }
			for &p, i in g.gibs { p = {{f32(i%8)*2+29, 1.5, f32(i/8)*1.1-40}, {}, 6, 6, 0.2, i%3} }
		}
		g.player.position = {44, 0, -16}
		if wrecks { for &e in g.enemies { e.health, e.phase, e.phase_time, e.shield = 0, .Recover, 0, 0 } }
	}
	if scene == "tunnel" { g.player.position = {-9, 0, 11} }
	if ram_view || mixed { assert(game.world_clear_box(&g_world, g.player.position+game.Vec3{0, game.PLAYER_HEIGHT*0.5+0.02, 0}, {game.PLAYER_RADIUS, game.PLAYER_HEIGHT*0.5, game.PLAYER_RADIUS}), "Benchmark player is embedded in geometry") }
	if scene == "crowd" {
		for g.enemy_count < game.ENEMY_CAPACITY {
			i := g.enemy_count
			_, ok := game.spawn_enemy(&g, {f32(i%16)*3-23, 4+f32(i%3), -f32(i/16)*4}, 5, 0, .Interceptor if i%3 == 0 else .Sentry)
			assert(ok)
		}
		for &enemy, i in g.enemies { if i%3 == 0 { enemy.phase, enemy.phase_time = .Windup, 0.3 } }
	}
	if scene == "effects" || scene == "crowd" {
		for &bullet, i in g.projectiles {
			bullet = {{f32(i%12)*3-16, 3+f32(i%3), -f32(i/12)*4}, {0, 0, -12}, 100, .Fairy}
		}
		for &particle, i in g.particles {
			particle = {{f32(i%24)*1.5-16, 2+f32(i%7)*0.3, -f32(i/24)*2}, {}, 1, 1, 0.08, i%2}
		}
		for &flash, i in g.flashes { flash = {{f32(i%4)*8-12, 5, -f32(i/4)*8}, {1, 0.3, 0.06}, 10, 7, 1, 1} }
	}
	r: app.Renderer
	start := rl.GetTime()
	app.renderer_init(&r, &g)
	fmt.printf("Renderer init %.2f ms\n", (rl.GetTime()-start)*1000)
	defer app.renderer_destroy(&r)
	if len(os.args) > 6 && os.args[6] == "0" { r.culling_enabled = false }
	if len(os.args) > 8 {
		scale, ok := strconv.parse_f32(os.args[8])
		assert(ok && scale >= 0.5 && scale <= 1)
		r.render_scale = scale
	}
	if len(os.args) > 9 && os.args[9] == "0" { r.near_first = false }
	if subdivisions > 0 { subdivide_architecture(&r, subdivisions) }
	fmt.printf("Scene=%s subdivisions=%d architecture=%d vertices / %d triangles / %.2f MiB vertex data\n", scene, subdivisions, r.architecture_vertices, r.architecture_vertices/3, f64(r.architecture_vertices)*36/(1024*1024))
	frames :: 600
	warmup := 120
	warmup_deadline := rl.GetTime()+5
	queries: [frames*5]u32
	gl.GenQueries(len(queries), &queries[0])
	defer gl.DeleteQueries(len(queries), &queries[0])
	metrics: [7][frames]f64
	history: game.Pose_History
	view: game.Render_Snapshot
	for frame := 0; frame < warmup+frames; frame += 1 {
		if frame == warmup && rl.GetTime() < warmup_deadline { warmup += 1 }
		index := frame-warmup
		context.allocator = mem.panic_allocator()
		context.temp_allocator = mem.panic_allocator()
		if rl.WindowShouldClose() { return }
		// Measurement poses are identical across resolutions, regardless of
		// how many frames the minimum five-second clock warmup required.
		t := f32(120+index if index >= 0 else frame)/144
		if scene == "ram-flight" { t += 10.8 }
		g.time = t
		if !wrecks { for &enemy, i in g.enemies[:g.enemy_count] { enemy.position = enemy.anchor+game.Vec3{math.sin(t+f32(i))*1.6, 0, math.cos(t+f32(i))*1.4} } }
		if scene == "ram-boss" { g.boss.timer = 2-math.mod(t, 2) }
		cam := game.camera(&g)
		if scene == "enemy" {
			g.enemies[0].position = {0, 2.1, 7}
			g.enemies[0].facing = game.normalized(game.Vec3{0.3, -0.05, 1})
			g.enemies[0].phase, g.enemies[0].phase_time = .Windup, 0.25
			g.enemies[1].position = {2.5, 2.1, 7}
			g.enemies[1].kind, g.enemies[1].facing = .Interceptor, g.enemies[0].facing
			cam.position, cam.target, cam.fov = {1.8, 3.3, 11}, {1.1, 2.1, 7}, 52
			cam.forward = game.normalized(cam.target-cam.position)
		}
		if hero_view {
			g.player.grounded = scene != "hero-air" && scene != "hero-glide"
			g.player.idle_time = 8
			g.player.gait_phase = math.mod(t*16, 2*math.PI)
			if scene == "hero-run" || scene == "hero-air" { g.player.velocity = {9, 0, -8} }
			if scene == "hero-air" || scene == "hero-glide" { g.player.air_time = 0.2 }
			if scene == "hero-land" { g.player.land_time, g.player.land_strength = 0.12, 0.9 }
			if scene == "hero-glide" { g.player.glide_blend, g.player.gliding = 1, true }
			cam.position = g.player.position+game.Vec3{1.8, 1.5, -2.8}
			if scene == "hero-back" { cam.position = g.player.position+game.Vec3{-1.5, 2.8, 2.5} }
			if scene == "hero-top" { cam.position = g.player.position+game.Vec3{1.4, 3.1, -1.8} }
			cam.target = g.player.position+game.Vec3{0, 0.85, 0}
			cam.forward = game.normalized(cam.target-cam.position)
			cam.fov = 45 if scene != "hero-glide" else 72
		}
		if scene == "overview" || scene == "effects" || scene == "crowd" {
			cam.position = {22+math.sin(t*0.7)*18, 18, 25}
			cam.target = {0, 3, -12}
			cam.forward = game.normalized(cam.target-cam.position)
		}
		if mixed {
			// Look down into the whole court: its near wall must not conceal
			// the front half of this deliberately excessive crowd fixture.
			cam.position, cam.target, cam.fov = {44, 31, -22}, {44, 0, -27}, 72
			cam.forward = game.normalized(cam.target-cam.position)
		}
		game.capture_poses(&history, &g)
		game.render_snapshot(&view, &g, &history, 1)
		begin := rl.GetTime()
		rl.BeginDrawing()
		app.resize_render_target(&r)
		if index >= 0 { gl.QueryCounter(queries[index*5], gl.TIMESTAMP) }
		app.prepare_frame(&r, &view, cam, t)
		app.render_shadow(&r, &view, cam, t)
		if index >= 0 { gl.QueryCounter(queries[index*5+1], gl.TIMESTAMP) }
		app.update_lighting(&r, &view, cam)
		app.render_world_pass(&r, &view, cam, t)
		if index >= 0 { gl.QueryCounter(queries[index*5+2], gl.TIMESTAMP) }
		app.render_post_pass(&r)
		rlgl.DrawRenderBatchActive()
		if index >= 0 { gl.QueryCounter(queries[index*5+3], gl.TIMESTAMP) }
		app.draw_hud(&r, &g, false, false, true, 0, 0, 0)
		rlgl.DrawRenderBatchActive()
		if index >= 0 {
			gl.QueryCounter(queries[index*5+4], gl.TIMESTAMP)
			metrics[0][index] = (rl.GetTime()-begin)*1000
		}
		rl.EndDrawing()
		if index >= 0 { metrics[6][index] = (rl.GetTime()-begin)*1000 }
	}
	if len(os.args) > 7 {
		path: [512]u8
		assert(len(os.args[7]) < len(path))
		copy(path[:], os.args[7])
		rl.TakeScreenshot(cstring(&path[0]))
	}
	// Query results are read after the run, never by blocking each submitted frame.
	for frame in 0..<frames {
		timestamps: [5]u64
		for &timestamp, i in timestamps { gl.GetQueryObjectui64v(queries[frame*5+i], gl.QUERY_RESULT, &timestamp) }
		metrics[1][frame] = f64(timestamps[4]-timestamps[0])/1e6
		for stage in 0..<4 { metrics[stage+2][frame] = f64(timestamps[stage+1]-timestamps[stage])/1e6 }
	}
	names := [7]string{"cpu_submit", "gpu_total", "gpu_shadow", "gpu_world", "gpu_post", "gpu_hud", "hidden_swap" if headless else "frame_present"}
	for &values, index in metrics {
		slice.sort(values[:])
		sum := f64(0)
		for value in values { sum += value }
		fmt.printf("%dx%d %s mean=%.3f median=%.3f p95=%.3f p99=%.3f ms\n", r.width, r.height, names[index], sum/frames, values[frames/2], values[frames*95/100], values[frames*99/100])
	}
	samples: i32
	gl.GetIntegerv(gl.SAMPLES, &samples)
	fmt.printf("Default framebuffer samples=%d. Warmup=%d (at least 120 frames and 5 seconds), measured=%d. Odin frame allocations=0 (panic allocator).\n", samples, warmup, frames)
	fmt.println("No simulation/audio/input; HUD included. GPU intervals stop before EndDrawing, but can include shared-GPU/default-framebuffer waits.")
	if headless { fmt.println("Hidden-swap time is not visible presentation or input latency.")
	} else { fmt.println("Frame time includes presentation.") }
	fmt.printf("Chunks: total=%d world=%d shadow=%d culling=%v\n", len(r.chunks), r.visible_world_chunks, r.visible_shadow_chunks, r.culling_enabled)
	fmt.printf("Scene target: %dx%d, near-to-far=%v\n", r.target.texture.width, r.target.texture.height, r.near_first)
	fmt.printf("Instances: %d, world draws=%d shadow draws=%d\n", r.objects.count, r.objects.world_draws, r.objects.shadow_draws)
	fmt.printf("Hero: %d triangles, %d bones, one draw per visible pass\n", r.hero.models[r.hero.character].mesh.triangleCount, len(r.hero.bones))
	fmt.printf("GL error: %d\n", gl.GetError())
}

Vertex :: struct {
	position, normal: game.Vec3,
	uv: game.Vec2,
	color: rl.Color,
}

vertex_at :: proc(mesh: ^rl.Mesh, i: int) -> Vertex {
	return {{mesh.vertices[i*3], mesh.vertices[i*3+1], mesh.vertices[i*3+2]},
		{mesh.normals[i*3], mesh.normals[i*3+1], mesh.normals[i*3+2]},
		{mesh.texcoords[i*2], mesh.texcoords[i*2+1]},
		{mesh.colors[i*4], mesh.colors[i*4+1], mesh.colors[i*4+2], mesh.colors[i*4+3]}}
}

midpoint :: proc(a, b: Vertex) -> Vertex {
	color := rl.Color{u8((u16(a.color.r)+u16(b.color.r))/2), u8((u16(a.color.g)+u16(b.color.g))/2), u8((u16(a.color.b)+u16(b.color.b))/2), u8((u16(a.color.a)+u16(b.color.a))/2)}
	return {(a.position+b.position)*0.5, (a.normal+b.normal)*0.5, (a.uv+b.uv)*0.5, color}
}

split_triangle :: proc(m: ^app.Mesh_Builder, a, b, c: Vertex, depth: int) {
	if depth > 0 {
		ab, bc, ca := midpoint(a, b), midpoint(b, c), midpoint(c, a)
		split_triangle(m, a, ab, ca, depth-1)
		split_triangle(m, ab, b, bc, depth-1)
		split_triangle(m, ca, bc, c, depth-1)
		split_triangle(m, ab, bc, ca, depth-1)
		return
	}
	vertices := [3]Vertex{a, b, c}
	for v in vertices {
		append(&m.positions, v.position)
		append(&m.normals, v.normal)
		append(&m.uv, v.uv)
		append(&m.colors, v.color)
	}
}

subdivide_architecture :: proc(r: ^app.Renderer, depth: int) {
	// Same surfaces, more real triangles: separates polygon throughput from
	// the very different costs of added AI, materials or screen overdraw.
	m: app.Mesh_Builder
	defer app.mesh_destroy_builder(&m)
	for chunk in r.chunks {
		mesh := chunk.mesh
		for triangle in 0..<int(mesh.triangleCount) {
			i := triangle*3
			split_triangle(&m, vertex_at(&mesh, i), vertex_at(&mesh, i+1), vertex_at(&mesh, i+2), depth)
		}
	}
	app.upload_chunks(r, &m)
}
