package main

import "core:math"
import rl "vendor:raylib"
import game "game"

Mesh_Builder :: struct {
	positions, normals: [dynamic]game.Vec3,
	uv: [dynamic]game.Vec2,
	colors: [dynamic]rl.Color,
	ao_cache: map[[6]f32]f32,
}

mesh_destroy_builder :: proc(m: ^Mesh_Builder) {
	delete(m.positions)
	delete(m.normals)
	delete(m.uv)
	delete(m.colors)
	delete(m.ao_cache)
}

ao_directions := make_ao_directions()
make_ao_directions :: proc "contextless" () -> [8]game.Vec3 {
	result: [8]game.Vec3
	for &d, i in result {
		angle := f32(i)*2.399963
		radius := math.sqrt((f32(i)+0.5)/8)
		d = {math.cos(angle)*radius, math.sin(angle)*radius, math.sqrt(1-radius*radius)}
	}
	return result
}

ambient_visibility :: proc(g: ^game.World, position, normal: game.Vec3) -> f32 {
	helper := game.Vec3{0, 1, 0} if abs(normal.y) < 0.9 else game.Vec3{1, 0, 0}
	u := game.normalized(game.cross(helper, normal))
	v := game.cross(normal, u)
	visibility := f32(0)
	for d in ao_directions {
		direction := u*d.x+v*d.y+normal*d.z
		distance := game.world_ray(g, position+normal*0.025, direction, 2.8)
		visibility += min(1, distance/2.8)
	}
	return 0.22+0.78*visibility/8
}

mesh_triangle :: proc(m: ^Mesh_Builder, g: ^game.World, a, b, c: game.Vec3, color: rl.Color, material: f32, detail: f32 = 2.5, depth: int = 0) {
	ab, bc, ca := game.length(b-a), game.length(c-b), game.length(a-c)
	if depth < 9 && max(ab, max(bc, ca)) > detail {
		if ab >= bc && ab >= ca {
			mid := (a+b)*0.5
			mesh_triangle(m, g, a, mid, c, color, material, detail, depth+1)
			mesh_triangle(m, g, mid, b, c, color, material, detail, depth+1)
		} else if bc >= ca {
			mid := (b+c)*0.5
			mesh_triangle(m, g, a, b, mid, color, material, detail, depth+1)
			mesh_triangle(m, g, a, mid, c, color, material, detail, depth+1)
		} else {
			mid := (c+a)*0.5
			mesh_triangle(m, g, a, b, mid, color, material, detail, depth+1)
			mesh_triangle(m, g, mid, b, c, color, material, detail, depth+1)
		}
		return
	}
	n := game.normalized(game.cross(b-a, c-a))
	if game.length(n) < 0.5 { return }
	points := [3]game.Vec3{a, b, c}
	for p in points {
		ao := f32(1)
		if g != nil && (material < 2.5 || material > 3.5) {
			// Exact position/normal keys preserve the same lighting at shared
			// triangle corners. Cache only one solid at a time to bound memory.
			if m.ao_cache == nil { m.ao_cache = make(map[[6]f32]f32) }
			key := [6]f32{p.x, p.y, p.z, n.x, n.y, n.z}
			cached, exists := m.ao_cache[key]
			if exists { ao = cached } else { ao = ambient_visibility(g, p, n); m.ao_cache[key] = ao }
		}
		append(&m.positions, p)
		append(&m.normals, n)
		append(&m.uv, game.Vec2{ao, material})
		append(&m.colors, color)
	}
}

mesh_quad :: proc(m: ^Mesh_Builder, g: ^game.World, a, b, c, d: game.Vec3, color: rl.Color, material: f32, detail: f32 = 2.5) {
	mesh_triangle(m, g, a, b, c, color, material, detail)
	mesh_triangle(m, g, a, c, d, color, material, detail)
}

