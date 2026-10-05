package game

Enemy_Pose :: struct {
	position, facing, attack_target, support_position: Vec3,
	health: int,
	flash, phase_time, gait_phase, exposed, windup_duration: f32,
	kind: Enemy_Kind,
	phase: Enemy_Phase,
	shielding, gibbed: bool,
}

// Only poses are interpolated. World and effect buffers are borrowed for this frame.
Render_Snapshot :: struct {
	hero: Character,
	world: ^World,
	player: Player,
	boss: Boss_State,
	anvil: Anvil_State,
	enemies: [ENEMY_CAPACITY]Enemy_Pose,
	enemy_count: int,
	cores: []Core,
	pickups: []Pickup,
	core_count, collected: int,
	projectiles: []Projectile,
	fragments: []Fragment,
	hazards: []Floor_Hazard,
	particles: []Particle,
	gibs: []Particle,
	traces: []Trace,
	flashes: []Light_Flash,
	time: f32,
	lift_started, exit_open: bool,
}

Pose_History :: struct {
	player: Vec3,
	gait_phase, land_time, air_time, glide_blend: f32,
	enemies: [ENEMY_CAPACITY]Vec3,
	facing: [ENEMY_CAPACITY]Vec3,
	enemy_gait: [ENEMY_CAPACITY]f32,
	generations: [ENEMY_CAPACITY]u32,
	time: f32,
	boss: Boss_State,
	anvil: Anvil_State,
}

capture_poses :: proc(h: ^Pose_History, g: ^State) {
	h.player, h.time = g.player.position, g.time
	h.boss, h.anvil = g.boss, g.anvil
	h.gait_phase, h.land_time, h.air_time, h.glide_blend = g.player.gait_phase, g.player.land_time, g.player.air_time, g.player.glide_blend
	for e, i in g.enemies[:g.enemy_count] { h.enemies[i], h.generations[i], h.facing[i], h.enemy_gait[i] = e.position, e.generation, e.facing, e.gait_phase }
}

render_snapshot :: proc(v: ^Render_Snapshot, g: ^State, h: ^Pose_History, alpha: f32) {
	t := clamp(alpha, 0, 1)
	v.world, v.player, v.hero = g.world, g.player, g.hero
	v.boss, v.anvil = g.boss, g.anvil
	if g.boss.phase == h.boss.phase && g.boss.pass == h.boss.pass { v.boss.timer = h.boss.timer*(1-t)+g.boss.timer*t }
	if g.anvil.phase == h.anvil.phase { v.anvil.position = h.anvil.position*(1-t)+g.anvil.position*t }
	if length(g.player.position-h.player) <= 5 {
		v.player.position = h.player*(1-t)+g.player.position*t
		phase_delta := g.player.gait_phase-h.gait_phase
		if phase_delta < -3 { phase_delta += 6.2831853 }
		v.player.gait_phase = h.gait_phase+phase_delta*t
		v.player.glide_blend = h.glide_blend*(1-t)+g.player.glide_blend*t
		if g.player.land_time <= h.land_time { v.player.land_time = h.land_time*(1-t)+g.player.land_time*t }
		if !g.player.grounded { v.player.air_time = h.air_time*(1-t)+g.player.air_time*t }
	}
	v.time = h.time*(1-t)+g.time*t
	v.enemy_count = g.enemy_count
	for e, i in g.enemies[:g.enemy_count] {
		v.enemies[i] = Enemy_Pose{position = e.position, facing = e.facing, attack_target = e.attack_target, health = e.health, flash = e.flash, phase_time = e.phase_time, gait_phase = e.gait_phase, exposed = e.exposed, kind = e.kind, phase = e.phase}
		v.enemies[i].windup_duration = e.windup_duration
		v.enemies[i].gibbed = e.gibbed
		if e.kind == .Nanny && e.phase == .Attack && e.shield > 0 {
			partner := find_enemy(g, e.support)
			if partner != nil && nanny_link_clear(g.world, e.position, partner.position) {
				v.enemies[i].shielding, v.enemies[i].support_position = true, partner.position
			}
		}
		if e.generation == h.generations[i] && e.phase != .Hatching {
			v.enemies[i].position = h.enemies[i]*(1-t)+e.position*t
			v.enemies[i].facing = normalized(h.facing[i]*(1-t)+e.facing*t)
			delta := e.gait_phase-h.enemy_gait[i]
			if delta < -3 { delta += 6.2831853 }
			v.enemies[i].gait_phase = h.enemy_gait[i]+delta*t
		}
	}
	v.core_count, v.collected = g.core_count, g.collected
	v.cores = g.cores[:g.core_count]
	v.pickups = g.pickups[:g.pickup_count]
	v.projectiles, v.particles, v.traces, v.flashes = g.projectiles[:], g.particles[:], g.traces[:], g.flashes[:]
	v.hazards = g.hazards[:]
	v.fragments = g.fragments[:]
	v.gibs = g.gibs[:]
	v.lift_started = g.lift_started
	v.exit_open = exit_ready(g.world, g.collected, g.core_count, g.lift_started, g.boss)
}

camera_snapshot :: proc(g: ^Render_Snapshot, focus: bool = false) -> Camera { return camera_pose(g.world, &g.player, focus) }
aim_point_snapshot :: proc(g: ^Render_Snapshot, cam: Camera) -> Vec3 { return aim_point_pose(g.world, g.enemies[:g.enemy_count], cam, g.boss) }
weapon_muzzle_snapshot :: proc(g: ^Render_Snapshot) -> Vec3 { return weapon_muzzle_pose(g.world, &g.player) }
