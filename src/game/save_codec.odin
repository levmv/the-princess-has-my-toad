package game

import "base:intrinsics"

// A new gameplay field must be considered by the explicit wire schema and its
// version. This catches accidental omissions when the simulation grows.
#assert(intrinsics.type_struct_field_count(Run_State) == 57, "Update the save schema and SAVE_VERSION for the changed Run_State")
#assert(intrinsics.type_struct_field_count(Boss_State) == 12)
#assert(intrinsics.type_struct_field_count(Sweep_Lane) == 3)
#assert(intrinsics.type_struct_field_count(Anvil_State) == 6)
#assert(intrinsics.type_struct_field_count(Player) == 37)
#assert(intrinsics.type_struct_field_count(Enemy) == 35)
#assert(intrinsics.type_struct_field_count(Core) == 2)
#assert(intrinsics.type_struct_field_count(Pickup) == 5)
#assert(intrinsics.type_struct_field_count(Projectile) == 4)
#assert(intrinsics.type_struct_field_count(Fragment) == 3)
#assert(intrinsics.type_struct_field_count(Floor_Hazard) == 5)
#assert(intrinsics.type_struct_field_count(Particle) == 6)
#assert(intrinsics.type_struct_field_count(Light_Flash) == 6)
#assert(intrinsics.type_struct_field_count(Trace) == 3)
#assert(intrinsics.type_struct_field_count(Campaign_Progress) == 3)
#assert(intrinsics.type_struct_field_count(Player_Noise) == 4)
#assert(intrinsics.type_struct_field_count(Gate_State) == 3)
#assert(intrinsics.type_struct_field_count(Save_Data) == 13)

Save_Cursor :: struct { bytes: []u8, at: int, reading: bool, error: Save_Error }

save_word :: proc(c: ^Save_Cursor, value: ^u64, size: int) {
	if c.error != .None { return }
	if size > len(c.bytes)-c.at { c.error = .Truncated; return }
	if c.reading { value^ = 0 }
	for i in 0..<size {
		if c.reading { value^ |= u64(c.bytes[c.at+i])<<u32(i*8) } else { c.bytes[c.at+i] = u8(value^>>u32(i*8)) }
	}
	c.at += size
}

// Primitive encodings are fixed width, including Odin's platform-sized int.
// Arrays recurse element by element; structs below explicitly name fields.
save_field :: #force_no_inline proc(c: ^Save_Cursor, value: ^$T) {
	if c.error != .None { return }
	when intrinsics.type_is_array(T) {
		for &component in value^ { save_field(c, &component) }
	} else when T == bool {
		word := u64(1 if value^ else 0)
		save_word(c, &word, 1)
		if word > 1 { c.error = .Value }
		if c.reading { value^ = word == 1 }
	} else when T == f32 {
		word := u64(transmute(u32)value^)
		save_word(c, &word, 4)
		if c.reading { value^ = transmute(f32)u32(word) }
		if !(value^ >= -1e8 && value^ <= 1e8) { c.error = .Value }
	} else when T == int {
		if !c.reading && (value^ < -0x80000000 || value^ > 0x7FFFFFFF) { c.error = .Value; return }
		word := u64(transmute(u32)i32(value^))
		save_word(c, &word, 4)
		if c.reading { value^ = int(transmute(i32)u32(word)) }
	} else when intrinsics.type_is_enum(T) {
		word := u64(value^)
		save_word(c, &word, 4)
		found := false
		for member in T { if u64(member) == word { found = true; break } }
		if !found { c.error = .Value; return }
		if c.reading { value^ = T(word) }
	} else when T == u32 || T == u64 || T == u8 || T == Object_ID || T == Room_ID {
		word := u64(value^)
		save_word(c, &word, 8 if T == u64 else 4)
		when T == u8 { if word > 255 { c.error = .Value; return } }
		when T == Room_ID { if word > 65535 { c.error = .Value; return } }
		if c.reading { value^ = T(word) }
	} else {
		#panic("Save schema contains an unsupported field type")
	}
}

