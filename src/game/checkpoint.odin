package game

Gate_State :: struct { id: Object_ID, open: bool, amount: f32 }
Checkpoint_State :: struct {
	run: Run_State,
	gates: [GATE_CAPACITY]Gate_State,
	gate_count: int,
	valid: bool,
}

// Preserve only progression and view direction. Both checkpoint capture and
// respawn use this list; new animation/attack fields default to a resting state.
reset_checkpoint_player :: proc(p: ^Player, position: Vec3, invulnerability: f32) {
	p^ = Player{
		position = position, yaw = p.yaw, pitch = p.pitch,
		health = max(65, p.health), invulnerable = max(invulnerability, p.invulnerable),
		weapon = p.weapon,
		fragment_unlocked = p.fragment_unlocked, fragment_ammo = p.fragment_ammo,
		shotgun_unlocked = p.shotgun_unlocked, shotgun_ammo = p.shotgun_ammo,
	}
}

reset_respawn_player :: proc(g: ^State) {
	reset_checkpoint_player(&g.player, g.checkpoint, 2.5)
	g.focused = false
	g.message, g.message_time = 2, 3
	for &bullet in g.projectiles { bullet.life = 0 }
	for &fragment in g.fragments { fragment.life = 0 }
	for &hazard in g.hazards { hazard.life = 0 }
}

capture_checkpoint :: #force_no_inline proc(g: ^State) {
	r := &g.restart
	r.run, r.gate_count, r.valid = g.run, g.world.gate_count, true
	r.run.focused = false
	reset_checkpoint_player(&r.run.player, g.checkpoint, 1.25)
	r.run.projectiles, r.run.fragments, r.run.hazards = {}, {}, {}
	r.run.particles, r.run.flashes, r.run.traces = {}, {}, {}
	r.run.sound_events, r.run.player_noise, r.run.anvil = {}, {}, {}
	if r.run.boss.id != 0 && r.run.boss.phase != .Dead && Room_ID(u32(g.checkpoint_id)>>16) == g.world.sector.boss.at.room { boss_phase(&r.run.boss, .Dormant, 0) }
	r.run.message_time = 0
	for gate, i in g.world.gates[:g.world.gate_count] { r.gates[i] = {gate.id, gate.open, 1 if gate.open else 0} }
	g.checkpoint_pending = false
	g.checkpoint_sequence += 1
}

checkpoint_changed :: proc(g: ^State) {
	if g.in_step { g.checkpoint_pending = true } else { capture_checkpoint(g) }
}

// Death is deferred until the end of the tick, so restoring an actor array
// cannot invalidate a live attack's references halfway through its update.
respawn :: #force_no_inline proc(g: ^State) {
	if g.in_step { g.respawn_pending = true; return }
	deaths := g.deaths+1
	if g.restart.valid {
		g.run = g.restart.run
		for saved in g.restart.gates[:g.restart.gate_count] {
			for &gate in g.world.gates[:g.world.gate_count] {
				if gate.id == saved.id { gate.open, gate.amount = saved.open, saved.amount; break }
			}
		}
	}
	reset_respawn_player(g)
	g.deaths, g.respawn_pending, g.checkpoint_pending = deaths, false, false
	boss_exit_sync(g)
}

core_object_id :: proc(index: int) -> Object_ID { return Object_ID(0xA0000000+u32(index)+1) }
