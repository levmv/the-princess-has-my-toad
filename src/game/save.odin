package game

// The wire schema is independent of struct padding, pointer size and host
// endian. Additions require a new format version, never a silent reinterpret.
SAVE_VERSION :: u32(7)
SAVE_LIMIT :: 256*1024
SAVE_HEADER_SIZE :: 24
Save_Error :: enum { None, Truncated, Too_Large, Magic, Version, Checksum, Generator, Value, Content, Busy }
Save_Mode :: enum u8 { Quick = 0, Checkpoint = 1 }
Saved_Variant :: struct { id: Room_ID, variant: Room_Variant }
Saved_Run :: struct {
	state: Run_State,
	support_targets: [ENEMY_CAPACITY]Object_ID,
	encounter_rooms: [ENEMY_CAPACITY]Room_ID,
}
Save_Data :: struct {
	stamp: u64,
	mode: Save_Mode,
	kind: Level_Kind,
	sector: Sector_ID,
	seed, generator: u32,
	variants: [SECTOR_ROOM_CAPACITY]Saved_Variant,
	variant_count: int,
	live, restart: Saved_Run,
	gates, restart_gates: [GATE_CAPACITY]Gate_State,
	gate_count: int,
}

save_error_text :: proc(err: Save_Error) -> string {
	switch err {
	case .None: return "Saved."
	case .Truncated: return "Save is incomplete."
	case .Too_Large: return "Save exceeds the size limit."
	case .Magic: return "This is not a THE PRINCESS HAS MY TOAD save."
	case .Version: return "Save format belongs to a different build."
	case .Checksum: return "Save checksum failed."
	case .Generator: return "This build cannot recreate that generator version."
	case .Value: return "Save contains invalid state."
	case .Content: return "Save does not match this sector's content."
	case .Busy: return "Saving is unavailable during a simulation step."
	}
	unreachable()
}

save_capture_run :: #force_no_inline proc(out: ^Saved_Run, run: ^Run_State, w: ^World) {
	out.state = run^
	// Old one-shot events must not replay after a load. Sequence cursors stay
	// intact; presentation resynchronizes before the next simulation tick.
	out.state.sound_events = {}
	for e, i in run.enemies[:run.enemy_count] {
		if e.encounter > 0 && e.encounter <= len(w.encounters) { out.encounter_rooms[i] = w.encounters[e.encounter-1].room }
		if int(e.support.slot) < run.enemy_count {
			target := run.enemies[e.support.slot]
			if target.health > 0 && target.generation == e.support.generation { out.support_targets[i] = target.content_id }
		}
	}
}

save_capture :: #force_no_inline proc(out: ^Save_Data, g: ^State, mode: Save_Mode, stamp: u64) -> Save_Error {
	if g.in_step || g.respawn_pending || !g.restart.valid { return .Busy }
	out^ = Save_Data{stamp = stamp, mode = mode, kind = g.world.kind, sector = g.world.sector.key, seed = g.world.seed, generator = GENERATOR_VERSION, variant_count = g.world.sector.count, gate_count = g.world.gate_count}
	for s, i in g.world.sector.sections[:g.world.sector.count] { out.variants[i] = {s.id, s.variant} }
	save_capture_run(&out.live, &g.run if mode == .Quick || g.won else &g.restart.run, g.world)
	save_capture_run(&out.restart, &g.restart.run, g.world)
	for gate, i in g.world.gates[:g.world.gate_count] {
		out.gates[i] = {gate.id, gate.open, gate.amount} if mode == .Quick || g.won else g.restart.gates[i]
		out.restart_gates[i] = g.restart.gates[i]
	}
	return .None
}

