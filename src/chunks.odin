package main

import "core:math"
import rl "vendor:raylib"
import game "game"

Render_Chunk :: struct { mesh: rl.Mesh, bounds: game.Bounds }

// The tiny intro stage and the current level retain independent GPU geometry.
// Switching menus must not throw away and rebake an entire RAM sector.
Geometry_Cache :: struct {
	chunks: [dynamic]Render_Chunk,
	draw_order: []int,
	chunk_distance: []f32,
	vertices: int,
	world: ^game.World,
	revision: u64,
	seed: u32,
}

swap_geometry :: proc(r: ^Renderer) {
	old := Geometry_Cache{r.chunks, r.draw_order, r.chunk_distance, r.architecture_vertices, r.world_source, r.world_revision, r.geometry_seed}
	c := r.other_geometry
	r.chunks, r.draw_order, r.chunk_distance = c.chunks, c.draw_order, c.chunk_distance
	r.architecture_vertices, r.world_source, r.world_revision = c.vertices, c.world, c.revision
	r.geometry_seed = c.seed
	r.other_geometry = old
}

destroy_chunks :: proc(r: ^Renderer) {
	for chunk in r.chunks { rl.UnloadMesh(chunk.mesh) }
	clear(&r.chunks)
	delete(r.draw_order); delete(r.chunk_distance)
	r.draw_order, r.chunk_distance = nil, nil
}

Chunk_Upload :: struct {
	builders: [dynamic]Mesh_Builder,
	cells: map[[3]int]int,
	triangle, uploaded: int,
	partitioned: bool,
}

upload_chunks_step :: proc(r: ^Renderer, source: ^Mesh_Builder, work: ^Chunk_Upload) -> bool {
	if !work.partitioned {
		if work.cells == nil { work.cells = make(map[[3]int]int) }
		end := min(len(source.positions), work.triangle+768*3)
		for first := work.triangle; first < end; first += 3 {
			center := (source.positions[first]+source.positions[first+1]+source.positions[first+2])/3
			cell := [3]int{int(math.floor(center.x/32)), int(math.floor(center.y/32)), int(math.floor(center.z/32))}
			index, exists := work.cells[cell]
			if !exists { index = len(work.builders); work.cells[cell] = index; append(&work.builders, Mesh_Builder{}) }
			b := &work.builders[index]
			append(&b.positions, ..source.positions[first:first+3])
			append(&b.normals, ..source.normals[first:first+3])
			append(&b.uv, ..source.uv[first:first+3])
			append(&b.colors, ..source.colors[first:first+3])
		}
		work.triangle = end
		if end < len(source.positions) { return false }
		destroy_chunks(r)
		r.architecture_vertices = 0
		work.partitioned = true
		return false
	}
	if work.uploaded < len(work.builders) {
		b := &work.builders[work.uploaded]
		bounds := game.Bounds{b.positions[0], b.positions[0]}
		for p in b.positions { bounds = game.bounds_union(bounds, {p, p}) }
		append(&r.chunks, Render_Chunk{mesh_upload(b), bounds})
		r.architecture_vertices += len(b.positions)
		mesh_destroy_builder(b)
		work.uploaded += 1
		return false
	}
	delete(work.cells); delete(work.builders)
	work.cells, work.builders = nil, nil
	r.draw_order = make([]int, len(r.chunks))
	r.chunk_distance = make([]f32, len(r.chunks))
	for &index, i in r.draw_order { index = i }
	return true
}

upload_chunks_progress :: proc(work: ^Chunk_Upload, source: ^Mesh_Builder) -> f32 {
	if !work.partitioned { return f32(work.triangle)/f32(max(1, len(source.positions)))*0.55 }
	return 0.55+f32(work.uploaded)/f32(max(1, len(work.builders)))*0.45
}

upload_chunks :: proc(r: ^Renderer, source: ^Mesh_Builder) {
	work: Chunk_Upload
	for !upload_chunks_step(r, source, &work) {}
}

// Opaque surfaces submit near to far so depth rejection happens before the
// expensive material/light shader. Insertion sort reuses the previous order;
// ordinary camera movement changes only a few neighbours. No frame allocation.
order_chunks :: proc(r: ^Renderer, eye: game.Vec3) {
	if !r.near_first { return }
	for chunk, i in r.chunks {
		closest := eye
		for axis in 0..<3 { closest[axis] = clamp(eye[axis], chunk.bounds.lo[axis], chunk.bounds.hi[axis]) }
		delta := eye-closest
		r.chunk_distance[i] = game.dot(delta, delta)
	}
	for i in 1..<len(r.draw_order) {
		index := r.draw_order[i]
		distance := r.chunk_distance[index]
		j := i-1
		for j >= 0 && r.chunk_distance[r.draw_order[j]] > distance { r.draw_order[j+1] = r.draw_order[j]; j -= 1 }
		r.draw_order[j+1] = index
	}
}

draw_chunks :: proc(r: ^Renderer, material: rl.Material, clip: rl.Matrix) -> int {
	visible := 0
	for index in r.draw_order {
		chunk := r.chunks[index]
		if r.culling_enabled && !game.bounds_visible(chunk.bounds, clip) { continue }
		rl.DrawMesh(chunk.mesh, material, rl.Matrix(1))
		visible += 1
	}
	return visible
}

sync_world_mesh :: proc(r: ^Renderer, w: ^game.World) {
	if r.world_source == w && r.world_revision == w.revision && r.material_seed == w.seed { return }
	assert(w.index_revision == w.revision, "Commit edited world geometry before rendering")
	if r.material_seed != w.seed {
		rl.UnloadTexture(r.grain)
		rl.UnloadTexture(r.glow)
		generate_materials(r, w.seed)
		r.material_seed = w.seed
	}
	if r.world_source != w { swap_geometry(r) }
	if r.world_source != w || r.world_revision != w.revision || r.geometry_seed != w.seed { bake_architecture(r, w) }
	finish_world_mesh(r, w)
}

finish_world_mesh :: proc(r: ^Renderer, w: ^game.World) {
	r.world_revision, r.world_source = w.revision, w
	r.geometry_seed = w.seed
	debug_sync(&r.debug, w)
	r.shadow_center, r.shadow_extent = {}, 104
	// Fit the sun to playable geometry; background decoration does not dilute it.
	if len(w.nodes) > 0 {
		bounds := w.nodes[0].bounds
		r.shadow_center = (bounds.lo+bounds.hi)*0.5
		r.shadow_extent = max(104, game.length(bounds.hi-bounds.lo)+12)
	}
}