save_count :: proc(c: ^Save_Cursor, count: ^int, capacity: int) {
	save_field(c, count)
	if count^ < 0 || count^ > capacity { c.error = .Value; count^ = 0 }
}

save_checksum :: proc(bytes: []u8) -> u32 {
	hash := u32(2166136261)
	for b in bytes { hash = (hash ~ u32(b))*16777619 }
	return hash
}

save_encode :: #force_no_inline proc(data: ^Save_Data, bytes: []u8) -> (int, Save_Error) {
	if len(bytes) < SAVE_HEADER_SIZE { return 0, .Truncated }
	c := Save_Cursor{bytes = bytes, at = SAVE_HEADER_SIZE}
	save_payload(&c, data)
	if c.error != .None { return 0, c.error }
	if c.at > SAVE_LIMIT { return 0, .Too_Large }
	header := Save_Cursor{bytes = bytes}
	magic, version, size, checksum := u32(0x5354564E), SAVE_VERSION, u32(c.at), u32(0)
	save_field(&header, &magic); save_field(&header, &version); save_field(&header, &size); save_field(&header, &checksum)
	save_field(&header, &data.stamp)
	// The timestamp belongs to the checksum too. It was written after the
	// payload so no stale bytes from an earlier use of the buffer can leak.
	checksum = save_checksum(bytes[16:c.at])
	header.at = 12
	save_field(&header, &checksum)
	return c.at, .None
}

save_decode :: #force_no_inline proc(bytes: []u8, out: ^Save_Data) -> Save_Error {
	if len(bytes) < SAVE_HEADER_SIZE { return .Truncated }
	if len(bytes) > SAVE_LIMIT { return .Too_Large }
	c := Save_Cursor{bytes = bytes, reading = true}
	magic, version, size, checksum := u32(0), u32(0), u32(0), u32(0)
	save_field(&c, &magic); save_field(&c, &version); save_field(&c, &size); save_field(&c, &checksum)
	if magic != 0x5354564E { return .Magic }
	if version != SAVE_VERSION { return .Version }
	if int(size) != len(bytes) { return .Truncated }
	if save_checksum(bytes[16:]) != checksum { return .Checksum }
	candidate: Save_Data
	save_field(&c, &candidate.stamp)
	save_payload(&c, &candidate)
	if c.error != .None { return c.error }
	if c.at != len(bytes) || !save_valid_metadata(&candidate) { return .Value }
	if candidate.generator != GENERATOR_VERSION { return .Generator }
	out^ = candidate
	return .None
}

save_payload :: #force_no_inline proc(c: ^Save_Cursor, d: ^Save_Data) {
	save_field(c, &d.mode); save_field(c, &d.kind); save_field(c, &d.sector)
	save_field(c, &d.seed); save_field(c, &d.generator)
	save_count(c, &d.variant_count, len(d.variants))
	for &v in d.variants[:d.variant_count] { save_field(c, &v.id); save_field(c, &v.variant) }
	save_run(c, &d.live); save_run(c, &d.restart)
	save_count(c, &d.gate_count, len(d.gates))
	for i in 0..<d.gate_count {
		for gate in ([2]^Gate_State{&d.gates[i], &d.restart_gates[i]}) {
			save_field(c, &gate.id); save_field(c, &gate.open); save_field(c, &gate.amount)
		}
	}
}