// Decode and build into private candidates. A failed read, incompatible ID or
// generator must leave both the live simulation and its render revision alone.
save_restore :: #force_no_inline proc(g: ^State, data: ^Save_Data) -> Save_Error {
	if g.in_step { return .Busy }
	if data.generator != GENERATOR_VERSION { return .Generator }
	if !save_valid_metadata(data) { return .Value }
	w: World
	defer world_destroy(&w)
	if data.kind == .Arena {
		world_init(&w, data.seed)
	} else {
		r: Sector_Recipe
		switch data.sector {
		case .RAM_Bank_01: r = ram_cold_boot()
		case .RAM_Transfer: r = ram_transfer()
		case .RAM_Combat_Lab: r = ram_combat_lab()
		case .None: return .Content
		}
		if data.variant_count != r.count { return .Content }
		seen: [SECTOR_ROOM_CAPACITY]bool
		for v in data.variants[:data.variant_count] {
			index := room_index(&r, v.id)
			if index < 0 || seen[index] { return .Content }
			seen[index] = true
			if r.sections[index].variant == .Auto {
				if v.variant != .Weave && v.variant != .Split { return .Content }
			} else if r.sections[index].variant != v.variant { return .Content }
			r.sections[index].variant = v.variant
		}
		world_build_ram(&w, r, data.seed)
	}
	candidate := State{world = &w, difficulty = data.live.state.difficulty}
	init(&candidate)
	baseline := candidate.run
	if !save_resolve_run(&candidate.run, &data.live, &baseline, &w) { return .Content }
	if !save_resolve_run(&candidate.restart.run, &data.restart, &baseline, &w) { return .Content }
	if !save_resolve_gates(&w, data.gates[:data.gate_count]) { return .Content }
	candidate.restart.gate_count = data.gate_count
	// Checkpoint gates can be stored in a different order; snapshots retain
	// the world's canonical ordering, just as ordinary checkpoint capture does.
	for gate, i in w.gates[:w.gate_count] {
		found := false
		for saved in data.restart_gates[:data.gate_count] {
			if saved.id == gate.id { candidate.restart.gates[i] = saved; found = true; break }
		}
		if !found { return .Content }
	}
	if candidate.run.difficulty != candidate.restart.run.difficulty || candidate.hero != candidate.restart.run.hero { return .Content }
	// The live run may have just completed the sector, before the checkpoint
	// copy was updated. Its completion bit is meaningful across transitions.
	completed := candidate.restart.run.campaign.completed
	if candidate.won && data.sector != .None && !sector_definition(data.sector).preview { completed |= u64(1)<<u16(data.sector) }
	if candidate.campaign.completed != completed { return .Content }
	old_world, revision := g.world, g.world.revision
	if save_same_geometry(old_world, &w) {
		// A quickload in the same sector changes simulation and moving gates,
		// not GPU architecture or materials. Keep the renderer's static cache.
		old_world.gates = w.gates
	} else {
		world_destroy(old_world)
		old_world^ = w
		w = {}
		old_world.revision, old_world.index_revision = revision+1, revision+1
	}
	candidate.world = old_world
	g^ = candidate
	boss_exit_sync(g)
	return .None
}

save_same_slice :: proc(a, b: []$T) -> bool {
	if len(a) != len(b) { return false }
	for v, i in a { if v != b[i] { return false } }
	return true
}

save_same_geometry :: proc(a, b: ^World) -> bool {
	if a.sector.boss != b.sector.boss { return false }
	if a.seed != b.seed || a.kind != b.kind || a.sector.key != b.sector.key || a.sector.generator_version != b.sector.generator_version || a.sector.count != b.sector.count || a.spawn != b.spawn || a.exit != b.exit || a.gate_count != b.gate_count { return false }
	for section, i in a.sector.sections[:a.sector.count] {
		if section.id != b.sector.sections[i].id || section.variant != b.sector.sections[i].variant { return false }
	}
	if !save_same_slice(a.blocks[:], b.blocks[:]) || !save_same_slice(a.decor_blocks[:], b.decor_blocks[:]) || !save_same_slice(a.decor_beams[:], b.decor_beams[:]) { return false }
	if !save_same_slice(a.lamps[:], b.lamps[:]) || !save_same_slice(a.vents[:], b.vents[:]) { return false }
	return true
}

