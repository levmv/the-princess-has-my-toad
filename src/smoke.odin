package main

import "core:math"
import game "game"

smoke_input :: proc(g: ^game.State, session: ^Play_Session, frames: int) -> game.Input {
	input: game.Input
	// Finish the flight with repeatable ground and scope views of a sentry.
	if frames == 160 {
		g.player.position = g.checkpoint
		g.player.velocity = {}
		g.player.yaw, g.player.pitch = 0, -0.08
		game.capture_poses(&session.history, g)
	}
	if frames == 178 {
		game.aim_at(g, g.enemies[1].position, false)
	}
	if frames == 220 {
		g.player.position = {game.TUNNEL_X, 0, 11}
		g.player.velocity = {}
		g.player.yaw, g.player.pitch = 0, -0.08
		game.capture_poses(&session.history, g)
		session.was_focused = false
	}
	if frames == 245 { game.light_flash(g, {-8, 1.6, 8}, {1, 0.3, 0.06}, 10, 7, 0.5) }
	if frames == 270 {
		g.player.position = {-3.5, 0, 12}
		g.player.velocity = {}
		g.player.yaw, g.player.pitch = -math.PI/2, -0.08
		game.capture_poses(&session.history, g)
	}
	if frames == 310 { g.player.yaw = 0.9 }
	input.move.y = 1 if frames < 110 || (frames >= 270 && frames < 310) else 0
	input.jump_pressed = frames == 15 || frames == 30
	input.jump_held = (frames >= 15 && frames < 24) || (frames >= 30 && frames < 160)
	input.fire = (frames >= 40 && frames < 140) || (frames >= 195 && frames < 215)
	input.dash_pressed = frames == 150
	input.focus = (frames >= 110 && frames < 150) || (frames >= 180 && frames < 220)
	return input
}