// Derive every face from the collision planes. No separate hand-built visible
// floor can disagree with the shape used by movement or aiming.
mesh_block :: proc(m: ^Mesh_Builder, g: ^game.World, block: game.Block, base, top: rl.Color, material: f32 = 0, detail: f32 = 0) {
	if g != nil { clear(&m.ao_cache) }
	b := block
	count := 6+b.clip_count
	for face_index in 0..<count {
		face := game.block_plane(&b, face_index)
		duplicate := false
		for previous in 0..<face_index {
			p := game.block_plane(&b, previous)
			if game.dot(p.normal, face.normal) > 0.99999 && abs(p.distance-face.distance) < 0.002 { duplicate = true; break }
		}
		if duplicate { continue }
		points: [32]game.Vec3
		point_count := 0
		for i in 0..<count {
			if i == face_index { continue }
			p := game.block_plane(&b, i)
			for j in i+1..<count {
				if j == face_index { continue }
				q := game.block_plane(&b, j)
				cross_pq := game.cross(p.normal, q.normal)
				denominator := game.dot(face.normal, cross_pq)
				if abs(denominator) < 0.00001 { continue }
				vertex := (cross_pq*face.distance+game.cross(q.normal, face.normal)*p.distance+game.cross(face.normal, p.normal)*q.distance)/denominator
				inside := true
				for k in 0..<count {
					plane := game.block_plane(&b, k)
					if game.dot(plane.normal, vertex) > plane.distance+0.003 { inside = false; break }
				}
				if !inside { continue }
				for existing in points[:point_count] {
					if game.length(vertex-existing) < 0.005 { inside = false; break }
				}
				if !inside { continue }
				assert(point_count < len(points))
				points[point_count] = vertex
				point_count += 1
			}
		}
		if point_count < 3 { continue }
		center: game.Vec3
		for p in points[:point_count] { center += p }
		center /= f32(point_count)
		helper := game.Vec3{0, 1, 0} if abs(face.normal.y) < 0.9 else game.Vec3{1, 0, 0}
		u := game.normalized(game.cross(helper, face.normal))
		v := game.cross(face.normal, u)
		angles: [32]f32
		for p, i in points[:point_count] { angles[i] = math.atan2(game.dot(p-center, v), game.dot(p-center, u)) }
		for i in 1..<point_count {
			p, a := points[i], angles[i]
			j := i-1
			for j >= 0 && angles[j] > a { points[j+1], angles[j+1] = points[j], angles[j]; j -= 1 }
			points[j+1], angles[j+1] = p, a
		}
		color := base
		if face.normal.y > 0.5 { color = top }
		if face.normal.y > 0.1 && face.normal.y < 0.95 {
			color = {u8((u16(base.r)+u16(top.r))/2), u8((u16(base.g)+u16(top.g))/2), u8((u16(base.b)+u16(top.b))/2), 255}
		}
		face_material := material
		if g != nil && material == 0 && face.normal.y > 0.95 { face_material = 1 }
		for i in 0..<point_count {
			mesh_triangle(m, g, center, points[i], points[(i+1)%point_count], color, face_material, detail if detail > 0 else (2.3 if g != nil else 15))
		}
	}
}

mesh_beam :: proc(m: ^Mesh_Builder, a, b: game.Vec3, radius_a, radius_b: f32, color: rl.Color, material: f32 = 0, sides: int = 6) {
	direction := game.normalized(b-a)
	helper := game.Vec3{0, 1, 0} if abs(direction.y) < 0.9 else game.Vec3{1, 0, 0}
	u := game.normalized(game.cross(direction, helper))
	v := game.cross(direction, u)
	for i in 0..<sides {
		angle_a := f32(i)*2*math.PI/f32(sides)
		angle_b := f32(i+1)*2*math.PI/f32(sides)
		x := u*math.cos(angle_a)+v*math.sin(angle_a)
		y := u*math.cos(angle_b)+v*math.sin(angle_b)
		p, q := a+x*radius_a, a+y*radius_a
		r, s := b+x*radius_b, b+y*radius_b
		mesh_quad(m, nil, p, q, s, r, color, material, 10)
		mesh_triangle(m, nil, a, q, p, color, material, 10)
		mesh_triangle(m, nil, b, r, s, color, material, 10)
	}
}

mesh_upload :: proc(m: ^Mesh_Builder) -> rl.Mesh {
	count := len(m.positions)
	assert(count > 0)
	positions := make([]game.Vec3, count, rl.MemAllocator())
	normals := make([]game.Vec3, count, rl.MemAllocator())
	uv := make([]game.Vec2, count, rl.MemAllocator())
	colors := make([]rl.Color, count, rl.MemAllocator())
	copy(positions, m.positions[:])
	copy(normals, m.normals[:])
	copy(uv, m.uv[:])
	copy(colors, m.colors[:])
	mesh := rl.Mesh{
		vertexCount = i32(count), triangleCount = i32(count/3),
		vertices = cast([^]f32)raw_data(positions), normals = cast([^]f32)raw_data(normals),
		texcoords = cast([^]f32)raw_data(uv), colors = cast([^]u8)raw_data(colors),
	}
	rl.UploadMesh(&mesh, false)
	return mesh
}

// Work units are solids, decorative pieces, rooms and bounded upload batches.
// Desktop drains the job synchronously; browser startup yields between batches.
Architecture_Bake :: struct {
	mesh: Mesh_Builder,
	upload: Chunk_Upload,
	phase, index: int,
}