save_valid_metadata :: proc(d: ^Save_Data) -> bool {
	if d.kind != .Arena && d.kind != .RAM { return false }
	if d.mode != .Quick && d.mode != .Checkpoint { return false }
	if d.sector < .None || d.sector > .RAM_Combat_Lab { return false }
	if (d.kind == .Arena) != (d.sector == .None) { return false }
	if d.variant_count < 0 || d.variant_count > len(d.variants) || d.gate_count < 0 || d.gate_count > len(d.gates) { return false }
	if d.kind == .Arena && (d.variant_count != 0 || d.gate_count != 0) { return false }
	for run in ([2]^Run_State{&d.live.state, &d.restart.state}) {
		if run.campaign.current != d.sector || run.campaign.seed != d.seed { return false }
		if !save_valid_run(run) { return false }
	}
	for i in 0..<d.gate_count {
		for gates in ([2]^Gate_State{&d.gates[i], &d.restart_gates[i]}) {
			if gates.id == 0 || !(gates.amount >= 0 && gates.amount <= 1) || (!gates.open && gates.amount != 0) { return false }
		}
	}
	return true
}

save_resolve_gates :: proc(w: ^World, gates: []Gate_State) -> bool {
	if len(gates) != w.gate_count { return false }
	seen: [GATE_CAPACITY]bool
	for saved in gates {
		found := false
		for &gate, i in w.gates[:w.gate_count] {
			if saved.id != gate.id { continue }
			if seen[i] { return false }
			seen[i], found = true, true
			gate.open, gate.amount = saved.open, saved.amount
			break
		}
		if !found { return false }
	}
	return true
}

save_resolve_run :: #force_no_inline proc(out: ^Run_State, saved: ^Saved_Run, base: ^Run_State, w: ^World) -> bool {
	r := &saved.state
	if r.enemy_count != base.enemy_count || r.enemy_total != base.enemy_total || r.pickup_count != base.pickup_count || r.core_count != base.core_count { return false }
	out^ = r^
	seen: [ENEMY_CAPACITY]bool
	for e, i in r.enemies[:r.enemy_count] {
		index := -1
		for b, j in base.enemies[:base.enemy_count] { if e.content_id == b.content_id { index = j; break } }
		if index < 0 || seen[index] { return false }
		seen[index] = true
		b := base.enemies[index]
		if e.kind != b.kind || e.health > b.health || e.anchor != b.anchor || e.awareness != b.awareness { return false }
		room := Room_ID(0)
		if b.encounter > 0 { room = w.encounters[b.encounter-1].room }
		if room != saved.encounter_rooms[i] { return false }
		out.enemies[i].encounter = b.encounter
		out.enemies[i].support = {}
		target_id := saved.support_targets[i]
		if target_id != 0 {
			found := false
			for other, j in r.enemies[:r.enemy_count] {
				if other.content_id == target_id && other.health > 0 && j != i { out.enemies[i].support = {u32(j), other.generation}; found = true; break }
			}
			if !found { return false }
		}
	}
	pickups_seen: [PICKUP_CAPACITY]bool
	for p in r.pickups[:r.pickup_count] {
		index := -1
		for b, j in base.pickups[:base.pickup_count] { if p.id == b.id { index = j; break } }
		if index < 0 || pickups_seen[index] { return false }
		pickups_seen[index] = true
		b := base.pickups[index]
		if p.position != b.position || p.kind != b.kind || p.amount != b.amount { return false }
	}
	collected := 0
	for c, i in r.cores[:r.core_count] {
		if c.position != base.cores[i].position { return false }
		if c.collected { collected += 1 }
	}
	if collected != r.collected { return false }
	for id, i in r.secrets[:r.secret_count] {
		found := false
		for s in w.sector.sections[:w.sector.count] { if s.intent == .Secret && room_object_id(s.id, 0x500) == id { found = true; break } }
		if !found { return false }
		for earlier in r.secrets[:i] { if earlier == id { return false } }
	}
	checkpoint := w.spawn
	out.mission_checkpoint = 0
	if r.checkpoint_id != 0 {
		found := false
		if w.kind == .RAM {
			for c, i in w.checkpoints[:w.checkpoint_count] {
				if c.id == r.checkpoint_id { checkpoint, found, out.mission_checkpoint = c.position, true, u8(i+1); break }
			}
		} else {
			for c, i in r.cores[:r.core_count] {
				if core_object_id(i) == r.checkpoint_id && c.collected { checkpoint, found = c.position-Vec3{0, 0.85, 0}, true; break }
			}
		}
		if !found { return false }
	}
	if r.checkpoint != checkpoint { return false }
	if r.lift_started && w.sector.mechanism != .Shot_Lift { return false }
	if !boss_valid(w, r.boss) || !anvil_valid(r.anvil) { return false }
	if r.won && !exit_ready(w, r.collected, r.core_count, r.lift_started, r.boss) { return false }
	return true
}

