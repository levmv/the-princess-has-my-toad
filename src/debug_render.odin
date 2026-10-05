package main

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import game "game"

Debug_View :: enum { None, Collision, Navigation, Perception, All }
Debug_Render :: struct {
	view: Debug_View,
	mesh: rl.Mesh,
	material: rl.Material,
	source: ^game.World,
	revision: u64,
}

debug_destroy :: proc(d: ^Debug_Render) {
	if d.mesh.vertexCount > 0 { rl.UnloadMesh(d.mesh) }
	if d.material.maps != nil { rl.MemFree(d.material.maps) }
	d^ = {}
}

debug_sync :: proc(d: ^Debug_Render, w: ^game.World) {
	if d.view != .Collision && d.view != .All { return }
	if d.source == w && d.revision == w.revision { return }
	if d.mesh.vertexCount > 0 { rl.UnloadMesh(d.mesh) }
	if d.material.maps == nil { d.material = rl.LoadMaterialDefault() }
	m: Mesh_Builder
	defer mesh_destroy_builder(&m)
	for b in w.blocks { mesh_block(&m, nil, b, {75, 238, 183, 255}, {75, 238, 183, 255}, detail = 10000) }
	if len(m.positions) > 0 { d.mesh = mesh_upload(&m) }
	d.source, d.revision = w, w.revision
}

draw_debug_world :: proc(r: ^Renderer, g: ^game.Render_Snapshot) {
	d := &r.debug
	if d.view == .None { return }
	if d.view == .Collision || d.view == .All {
		if d.mesh.vertexCount > 0 { rlgl.EnableWireMode(); rl.DrawMesh(d.mesh, d.material, rl.Matrix(1)); rlgl.DisableWireMode() }
		for gate in g.world.gates[:g.world.gate_count] {
			b := game.gate_shape(gate)
			rl.DrawCubeWiresV(rl.Vector3(b.center), rl.Vector3(b.size), ORANGE)
		}
		rl.DrawCubeWiresV(rl.Vector3(g.player.position+game.Vec3{0, game.PLAYER_HEIGHT*0.5, 0}), {game.PLAYER_RADIUS*2, game.PLAYER_HEIGHT, game.PLAYER_RADIUS*2}, PAPER)
	}
	if d.view == .Navigation || d.view == .All {
		for &n in g.world.room_navigation[:g.world.sector.count] {
			for p, i in n.points[:n.count] {
				if game.length(p-g.player.position) > 95 { continue }
				from := p+game.Vec3{0, 0.15, 0}
				rl.DrawSphereWires(rl.Vector3(from), 0.15, 4, 6, MINT)
				for j in i+1..<n.count {
					// Representative ground/air routes; each actor uses its own hull's graph.
					if n.links[.Crab][i] & (u16(1)<<u32(j)) != 0 { rl.DrawLine3D(rl.Vector3(from), rl.Vector3(n.points[j]+game.Vec3{0, 0.15, 0}), MINT) }
					if n.links[.Sentry][i] & (u16(1)<<u32(j)) != 0 { rl.DrawLine3D(rl.Vector3(p+game.Vec3{0, 2, 0}), rl.Vector3(n.points[j]+game.Vec3{0, 2, 0}), ORANGE) }
				}
			}
		}
		for c in g.world.sector.connections[:g.world.sector.connection_count] {
			if game.length(c.position-g.player.position) > 95 { continue }
			rl.DrawSphereWires(rl.Vector3(c.position+game.Vec3{0, 1, 0}), 0.6, 6, 8, PAPER)
		}
	}
}

// AI data is read from the live simulation only for the explicit developer view.
// The normal Render_Snapshot remains a compact presentation interface.
draw_debug_ai :: proc(r: ^Renderer, g: ^game.State, camera: game.Camera) {
	if r.debug.view != .Perception && r.debug.view != .All { return }
	rl.BeginMode3D({camera.position, camera.target, {0, 1, 0}, camera.fov, .PERSPECTIVE})
	// Perception is an explicit x-ray diagnostic over the postprocessed image.
	rlgl.DisableDepthTest()
	for e in g.enemies[:g.enemy_count] {
		if e.health <= 0 || game.length(e.position-g.player.position) > 95 { continue }
		color := RED if e.sees_player else (ORANGE if e.alerted else MUTED)
		rl.DrawCubeWiresV(rl.Vector3(e.position), rl.Vector3(game.enemy_extent(e.kind)*2), color)
		rl.DrawLine3D(rl.Vector3(e.position), rl.Vector3(e.position+e.facing*2), color)
		if e.alerted {
			rl.DrawLine3D(rl.Vector3(e.position), rl.Vector3(e.last_known), color)
			rl.DrawLine3D(rl.Vector3(e.position), rl.Vector3(e.nav_goal), MINT)
		}
	}
	rlgl.EnableDepthTest()
	rl.EndMode3D()
}
