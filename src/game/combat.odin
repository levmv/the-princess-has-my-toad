package game

import "core:math"

weapon_spread :: proc(p: ^Player, scoped: bool) -> f32 {
	motion := min(1, length(Vec3{p.velocity.x, 0, p.velocity.z})/RUN_SPEED)
	if scoped { return 0.0015+p.weapon_bloom*0.004+motion*0.007 }
	return 0.008+p.weapon_bloom*0.022+motion*0.010
}

spread_direction :: proc(g: ^State, direction: Vec3, spread: f32) -> Vec3 {
	radius := math.sqrt(random_stream(&g.weapon_rng))*spread
	angle := random_stream(&g.weapon_rng)*2*math.PI
	right := normalized(cross(direction, Vec3{0, 1, 0}))
	up := cross(right, direction)
	return normalized(direction+right*(math.cos(angle)*radius)+up*(math.sin(angle)*radius))
}

light_flash :: proc(g: ^State, position, color: Vec3, radius, strength, duration: f32) {
	index := g.flash_cursor%len(g.flashes)
	for i in 0..<len(g.flashes) {
		candidate := (g.flash_cursor+i)%len(g.flashes)
		if g.flashes[candidate].life <= 0 { index = candidate; break }
		if g.flashes[candidate].life*g.flashes[candidate].strength < g.flashes[index].life*g.flashes[index].strength { index = candidate }
	}
	g.flashes[index] = {position, color, radius, strength, duration, duration}
	g.flash_cursor = (index+1)%len(g.flashes)
}

emit :: proc(g: ^State, position: Vec3, count, kind: int) {
	for _ in 0..<count {
		i := g.particle_cursor % len(g.particles)
		g.particle_cursor += 1
		// Visual density must not consume the RNG used by enemy behaviour.
		life := 0.3+random_stream(&g.effect_rng)*0.6
		g.particles[i] = {position, { (random_stream(&g.effect_rng)-0.5)*8, random_stream(&g.effect_rng)*7, (random_stream(&g.effect_rng)-0.5)*8 }, life, life, 0.025+random_stream(&g.effect_rng)*0.1, kind}
	}
}

fire :: proc(g: ^State, focused: bool) {
	cam := camera(g, focused)
	aim := aim_point(g, cam)
	muzzle := weapon_muzzle(g)
	dir := normalized(aim-muzzle)
	// A uniform angular cone gives distance-dependent accuracy naturally.
	// Weapon randomness is separate from AI and visual effects.
	dir = spread_direction(g, dir, weapon_spread(&g.player, focused))
	g.player.weapon_bloom = min(1, g.player.weapon_bloom+0.13)
	distance := world_ray(g, muzzle, dir, 110)
	button_distance, button := lift_button_hit(g.world, muzzle, dir, distance)
	if button { distance = button_distance }
	victim := -1
	zone := Hit_Zone.None
	for enemy, i in g.enemies[:g.enemy_count] {
		if enemy.health <= 0 { continue }
		t, part := enemy_hit(enemy, muzzle, dir, distance)
		if part != .None { distance, victim, zone, button = t, i, part, false }
	}
	boss_distance, boss_zone := boss_hit(g.world, g.boss, muzzle, dir, distance)
	if boss_zone != .None { distance, victim, zone, button = boss_distance, -1, .None, false }
	end := muzzle+dir*distance
	light_flash(g, muzzle, {1, 0.72, 0.32}, 4.0, 2.5, 0.04)
	if distance < 109 { light_flash(g, end-dir*0.08, {1, 0.8, 0.45}, 2.0, 1.5, 0.07) }
	if button {
		start_lift(g)
	} else if boss_zone != .None {
		damage_boss(g, 3, end)
	} else if victim >= 0 {
		damage_enemy(g, victim, 1, zone, end)
	} else if distance < 109 {
		emit(g, end, 6, 2)
	}
	g.traces[g.trace_cursor % len(g.traces)] = {muzzle, end, 0.075}
	g.trace_cursor += 1
	g.player.recoil = 1
	g.shot_sequence += 1
	player_noise(g, muzzle, 72)
}

damage :: proc(g: ^State, amount: f32, source: Death_Cause = .Unknown) {
	if g.player.invulnerable > 0 || g.respawn_pending { return }
	g.player.health -= amount
	g.player.invulnerable, g.player.hurt_time = 0.35, 0.28
	g.player.hurt_strength = clamp(amount/35, 0.25, 1)
	g.damage_sequence += 1
	if g.player.health <= 0 { g.last_death = source; respawn(g) }
}

update_combat :: proc(g: ^State, input: Input, dt: f32) {
	update_weapons(g, input, dt)
	update_boss(g, dt)
	if g.respawn_pending { return }
	update_anvil(g, input, dt)
	if g.respawn_pending { return }
	update_enemies(g, dt)
	if g.respawn_pending { return }
	update_fragments(g, dt)
	if g.respawn_pending { return }
	update_floor_hazards(g, dt)
	if g.respawn_pending { return }
	update_projectiles(g, dt)
}
