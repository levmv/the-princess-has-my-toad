package combat_checks

import "core:fmt"
import "core:math"
import "core:os"
import game "../../src/game"
import replay "../../src/replay"

main :: proc() {
	prefix := "build/combat"
	if len(os.args) > 1 { prefix = os.args[1] }
	passed := true
	for difficulty in game.Difficulty {
		for room_id in ([3]game.Room_ID{3002, 3003, 3004}) {
			w: game.World
			game.world_load_sector(&w, .RAM_Combat_Lab, 42)
			g := game.State{world = &w, difficulty = difficulty}
			game.init(&g)
			room := w.sector.sections[game.room_index(&w.sector, room_id)]
			target_count := 0
			for &e in g.enemies[:g.enemy_count] {
				if w.encounters[e.encounter-1].room == room_id { target_count += 1
				} else { e.health, e.phase_time = 0, 0 }
			}
			g.player.position = {0, 0.03, -12} if room_id == 3002 else (game.Vec3{12, 0.03, -27} if room_id == 3003 else game.Vec3{31, 0.03, -27})
			g.player.invulnerable, g.player.grounded = 0, true
			game.capture_checkpoint(&g)
			tape: replay.Tape
			assert(replay.begin(&tape, &g, 120*90) == .None)
			attacked: [game.Enemy_Kind]bool
			for tick in 0..<120*90 {
				if g.kills == target_count || g.deaths > 0 { break }
				command := combat_command(&g, room, tick)
				game.update(&g, command, game.STEP)
				replay.record_tick(&tape, command, &g)
				for e in g.enemies[:g.enemy_count] { if e.health > 0 && e.phase == .Attack { attacked[e.kind] = true } }
			}
			assert(replay.finish(&tape, &g) == .None)
			path := fmt.aprintf("%s-%v-%d.nvr", prefix, difficulty, room_id)
			write_error := replay.write(&tape, path)
			if write_error != .None {
				fmt.printf("Replay write failed: %v: %s\n", write_error, replay.error_text(write_error))
				for &command, tick in tape.commands[:tape.count] {
					buffer: [replay.COMMAND_SIZE]u8
					cursor := game.Save_Cursor{bytes = buffer[:]}
					replay.command_codec(&cursor, &command)
					if cursor.error != .None { fmt.printf("Invalid command tick=%d input=%v error=%v\n", tick, command, cursor.error) }
				}
			}
			assert(write_error == .None)
			fmt.printf("%v room=%d kills=%d/%d hp=%.1f deaths=%d seconds=%.2f position=%v attacks=%v replay=%s\n", difficulty, room_id, g.kills, target_count, g.player.health, g.deaths, f32(tape.count)*game.STEP, g.player.position, attacked, path)
			if g.kills != target_count || g.deaths > 0 {
				passed = false
				for e in g.enemies[:g.enemy_count] { if e.health > 0 { fmt.printf("  alive %v hp=%d pos=%v phase=%v sees=%v\n", e.kind, e.health, e.position, e.phase, e.sees_player) } }
			}
			delete(path)
			replay.destroy(&tape)
			game.world_destroy(&w)
		}
	}
	assert(passed, "A characteristic encounter could not be completed; see its replay and diagnostics")
	fmt.println("COMBAT CHECK OK: three authored encounters on each difficulty, real controller and base gun, no invulnerability or extra health. Perfect aim is not a human balance or duration test.")
}

// An intentionally explicit technical pilot: perfect pointing plus ordinary
// movement, gun spread, kick and jump. It is not a proxy for human difficulty.
combat_command :: proc(g: ^game.State, room: game.Section_Recipe, tick: int) -> game.Input {
	best, score := -1, f32(1e9)
	point: game.Vec3
	origin := g.player.position+game.Vec3{0, game.EYE_HEIGHT, 0}
	for e, i in g.enemies[:g.enemy_count] {
		if e.health <= 0 { continue }
		weak, _, open := game.enemy_weak_spot(e)
		target := weak if open else e.position
		delta := target-origin
		distance := game.length(delta)
		visible := game.world_ray(g.world, origin, game.normalized(delta), distance) >= distance-0.04
		priority := distance+(0 if visible else f32(60))-(15 if e.kind == .Nanny else f32(0))
		if priority < score { best, score, point = i, priority, target }
	}
	if best < 0 { return {} }
	e := &g.enemies[best]
	game.aim_at(g, point, true)
	// The old four-second no-fire warmup relied on enemies being harmless.
	// Completion now tests an immediate response; individual attack/dodge
	// contracts are exercised independently in pressure_test and roles_test.
	input := game.Input{has_look = true, look = {g.player.yaw, g.player.pitch}, focus = true, fire = tick >= 30}
	to_enemy := e.position-g.player.position
	to_enemy.y = 0
	distance := game.length(to_enemy)
	direction := game.normalized(to_enemy)
	right := game.Vec3{math.cos(g.player.yaw), 0, math.sin(g.player.yaw)}
	forward := game.forward(g.player.yaw, 0)
	goal := room.origin
	goal.y = g.player.position.y
	if room.id == 3004 {
		// A wide patrol crosses all four open lanes around the court's cover.
		corners := [4]game.Vec3{{-7, 0, 7}, {7, 0, 7}, {7, 0, -7}, {-7, 0, -7}}
		goal = room.origin+corners[(tick/360)%4]
	}
	if e.kind == .Crab && distance < 11 { goal = e.position-direction*2.3; goal.y = g.player.position.y }
	desired := goal-g.player.position
	desired.y = 0
	desired = game.normalized(desired)*min(1, game.length(desired)*0.5)
	if e.kind == .Interceptor && e.phase == .Windup && e.phase_time < 0.2 { desired = game.normalized(game.cross(to_enemy, game.Vec3{0, 1, 0})) }
	if e.kind == .Kettle && (e.phase == .Windup || e.phase == .Attack) { desired = game.normalized(game.cross(to_enemy, game.Vec3{0, 1, 0})) }
	input.move = {clamp(game.dot(desired, right), -1, 1), clamp(game.dot(desired, forward), -1, 1)}
	input.kick_pressed = distance < 2.8 && g.player.kick_cooldown <= 0
	input.jump_pressed = g.player.grounded && ((e.kind == .Crab && e.phase == .Windup && e.phase_time < 0.38) || (room.id == 3004 && tick%150 == 0))
	input.jump_held = input.jump_pressed
	return input
}