bake_world_block :: proc(m: ^Mesh_Builder, g: ^game.World, block: game.Block) {
		base, top := rl.Color{65, 83, 92, 255}, rl.Color{176, 182, 159, 255}
		material := f32(0)
		if block.style == 1 { base = {92, 88, 84, 255}; top = {190, 176, 141, 255} }
		if block.style == 2 { base = {51, 83, 90, 255}; top = {151, 186, 170, 255} }
		if block.style == 3 { base = {45, 61, 74, 255}; top = {100, 126, 138, 255}; material = 2 }
		if block.style == 4 { base = {91, 107, 113, 255}; top = {144, 163, 156, 255}; material = 1 }
		if block.style == 5 { base = {98, 118, 127, 255}; top = {139, 149, 151, 255}; material = 2 }
		if block.style == 6 { base = {35, 73, 61, 255}; top = {65, 128, 104, 255}; material = 4 }
		if block.style == 7 { base = {36, 73, 109, 255}; top = {166, 175, 176, 255}; material = 2 }
		if block.style == 8 { base = {109, 120, 123, 255}; top = {161, 173, 164, 255}; material = 2 }
		if block.style == 9 { base = {46, 57, 65, 255}; top = {113, 131, 136, 255}; material = 2 }
		if block.style == 10 { base = {29, 67, 53, 255}; top = {80, 120, 88, 255}; material = 4 }
		if block.style == 11 { base = {91, 49, 30, 255}; top = {153, 103, 62, 255}; material = 2 }
		if block.style == 12 { base = {35, 33, 38, 255}; top = {79, 69, 63, 255}; material = 2 }
		if block.style == 13 { base = {34, 48, 85, 255}; top = {91, 124, 169, 255}; material = 2 }
		if block.style == 14 { base = {154, 164, 148, 255}; top = {211, 208, 173, 255}; material = 1 }
		if block.style == 15 { base = {59, 36, 77, 255}; top = {132, 110, 145, 255}; material = 2 }
		if block.style == game.STYLE_ROSE_STONE { base = {188, 100, 129, 255}; top = {233, 161, 180, 255}; material = SURFACE_STONE }
		if block.style == game.STYLE_DARK_ROSE { base = {85, 42, 63, 255}; top = {150, 85, 114, 255}; material = SURFACE_STONE }
		if block.style == game.STYLE_OLD_GOLD { base = {129, 96, 47, 255}; top = {190, 158, 85, 255}; material = SURFACE_PAINT }
		if block.style == game.STYLE_ROYAL_CANVAS { base = {96, 27, 44, 255}; top = {128, 44, 57, 255}; material = SURFACE_CLOTH }
		mesh_block(m, g, block, base, top, material)
}

bake_architecture_step :: proc(job: ^Architecture_Bake, r: ^Renderer, w: ^game.World) -> bool {
	m := &job.mesh
	switch job.phase {
	case 0:
		if job.index < len(w.blocks) {
			bake_world_block(m, w, w.blocks[job.index]); job.index += 1; return false
		}
	case 1:
		if job.index < len(w.decor_blocks) {
			v := w.decor_blocks[job.index]
			mesh_block(m, nil, v.shape, {v.base[0], v.base[1], v.base[2], 255}, {v.top[0], v.top[1], v.top[2], 255})
			job.index += 1; return false
		}
	case 2:
		if job.index < len(w.decor_beams) {
			b := w.decor_beams[job.index]
			mesh_beam(m, b.a, b.b, b.radius_a, b.radius_b, {b.color[0], b.color[1], b.color[2], 255}, b.material, b.sides)
			job.index += 1; return false
		}
	case 3:
		if job.index < w.sector.count {
			bake_interior_details(m, w, job.index, 1)
			if w.sector.key == .RAM_Bank_01 { bake_royal_banner(m, w.sector.sections[job.index]) }
			job.index += 1; return false
		}
	case 4:
		if !upload_chunks_step(r, m, &job.upload) { return false }
		mesh_destroy_builder(m)
		job.mesh = {}
	case 5: return true
	}
	job.phase += 1
	job.index = 0
	return job.phase == 5
}

bake_architecture_progress :: proc(job: ^Architecture_Bake, w: ^game.World) -> f32 {
	counts := [4]int{len(w.blocks), len(w.decor_blocks), len(w.decor_beams), w.sector.count}
	weights := [5]f32{0.70, 0.06, 0.02, 0.10, 0.12}
	progress := f32(0)
	for weight, i in weights {
		if job.phase > i { progress += weight
		} else if job.phase == i {
			if i < 4 { progress += weight*f32(job.index)/f32(max(1, counts[i]))
			} else { progress += weight*upload_chunks_progress(&job.upload, &job.mesh) }
		}
	}
	return progress
}

bake_architecture :: proc(r: ^Renderer, g: ^game.World) {
	job: Architecture_Bake
	for !bake_architecture_step(&job, r, g) {}
}
