package main

import "core:math"
import gl "graphics"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "game"

Model_Kind :: enum { Beam, Enemy, Eye, Shot, Triangle, Cube, Ring, Arc, Vent, Line, SentryHull, InterceptorHull, EnemyFin, CrabShell, CrabPlate, CrabClaw, KettleBody, KettleLid, NannyBody, NannyUmbrella, NannyWheel, FragmentBarrel, Diskette, AmmoPacket, GCFittings, GCBrush, PixelAnvil, LauncherPickup, FairyHead, BloodSplat, FairyLimb, FairyHeart, CoreCage, ShotgunBody, ShellPacket, FragmentShell, GibFlesh, GibBone, FairyDart, NannyNeedle, GCShard, RabbitBody, RabbitHead, RabbitEar, RabbitJaw, RabbitPaw }
INSTANCE_CAPACITY :: 8192
WORLD_PASS :: 1
SHADOW_PASS :: 2

// Column vectors in GL attribute order. Normal matrices are calculated once per
// instance on the CPU and reused by every vertex and both render passes.
Instance :: struct { transform: [4][4]f32, normal: [3][4]f32, tint: [4]f32 }
Object_Command :: struct { instance: Instance, kind: Model_Kind, passes: int, surface: f32 }
Instance_Range :: struct { offset, count: int }
GPU_Model :: struct { mesh: rl.Mesh, mode: u32 }
Object_Renderer :: struct {
	models: [Model_Kind]GPU_Model,
	buffer: u32,
	commands: []Object_Command,
	instances: []Instance,
	ranges: [Model_Kind][4]Instance_Range,
	count, passes: int,
	world_draws, shadow_draws: int,
	scene_location, shadow_location: i32,
}