save_valid_run :: proc(r: ^Run_State) -> bool {
	if r.hero < .Duke || r.hero > .Lora { return false }
	if r.difficulty < .Hard || r.difficulty > .Nightmare { return false }
	if r.enemy_count < 0 || r.enemy_count > len(r.enemies) || r.enemy_total < 0 || r.enemy_total > ENEMY_CAPACITY { return false }
	if r.pickup_count < 0 || r.pickup_count > len(r.pickups) || r.core_count < 0 || r.core_count > len(r.cores) || r.secret_count < 0 || r.secret_count > len(r.secrets) { return false }
	if r.collected < 0 || r.collected > r.core_count || r.kills < 0 || r.kills > r.enemy_total || r.deaths < 0 { return false }
	if !(r.time >= 0 && r.time < 1e8) { return false }
	if r.rng == 0 || r.weapon_rng == 0 || r.effect_rng == 0 || r.campaign.completed & ~u64(1<<1) != 0 { return false }
	if r.particle_cursor < 0 || r.trace_cursor < 0 || r.projectile_cursor < 0 || r.projectile_cursor >= len(r.projectiles) || r.flash_cursor < 0 || r.flash_cursor >= len(r.flashes) { return false }
	p := &r.player
	if !(p.health > 0 && p.health <= 100 && p.pitch >= -1.2 && p.pitch <= 1.15) || p.fragment_ammo < 0 || p.fragment_ammo > FRAGMENT_AMMO_MAX { return false }
	if p.weapon < .Repeater || p.weapon > .Shotgun || !weapon_owned(p, p.weapon) { return false }
	if p.shotgun_ammo < 0 || p.shotgun_ammo > SHOTGUN_AMMO_MAX || p.shotgun_cooldown < -1 || p.shotgun_cooldown > SHOTGUN_INTERVAL { return false }
	if r.gib_cursor < 0 || r.gib_cursor >= len(r.gibs) { return false }
	if !(p.hurt_strength >= 0 && p.hurt_strength <= 1) { return false }
	if !(p.hurt_time >= 0 && p.hurt_time <= 0.28) { return false }
	for e in r.enemies[:r.enemy_count] {
		if e.content_id == 0 || e.generation == 0 || e.health < -1000 || e.health > 1000 || e.shield < 0 || e.shield > 6 || e.rounds < 0 || e.rounds > 3 { return false }
		if e.kind < .Sentry || e.kind > .Rabbit_Kit || e.phase < .Patrol || e.phase > .Hatching { return false }
		if e.gibbed && (e.health > 0 || !enemy_organic(e.kind)) { return false }
		if e.phase == .Dormant || e.phase == .Hatching {
			if (e.kind != .Rabbit_Young && e.kind != .Rabbit_Kit) || e.health <= 0 { return false }
			if e.phase_time < 0 || e.phase_time > RABBIT_HATCH_TIME { return false }
		}
	}
	return true
}
