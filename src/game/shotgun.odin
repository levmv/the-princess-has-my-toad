package game

import "core:math"

SHOTGUN_CORE_PELLETS :: 8

// A dense core preserves close lethality; the broad skirt catches near misses.
// Rotate the pattern per shot; independent random pellets left large empty gaps.
shotgun_direction :: proc(g: ^State, aim: Vec3, pellet: int, rotation: f32) -> Vec3 {
	core := pellet < SHOTGUN_CORE_PELLETS
	index, count := pellet if core else pellet-SHOTGUN_CORE_PELLETS, SHOTGUN_CORE_PELLETS if core else SHOTGUN_PELLETS-SHOTGUN_CORE_PELLETS
	t := (f32(index)+0.3+random_stream(&g.weapon_rng)*0.4)/f32(count)
	inner, outer := f32(0), f32(0.024)
	if !core { inner, outer = 0.035, 0.18 }
	radius := outer*math.sqrt(t) if core else inner+t*(outer-inner)
	angle := rotation+f32(pellet)*2.39996323
	right := normalized(cross(aim, Vec3{0, 1, 0}))
	up := cross(right, aim)
	return normalized(aim+right*(math.cos(angle)*radius)+up*(math.sin(angle)*radius*(1 if core else f32(0.85))))
}

// Resolve the entire pattern before applying damage. A pellet that kills a
// fairy must not let later pellets pass through its disappearing hit volume.
fire_shotgun :: proc(g: ^State, focused: bool) -> bool {
	p := &g.player
	if !p.shotgun_unlocked || p.shotgun_ammo <= 0 { return false }
	muzzle := weapon_muzzle(g)
	cam := camera(g, focused)
	rotation := random_stream(&g.weapon_rng)*2*math.PI
	body, weak: [ENEMY_CAPACITY]int
	armour: [ENEMY_CAPACITY]bool
	points: [ENEMY_CAPACITY]Vec3
	boss_damage := 0
	boss_point: Vec3
	button_hit := false
	for pellet in 0..<SHOTGUN_PELLETS {
		// Converge every pellet separately, as the repeater does its single ray.
		// A near miss by the crosshair must not send the whole cone at the distant
		// backdrop and below a close target in the elevated third-person camera.
		pellet_cam := cam
		pellet_cam.forward = shotgun_direction(g, cam.forward, pellet, rotation)
		direction := normalized(aim_point(g, pellet_cam)-muzzle)
		amount := 2 if pellet < SHOTGUN_CORE_PELLETS else 1
		distance := world_ray(g, muzzle, direction, 55)
		button_distance, button := lift_button_hit(g.world, muzzle, direction, distance)
		if button { distance = button_distance }
		victim, zone := -1, Hit_Zone.None
		for e, i in g.enemies[:g.enemy_count] {
			if !enemy_active(e) { continue }
			t, part := enemy_hit(e, muzzle, direction, distance)
			if part != .None { distance, victim, zone, button = t, i, part, false }
		}
		t, part := boss_hit(g.world, g.boss, muzzle, direction, distance)
		if part != .None { distance, victim, button = t, -1, false }
		end := muzzle+direction*distance
		if button { button_hit = true
		} else if part != .None { boss_damage += amount; boss_point = end
		} else if victim >= 0 {
			points[victim] = end
			switch zone {
			case .Weak: weak[victim] += amount
			case .Body: body[victim] += amount
			case .Armour: armour[victim] = true; emit(g, end, 3, 2)
			case .None:
			}
		} else if distance < 55 { emit(g, end, 3, 2) }
	}
	for &e, i in g.enemies[:g.enemy_count] {
		if armour[i] { damage_enemy(g, i, 1, .Armour, points[i]) }
		potential := weak[i]*3+body[i]
		if potential == 0 { continue }
		old_knockback := e.knockback
		impulse := normalized(e.position-muzzle)*min(18, f32(potential)*1.8)+Vec3{0, 2.5, 0}
		e.knockback += impulse
		dismember := length(e.position-muzzle) < 13 && potential >= 6
		dealt := 0
		for zone in ([2]Hit_Zone{.Weak, .Body}) {
			amount := weak[i] if zone == .Weak else body[i]
			if amount == 0 { continue }
			dealt += damage_enemy(g, i, amount, zone, points[i], dismember = dismember)
		}
		if dealt == 0 { e.knockback = old_knockback; continue }
		if e.health > 0 {
			e.knockback = old_knockback+impulse*(f32(dealt)/f32(potential))
			if dealt >= 4 {
				// A body stagger must not shorten the critical hit's interruption
				// above, or wake an enemy already recovering from a missed attack.
				e.phase_time = max(0.32, e.phase_time if e.phase == .Recover else 0)
				e.phase, e.shield = .Recover, 0
			}
		}
	}
	if boss_damage > 0 { damage_boss(g, min(18, boss_damage), boss_point) }
	if button_hit { start_lift(g) }
	p.shotgun_ammo -= 1
	p.recoil = 1
	player_noise(g, muzzle, 72)
	light_flash(g, muzzle, {1, 0.65, 0.25}, 7, 4, 0.09)
	sound_event(g, .ShotgunFire, muzzle)
	return true
}
