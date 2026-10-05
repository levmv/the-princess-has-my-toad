package game

import "core:math"

Weapon :: enum u8 { Repeater = 0, Fragmentator = 1, Shotgun = 2 }
// Presentation order is independent of persistent weapon/input IDs.
@(rodata) WEAPON_ORDER := [3]Weapon{.Repeater, .Shotgun, .Fragmentator}
Fragment :: struct { position, velocity: Vec3, life: f32 }

weapon_owned :: proc(p: ^Player, weapon: Weapon) -> bool {
	switch weapon {
	case .Repeater: return true
	case .Fragmentator: return p.fragment_unlocked
	case .Shotgun: return p.shotgun_unlocked
	}
	return false
}

cycle_weapon :: proc(p: ^Player, direction: int) -> int {
	current := 0
	for weapon, i in WEAPON_ORDER { if weapon == p.weapon { current = i; break } }
	for step in 1..<4 {
		weapon := WEAPON_ORDER[(current+step*direction+6)%3]
		if weapon_owned(p, weapon) { return int(weapon)+1 }
	}
	return 0
}

equip_weapon :: proc(g: ^State, weapon: Weapon) {
	if weapon == g.player.weapon || !weapon_owned(&g.player, weapon) { return }
	g.player.weapon, g.player.switch_time = weapon, 0.16
	cue := Sound_Cue.EquipRepeater
	if weapon == .Shotgun { cue = .EquipShotgun }
	if weapon == .Fragmentator { cue = .EquipFragmentator }
	sound_event(g, cue, g.player.position+Vec3{0, 1.2, 0})
}

update_weapons :: proc(g: ^State, input: Input, dt: f32) {
	p := &g.player
	p.kick_cooldown = max(0, p.kick_cooldown-dt)
	p.switch_time = max(0, p.switch_time-dt)
	if input.weapon_select >= 1 && input.weapon_select <= 3 {
		selected := Weapon(input.weapon_select-1)
		equip_weapon(g, selected)
	}
	if input.kick_pressed && p.kick_cooldown <= 0 {
		p.kick_time, p.kick_cooldown, p.idle_time = KICK_DURATION, 0.55, 0
		sound_event(g, .KickSwing, p.position+Vec3{0, 0.8, 0})
	}
	before := p.kick_time
	p.kick_time = max(0, p.kick_time-dt)
	if before > 0.26 && p.kick_time <= 0.26 { kick(g) }
	// Retain the fractional tick remainder during automatic fire.
	p.shot_cooldown = max(0, p.shot_cooldown)-dt
	p.fragment_cooldown = max(0, p.fragment_cooldown)-dt
	p.shotgun_cooldown = max(0, p.shotgun_cooldown)-dt
	if !input.fire || p.switch_time > 0 { return }
	switch p.weapon {
	case .Repeater:
		if p.shot_cooldown > 0 { return }
		fire(g, input.focus)
		p.shot_cooldown += SHOT_INTERVAL
	case .Fragmentator:
		if p.fragment_cooldown > 0 { return }
		if fire_fragment(g, input.focus) { p.fragment_cooldown += FRAGMENT_INTERVAL
		} else {
			if p.fragment_ammo <= 0 { sound_event(g, .DryFire, p.position+Vec3{0, 1.28, 0}) }
			p.fragment_cooldown = 0.28
		}
	case .Shotgun:
		if p.shotgun_cooldown > 0 { return }
		if fire_shotgun(g, input.focus) { p.shotgun_cooldown += SHOTGUN_INTERVAL
		} else { sound_event(g, .DryFire, p.position+Vec3{0, 1.28, 0}); p.shotgun_cooldown = 0.28 }
	}
}

kick :: proc(g: ^State) {
	origin := g.player.position+Vec3{0, 0.85, 0}
	f := forward(g.player.yaw, 0)
	victim := -1
	best := f32(2.65)
	for e, i in g.enemies[:g.enemy_count] {
		if !enemy_active(e) { continue }
		delta := e.position-origin
		distance := length(delta)
		if distance >= best || abs(delta.y) > 1.35 || dot(normalized(Vec3{delta.x, 0, delta.z}), f) < 0.55 { continue }
		if world_ray(g, origin, normalized(delta), distance) < distance-0.05 { continue }
		best, victim = distance, i
	}
	if victim < 0 { return }
	e := &g.enemies[victim]
	// A physical shove opens the plate even from the armoured side. Its brief
	// stun is shorter than the kick cooldown, so it cannot lock a crowd forever.
	e.phase, e.phase_time, e.exposed, e.shield = .Recover, 0.4, 0.85, 0
	e.knockback = f*15+Vec3{0, 2.5, 0}
	damage_enemy(g, victim, 2, .Body, e.position, true)
	sound_event(g, .KickHit, e.position)
	player_noise(g, e.position, 12)
}