models_init :: proc(r: ^Renderer) {
	when ODIN_OS != .JS { gl.load_up_to(3, 3, proc(p: rawptr, name: cstring) { (cast(^rawptr)p)^ = rlgl.GetProcAddress(name) }) }
	o := &r.objects
	o.commands = make([]Object_Command, INSTANCE_CAPACITY)
	o.instances = make([]Instance, INSTANCE_CAPACITY)
	o.scene_location = rl.GetShaderLocation(r.scene, "instanced")
	o.shadow_location = rl.GetShaderLocation(r.depth, "instanced")
	assert(o.scene_location >= 0 && o.shadow_location >= 0)
	gl.GenBuffers(1, &o.buffer)
	gl.BindBuffer(gl.ARRAY_BUFFER, o.buffer)
	gl.BufferData(gl.ARRAY_BUFFER, len(o.instances)*size_of(Instance), nil, gl.STREAM_DRAW)
	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	for kind in Model_Kind {
		m: Mesh_Builder
		mode := u32(gl.TRIANGLES)
		mesh: rl.Mesh
		switch kind {
		case .SentryHull, .InterceptorHull: fairy_body(&m, kind == .InterceptorHull)
		case .EnemyFin: fairy_wing(&m)
		case .FairyHead: fairy_head(&m)
		case .FairyLimb: fairy_limb(&m)
		case .FairyHeart: fairy_heart(&m)
		case .CoreCage: core_cage(&m)
		case .RabbitBody: rabbit_body(&m)
		case .RabbitHead: rabbit_head(&m)
		case .RabbitEar: rabbit_ear(&m)
		case .RabbitJaw: rabbit_jaw(&m)
		case .RabbitPaw: rabbit_paw(&m)
  case .BloodSplat: blood_splat(&m)
		case .CrabShell: crab_shell(&m)
		case .CrabPlate: crab_plate(&m)
		case .CrabClaw: crab_claw(&m)
		case .KettleBody: kettle_body(&m)
		case .KettleLid: kettle_lid(&m)
		case .NannyBody: nanny_body(&m)
		case .NannyUmbrella: nanny_umbrella(&m)
		case .NannyWheel: nanny_wheel(&m)
		case .FragmentBarrel: fragment_barrel(&m)
		case .Diskette: pickup_diskette(&m)
		case .AmmoPacket: ammo_packet(&m)
		case .LauncherPickup: launcher_pickup(&m)
		case .ShotgunBody: shotgun_mesh(&m)
		case .ShellPacket: shell_packet(&m)
		case .FragmentShell: fragment_shell(&m)
		case .GibFlesh, .GibBone: gib_chunk(&m, kind == .GibBone)
		case .FairyDart, .NannyNeedle, .GCShard: enemy_projectile_mesh(&m, kind)
		case .GCFittings: gc_fittings(&m)
		case .GCBrush: gc_brush(&m)
		case .PixelAnvil: pixel_anvil(&m)
		case .Enemy: mesh = rl.GenMeshSphere(1, 5, 8)
		case .Eye: mesh = rl.GenMeshSphere(1, 4, 8)
		case .Shot: mesh = rl.GenMeshSphere(1, 4, 6)
		case .Cube: mesh = rl.GenMeshCube(1, 1, 1)
		case .Triangle: mesh_triangle(&m, nil, {}, {1, 0, 0}, {0, 1, 0}, rl.WHITE, 0, 10)
		case .Ring, .Arc, .Line:
			mode = gl.LINES
			segments := 1 if kind == .Line else (48 if kind == .Arc else 64)
			for i in 0..<segments {
				for end in 0..<2 {
					a := f32(i+end)*2*math.PI/64
					p := game.Vec3{math.cos(a), 0, math.sin(a)} if kind != .Line else game.Vec3{0, f32(end), 0}
					append(&m.positions, p)
					append(&m.normals, game.Vec3{0, 1, 0})
					append(&m.uv, game.Vec2{1, SURFACE_LIGHT})
					append(&m.colors, rl.WHITE)
				}
			}
		case .Beam, .Vent:
			sides, ratio := 5, f32(1)
			if kind == .Vent { sides = 32 }
			for i in 0..<sides {
				a, b := f32(i)*2*math.PI/f32(sides), f32(i+1)*2*math.PI/f32(sides)
				p, q := game.Vec3{math.cos(a), 0, -math.sin(a)}, game.Vec3{math.cos(b), 0, -math.sin(b)}
				x, y := game.Vec3{p.x*ratio, 1, p.z*ratio}, game.Vec3{q.x*ratio, 1, q.z*ratio}
				mesh_quad(&m, nil, p, q, y, x, rl.WHITE, 0, 10)
				mesh_triangle(&m, nil, {}, q, p, rl.WHITE, 0, 10)
				mesh_triangle(&m, nil, {0, 1, 0}, x, y, rl.WHITE, 0, 10)
			}
		}
		if len(m.positions) > 0 { mesh = mesh_upload(&m)
		} else {
			// These primitives arrive with texture coordinates, not surface IDs.
			for i in 0..<int(mesh.vertexCount) { mesh.texcoords[i*2], mesh.texcoords[i*2+1] = 1, SURFACE_PAINT }
			rl.UpdateMeshBuffer(mesh, 1, mesh.texcoords, mesh.vertexCount*2*size_of(f32), 0)
		}
		mesh_destroy_builder(&m)
		o.models[kind] = {mesh, mode}
	}
}

models_destroy :: proc(r: ^Renderer) {
	for model in r.objects.models { rl.UnloadMesh(model.mesh) }
	gl.DeleteBuffers(1, &r.objects.buffer)
	delete(r.objects.commands)
	delete(r.objects.instances)
}