save_player :: proc(c: ^Save_Cursor, v: ^Player) {
	save_field(c, &v.position)
	save_field(c, &v.velocity)
	save_field(c, &v.yaw)
	save_field(c, &v.pitch)
	save_field(c, &v.health)
	save_field(c, &v.grounded)
	save_field(c, &v.gliding)
	save_field(c, &v.in_current)
	save_field(c, &v.glide_ready)
	save_field(c, &v.coyote)
	save_field(c, &v.jump_buffer)
	save_field(c, &v.dash_cooldown)
	save_field(c, &v.dash_time)
	save_field(c, &v.invulnerable)
	save_field(c, &v.shot_cooldown)
	save_field(c, &v.recoil)
	save_field(c, &v.hit_marker)
	save_field(c, &v.hurt_time)
	save_field(c, &v.hurt_strength)
	save_field(c, &v.gait_phase)
	save_field(c, &v.land_time)
	save_field(c, &v.land_strength)
	save_field(c, &v.idle_time)
	save_field(c, &v.air_time)
	save_field(c, &v.glide_blend)
	save_field(c, &v.weapon_bloom)
	save_field(c, &v.scope_time)
	save_field(c, &v.kick_time)
	save_field(c, &v.kick_cooldown)
	save_field(c, &v.switch_time)
	save_field(c, &v.fragment_cooldown)
	save_field(c, &v.weapon)
	save_field(c, &v.fragment_ammo)
	save_field(c, &v.fragment_unlocked)
	save_field(c, &v.shotgun_ammo); save_field(c, &v.shotgun_unlocked); save_field(c, &v.shotgun_cooldown)
}

save_enemy :: proc(c: ^Save_Cursor, v: ^Enemy) {
	save_field(c, &v.content_id)
	save_field(c, &v.anchor)
	save_field(c, &v.position)
	save_field(c, &v.velocity)
	save_field(c, &v.facing)
	save_field(c, &v.attack_direction)
	save_field(c, &v.knockback)
	save_field(c, &v.last_known)
	save_field(c, &v.known_velocity)
	save_field(c, &v.nav_goal)
	save_field(c, &v.separation)
	save_field(c, &v.attack_target)
	save_field(c, &v.health)
	save_field(c, &v.fire_timer)
	save_field(c, &v.flash)
	save_field(c, &v.sight_timer)
	save_field(c, &v.phase_time)
	save_field(c, &v.awareness)
	save_field(c, &v.memory_time)
	save_field(c, &v.nav_time)
	save_field(c, &v.gait_phase)
	save_field(c, &v.exposed)
	save_field(c, &v.support_time)
	save_field(c, &v.windup_duration)
	save_field(c, &v.generation)
	save_field(c, &v.heard_sequence)
	save_field(c, &v.kind)
	save_field(c, &v.phase)
	save_field(c, &v.rounds)
	save_field(c, &v.shield)
	save_field(c, &v.alerted)
	save_field(c, &v.sees_player)
	save_field(c, &v.gibbed)
}

save_projectile :: proc(c: ^Save_Cursor, v: ^Projectile) {
	save_field(c, &v.position)
	save_field(c, &v.velocity)
	save_field(c, &v.life)
	save_field(c, &v.source)
}

save_fragment :: proc(c: ^Save_Cursor, v: ^Fragment) {
	save_field(c, &v.position)
	save_field(c, &v.velocity)
	save_field(c, &v.life)
}

save_hazard :: proc(c: ^Save_Cursor, v: ^Floor_Hazard) {
	save_field(c, &v.position)
	save_field(c, &v.radius)
	save_field(c, &v.life)
	save_field(c, &v.warmup)
	save_field(c, &v.pulse)
}

save_particle :: proc(c: ^Save_Cursor, v: ^Particle) {
	save_field(c, &v.position)
	save_field(c, &v.velocity)
	save_field(c, &v.life)
	save_field(c, &v.max_life)
	save_field(c, &v.size)
	save_field(c, &v.kind)
}

save_flash :: proc(c: ^Save_Cursor, v: ^Light_Flash) {
	save_field(c, &v.position)
	save_field(c, &v.color)
	save_field(c, &v.radius)
	save_field(c, &v.strength)
	save_field(c, &v.life)
	save_field(c, &v.max_life)
}

save_pickup :: proc(c: ^Save_Cursor, v: ^Pickup) {
	save_field(c, &v.id)
	save_field(c, &v.position)
	save_field(c, &v.kind)
	save_field(c, &v.amount)
	save_field(c, &v.collected)
}

save_noise :: proc(c: ^Save_Cursor, v: ^Player_Noise) {
	save_field(c, &v.position)
	save_field(c, &v.radius)
	save_field(c, &v.life)
	save_field(c, &v.sequence)
}