fragment_muzzle :: proc(g: ^State) -> Vec3 {
	return fragment_muzzle_pose(g.world, &g.player)
}

fragment_muzzle_pose :: proc(w: ^World, player: ^Player) -> Vec3 {
	origin := player.position+Vec3{0, 1.28, 0}
	arm := weapon_muzzle_pose(w, player)-origin
	// The larger projectile must start outside the expanded wall, even when
	// the narrow automatic barrel can sit closer to it.
	fraction, _ := world_sweep(w, origin, arm, {0.21, 0.21, 0.21})
	return origin+arm*max(0, fraction-0.02/max(0.02, length(arm)))
}

fire_fragment :: proc(g: ^State, focused: bool) -> bool {
	if !g.player.fragment_unlocked || g.player.fragment_ammo <= 0 { return false }
	index := -1
	for fragment, i in g.fragments { if fragment.life <= 0 { index = i; break } }
	if index < 0 { g.fragments_refused += 1; return false }
	muzzle := fragment_muzzle(g)
	direction := normalized(aim_point(g, camera(g, focused))-muzzle)
	g.fragments[index] = {muzzle, direction*FRAGMENT_SPEED, 3.5}
	g.player.fragment_ammo -= 1
	g.player.recoil = 1
	player_noise(g, muzzle, 44)
	sound_event(g, .FragmentFire, muzzle)
	light_flash(g, muzzle, {0.9, 0.65, 0.2}, 5, 3, 0.10)
	return true
}

explode_fragment :: proc(g: ^State, point: Vec3) {
	radius :: FRAGMENT_RADIUS
	light_flash(g, point, {1, 0.44, 0.08}, 17, 10, 0.55)
	sound_event(g, .FragmentBlast, point)
	player_noise(g, point, 48)
	fragment_blast_effects(g, point)
	for &e, i in g.enemies[:g.enemy_count] {
		if !enemy_active(e) { continue }
		delta := e.position-point
		distance := length(delta)
		if distance >= radius || world_ray(g, point, normalized(delta), distance) < distance-0.05 { continue }
		strength := 1-distance/radius
		e.knockback += normalized(delta)*(24*strength)+Vec3{0, 4*strength, 0}
		e.exposed = max(e.exposed, 0.65)
		damage_enemy(g, i, max(1, int(math.ceil(48*strength))), .Body, e.position, true, distance < 5.5)
	}
	if g.boss.id != 0 {
		core := boss_core(g.world)
		delta := core-point
		distance := length(delta)
		// The exposed collector core still takes two well placed shells; splash
		// on a closed shell cannot bypass the boss's vulnerability window.
		if distance < radius && world_ray(g.world, point, normalized(delta), distance) >= distance-0.05 { damage_boss(g, max(1, int(math.ceil(18*(1-distance/radius)))), core) }
	}
	delta := g.player.position+Vec3{0, 0.7, 0}-point
	distance := length(delta)
	if distance >= radius || world_ray(g, point, normalized(delta), distance) < distance-0.05 { return }
	strength := 1-distance/radius
	deaths := g.deaths
	damage(g, 40*strength, .Fragment)
	if g.respawn_pending || g.deaths != deaths { return }
	g.player.velocity += normalized(delta)*(26*strength)
	g.player.velocity.y = min(28, g.player.velocity.y)
	g.player.grounded, g.player.gliding = false, false
	g.player.glide_ready = true
}

update_fragments :: proc(g: ^State, dt: f32) {
	if dt <= 0 { return }
	for &fragment in g.fragments {
		if fragment.life <= 0 { continue }
		step := min(dt, fragment.life)
		fragment.life = max(0, fragment.life-dt)
		fragment.velocity.y -= GRAVITY*FRAGMENT_GRAVITY*step
		delta := fragment.velocity*step
		distance := length(delta)
		fraction, normal := world_sweep(g.world, fragment.position, delta, {0.14, 0.14, 0.14})
		direction := normalized(delta)
		travel := distance*fraction
		hit := fraction < 1
		button_distance, button := lift_button_hit(g.world, fragment.position, direction, travel)
		if button { travel, hit, normal = button_distance, true, -direction }
		for e in g.enemies[:g.enemy_count] {
			if !enemy_active(e) { continue }
			t, part := enemy_hit(e, fragment.position, direction, travel)
			if part != .None { travel, hit, normal, button = t, true, -direction, false }
		}
		t, part := boss_hit(g.world, g.boss, fragment.position, direction, travel)
		if part != .None { travel, hit, normal, button = t, true, -direction, false }
		fragment.position += direction*travel
		if button { start_lift(g) }
		if hit || fragment.life <= 0 {
			fragment.life = 0
			deaths := g.deaths
			explode_fragment(g, fragment.position+normal*0.04)
			if g.respawn_pending || g.deaths != deaths { return }
		}
	}
}
