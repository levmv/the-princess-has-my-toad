package tests

import "core:math"
import "core:testing"
import game "../src/game"

@(test)
outside_tunnel_contact_keeps_player_and_camera_out_of_wall :: proc(t: ^testing.T) {
	for side in 0..<2 {
		sign := f32(side*2-1)
		g_world: game.World
		game.world_init(&g_world, game.DEFAULT_SEED)
		defer game.world_destroy(&g_world)
		g := game.State{world = &g_world}
		reset_fixture(&g)
		g.player.position = {game.TUNNEL_X+sign*4.5, 0, 12}
		g.player.yaw = -sign*math.PI/2
		// Keep pushing after the first contact. The wall slopes over the player,
		// so sliding along it must also preserve the simultaneous floor contact.
		for step in 0..<360 {
			game.update_player(&g, game.Input{move = {0, 1}}, game.STEP)
			if !testing.expectf(t, sign*(g.player.position.x-game.TUNNEL_X) > 3.9,
				"Pushing against the tunnel penetrated its outer wall on side %d at step %d: %v", side, step, g.player.position) { return }
		}
		for yaw_step in 0..<72 {
			for pitch_step in 0..<13 {
				g.player.yaw = f32(yaw_step)*math.PI/36
				g.player.pitch = -1.2+f32(pitch_step)*2.35/12
				cam := game.camera(&g)
				right := game.normalized(game.cross(cam.forward, game.Vec3{0, 1, 0}))
				up := game.cross(right, cam.forward)
				aspects := [5]f32{1.6, 16.0/9.0, 2.4, 4, 6.4}
				for aspect in aspects {
					near := game.camera_near_clip(cam.fov, aspect)
					for corner in 0..<4 {
						x, y := f32((corner%2)*2-1), f32((corner/2)*2-1)
						delta := cam.forward*near+right*(x*near*math.tan(cam.fov*math.PI/360)*aspect)+up*(y*near*math.tan(cam.fov*math.PI/360))
						distance := game.length(delta)
						clearance := game.world_ray(&g, cam.position, delta/distance, distance)
						if !testing.expectf(t, clearance >= distance-0.00001,
							"Camera clips the wall at aspect=%v yaw=%v pitch=%v, corner=%d", aspect, g.player.yaw, g.player.pitch, corner) { return }
					}
				}
			}
		}
	}
}

@(test)
sloping_wall_and_floor_preserve_movement_along_the_wall :: proc(t: ^testing.T) {
	g_world: game.World
	game.world_init(&g_world, game.DEFAULT_SEED)
	defer game.world_destroy(&g_world)
	g := game.State{world = &g_world}
	reset_fixture(&g)
	g.player.position = {-3.5, 0, 14}
	g.player.yaw = -math.PI/2
	for _ in 0..<90 { game.update_player(&g, game.Input{move = {0, 1}}, game.STEP) }
	start := g.player.position
	for _ in 0..<30 { game.update_player(&g, game.Input{move = {1, 1}}, game.STEP) }
	testing.expect(t, g.player.position.z < start.z-1, "Contact with the floor and sloped wall must still allow sideways movement")
	testing.expect(t, g.player.position.x > -5.1 && abs(g.player.position.y) < 0.001, "Sliding must stay outside the wall and above the floor")
}

@(test)
repeated_jumps_against_tunnel_cannot_cross_its_shell :: proc(t: ^testing.T) {
	for side in 0..<2 {
		for mode in 0..<3 {
			sign := f32(side*2-1)
			g_world: game.World
			game.world_init(&g_world, game.DEFAULT_SEED)
			defer game.world_destroy(&g_world)
			g := game.State{world = &g_world}
			reset_fixture(&g)
			g.player.position = {game.TUNNEL_X+sign*4.5, 0, 12}
			g.player.yaw = -sign*math.PI/2
			for _ in 0..<180 { game.update_player(&g, game.Input{move = {0, 1}}, game.STEP) }
			for step in 0..<1440 {
				game.update_player(&g, game.Input{
					move = {0, 1},
					jump_pressed = g.player.grounded,
					jump_held = mode == 1,
					dash_pressed = mode == 2 && step%300 == 0,
				}, game.STEP)
				center := g.player.position+game.Vec3{0, game.PLAYER_HEIGHT*0.5, 0}
				extent := game.Vec3{game.PLAYER_RADIUS, game.PLAYER_HEIGHT*0.5, game.PLAYER_RADIUS}
				for &block in g.world.blocks[:] {
					if block.style != 5 { continue }
					separated := false
					for face in 0..<6+block.clip_count {
						plane := game.block_plane(&block, face)
						n := plane.normal
						support := abs(n.x)*extent.x+abs(n.y)*extent.y+abs(n.z)*extent.z
						if game.dot(center, n) >= plane.distance+support-0.0005 { separated = true; break }
					}
					if !testing.expectf(t, separated,
						"Jumping into the tunnel penetrated its shell: side=%d mode=%d step=%d position=%v", side, mode, step, g.player.position) { return }
				}
				// Climbing the exterior ledges onto the roof is a valid route. Stop
				// once the feet clear it, before the pilot flies off the far edge.
				if g.jump_sequence >= 2 && g.player.position.y > 5.8 { break }
			}
			testing.expectf(t, g.jump_sequence >= 2, "The regression must exercise repeated jumps, got %d", g.jump_sequence)
			testing.expect_value(t, g.deaths, 0)
		}
	}
}