save_run :: #force_no_inline proc(c: ^Save_Cursor, saved: ^Saved_Run) {
	r := &saved.state
	save_field(c, &r.hero)
	save_field(c, &r.difficulty)
	save_field(c, &r.campaign.seed); save_field(c, &r.campaign.current); save_field(c, &r.campaign.completed)
	save_field(c, &r.checkpoint_id)
	save_player(c, &r.player); save_noise(c, &r.player_noise)
	save_boss(c, &r.boss); save_anvil(c, &r.anvil)
	save_count(c, &r.core_count, len(r.cores))
	for &v, i in r.cores[:r.core_count] {
		id := core_object_id(i)
		save_field(c, &id)
		if id != core_object_id(i) { c.error = .Content }
		save_field(c, &v.position); save_field(c, &v.collected)
	}
	save_count(c, &r.pickup_count, len(r.pickups))
	for &v in r.pickups[:r.pickup_count] { save_pickup(c, &v) }
	save_count(c, &r.secret_count, len(r.secrets))
	for &v in r.secrets[:r.secret_count] { save_field(c, &v) }
	save_count(c, &r.enemy_count, len(r.enemies))
	for &v, i in r.enemies[:r.enemy_count] {
		save_enemy(c, &v)
		save_field(c, &saved.support_targets[i]); save_field(c, &saved.encounter_rooms[i])
	}
	save_field(c, &r.sound_sequence)
	save_field(c, &r.pickup_sequence)
	save_field(c, &r.enemy_total)
	save_field(c, &r.lift_started)
	save_field(c, &r.next_enemy_generation)
	save_field(c, &r.fragments_refused)
	save_field(c, &r.hazards_refused)
	save_field(c, &r.flash_cursor)
	save_field(c, &r.particle_cursor)
	save_field(c, &r.projectile_cursor)
	save_field(c, &r.trace_cursor)
	save_field(c, &r.projectiles_refused)
	save_field(c, &r.checkpoint)
	save_field(c, &r.time)
	save_field(c, &r.collected)
	save_field(c, &r.kills)
	save_field(c, &r.deaths)
	save_field(c, &r.shot_sequence)
	save_field(c, &r.damage_sequence)
	save_field(c, &r.kill_sequence)
	save_field(c, &r.jump_sequence)
	save_field(c, &r.land_sequence)
	save_field(c, &r.step_sequence)
	save_field(c, &r.glide_sequence)
	save_field(c, &r.rng)
	save_field(c, &r.effect_rng)
	save_field(c, &r.weapon_rng)
	save_field(c, &r.won)
	save_field(c, &r.focused)
	save_field(c, &r.message)
	save_field(c, &r.message_time)
	for &v in r.projectiles { save_projectile(c, &v) }
	for &v in r.fragments { save_fragment(c, &v) }
	for &v in r.hazards { save_hazard(c, &v) }
	for &v in r.particles { save_particle(c, &v) }
	for &v in r.flashes { save_flash(c, &v) }
	for &v in r.traces { save_field(c, &v.start); save_field(c, &v.end); save_field(c, &v.life) }
	save_field(c, &r.gib_cursor)
	for &v in r.gibs { save_particle(c, &v) }
}

save_boss :: proc(c: ^Save_Cursor, b: ^Boss_State) {
	save_field(c, &b.id); save_field(c, &b.phase)
	save_field(c, &b.health); save_field(c, &b.stage); save_field(c, &b.cycle)
	save_field(c, &b.timer); save_field(c, &b.duration); save_field(c, &b.flash)
	save_count(c, &b.lane_count, len(b.lanes)); save_field(c, &b.pass)
	for &lane in b.lanes { save_field(c, &lane.a); save_field(c, &lane.b); save_field(c, &lane.width) }
	save_field(c, &b.aim)
}

save_anvil :: proc(c: ^Save_Cursor, a: ^Anvil_State) {
	save_field(c, &a.phase); save_field(c, &a.target); save_field(c, &a.position)
	save_field(c, &a.timer); save_field(c, &a.speed); save_field(c, &a.struck)
}
