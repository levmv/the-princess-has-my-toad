package game

CRAB_RUSH_SPEED :: f32(26)

// The plate closes for a committed ground rush. A sidestep, jump or wall
// leaves the crab exposed; it never steers after the warning's final 200 ms.
update_crab_rush :: proc(g: ^State, e: ^Enemy, dt: f32) {
	profile := difficulty_profile(g.difficulty)
	speed := CRAB_RUSH_SPEED*profile.move
	// A landing guard brakes at the edge instead of chasing a glider into the
	// void. Knockback still goes through physical movement and can throw it off.
	blocked := !enemy_ground_supported(g.world, e, e.attack_direction*(enemy_extent(e.kind).x+speed*dt+0.15))
	if !blocked { blocked = move_enemy(g, e, e.attack_direction*speed+Vec3{0, e.velocity.y, 0}, dt) }
	delta := g.player.position+Vec3{0, 0.9, 0}-e.position
	in_arc := dot(normalized(Vec3{delta.x, 0, delta.z}), e.attack_direction) > 0.25
	hit := length(delta) < 3.2 && abs(delta.y) < 1.4 && in_arc && world_ray(g, e.position, normalized(delta), length(delta)) >= length(delta)-0.1
	if hit { damage(g, 26*profile.damage, .Crab) }
	if hit || blocked || e.phase_time <= 0 {
		e.phase, e.phase_time, e.exposed = .Recover, 0.9, 0.9
		e.velocity = {}
		if blocked { sound_event(g, .ClawSnap, e.position); emit(g, e.position+e.facing, 8, 2) }
	}
}