object_instance :: proc(r: ^Renderer, kind: Model_Kind, position, x, y, z: game.Vec3, color: rl.Color, surface: f32 = -1) {
	o := &r.objects
	assert(o.count < len(o.commands), "Render instance capacity exceeded")
	determinant := game.dot(x, game.cross(y, z))
	if abs(determinant) < 1e-12 { return }
	nx, ny, nz := game.cross(y, z)/determinant, game.cross(z, x)/determinant, game.cross(x, y)/determinant
	instance := Instance{
		transform = {{x.x, x.y, x.z, 0}, {y.x, y.y, y.z, 0}, {z.x, z.y, z.z, 0}, {position.x, position.y, position.z, 1}},
		normal = {{nx.x, nx.y, nx.z, 0}, {ny.x, ny.y, ny.z, 0}, {nz.x, nz.y, nz.z, 0}},
		tint = {f32(color.r)/255, f32(color.g)/255, f32(color.b)/255, f32(color.a)/255},
	}
	o.commands[o.count] = {instance, kind, o.passes, surface}
	o.ranges[kind][o.passes].count += 1
	o.count += 1
}

upload_instances :: proc(r: ^Renderer) {
	o := &r.objects
	offset := 0
	for &ranges in o.ranges {
		for &group in ranges { group.offset = offset; offset += group.count; group.count = 0 }
	}
	for command in o.commands[:o.count] {
		group := &o.ranges[command.kind][command.passes]
		instance := &o.instances[group.offset+group.count]
		instance^ = command.instance
		// Pack material metadata only after pose/death transforms have finished.
		// Normal-matrix padding saves another GPU attribute and buffer stream.
		instance.normal[0][3] = command.surface
		group.count += 1
	}
	gl.BindBuffer(gl.ARRAY_BUFFER, o.buffer)
	gl.BufferSubData(gl.ARRAY_BUFFER, 0, o.count*size_of(Instance), &o.instances[0])
	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
}

// Persistent meshes and one persistent instance buffer: no per-frame mesh/VBO creation.
// GL 3.3 has no base-instance draw, so attributes select each group's buffer range.
draw_instances :: proc(r: ^Renderer, shadow: bool) {
	o := &r.objects
	shader := r.depth if shadow else r.scene
	location := o.shadow_location if shadow else o.scene_location
	pass := SHADOW_PASS if shadow else WORLD_PASS
	rlgl.DrawRenderBatchActive()
	enabled := i32(1)
	rl.SetShaderValue(shader, location, &enabled, .INT)
	rl.SetShaderValueMatrix(shader, shader.locs[rl.ShaderLocationIndex.MATRIX_MVP], rlgl.GetMatrixProjection()*rlgl.GetMatrixModelview())
	gl.UseProgram(shader.id)
	gl.BindBuffer(gl.ARRAY_BUFFER, o.buffer)
	draws := 0
	// Generated raylib primitives have no color stream. Their disabled color
	// attribute uses white; authored meshes keep their panel colors.
	gl.VertexAttrib4f(3, 1, 1, 1, 1)
	for model, kind in o.models {
		for group, mask in o.ranges[kind] {
			if group.count == 0 || mask&pass == 0 { continue }
			gl.BindVertexArray(model.mesh.vaoId)
			for attribute in 0..<8 {
				location := u32(4+attribute)
				gl.EnableVertexAttribArray(location)
				gl.VertexAttribPointer(location, 4, gl.FLOAT, false, i32(size_of(Instance)), uintptr(group.offset*size_of(Instance)+attribute*16))
				gl.VertexAttribDivisor(location, 1)
			}
			if model.mesh.indices != nil {
				gl.DrawElementsInstanced(model.mode, model.mesh.triangleCount*3, gl.UNSIGNED_SHORT, nil, i32(group.count))
			} else {
				gl.DrawArraysInstanced(model.mode, 0, model.mesh.vertexCount, i32(group.count))
			}
			draws += 1
		}
	}
	gl.BindVertexArray(0)
	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	enabled = 0
	rl.SetShaderValue(shader, location, &enabled, .INT)
	if shadow { o.shadow_draws = draws } else { o.world_draws = draws }
}
