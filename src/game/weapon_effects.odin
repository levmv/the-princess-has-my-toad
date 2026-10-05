package game

gib_enemy :: proc(g: ^State, e: ^Enemy) {
	if e.health > 0 || e.gibbed || !enemy_organic(e.kind) { return }
	e.gibbed = true
	for i in 0..<12 {
		part := &g.gibs[g.gib_cursor]
		g.gib_cursor = (g.gib_cursor+1)%len(g.gibs)
		velocity := Vec3{random_stream(&g.effect_rng)*2-1, random_stream(&g.effect_rng)*1.5, random_stream(&g.effect_rng)*2-1}*8
		life := 6+random_stream(&g.effect_rng)*3
		part^ = {e.position, e.velocity*0.65+velocity, life, life, 0.12+random_stream(&g.effect_rng)*0.12, 2 if i == 0 && !rabbit_kind(e.kind) else (1 if i%4 == 0 else 0)}
	}
	emit(g, e.position, 32, 3)
	sound_event(g, .GibImpact, e.position)
}

// A separate fixed pool keeps brass/sparks from immediately replacing flesh.
// Small swept boxes bounce against the same solids as the player and bullets.
update_gibs :: proc(g: ^State, dt: f32) {
	for &p in g.gibs {
		if p.life <= 0 { continue }
		p.life = max(0, p.life-dt)
		if p.velocity == (Vec3{}) { continue }
		p.velocity.y -= 20*dt
		delta := p.velocity*dt
		extent := Vec3{p.size, p.size, p.size}*0.5
		fraction, normal := world_sweep(g.world, p.position, delta, extent)
		p.position += delta*max(0, fraction-CONTACT_MARGIN/max(length(delta), CONTACT_MARGIN))
		if fraction < 1 {
			p.velocity = (p.velocity-normal*dot(p.velocity, normal)*1.25)*0.48
			if normal.y > 0.6 && length(p.velocity) < 1.5 { p.velocity = {} }
		}
		if p.position.y < -30 { p.life = 0 }
	}
}

fragment_blast_effects :: proc(g: ^State, point: Vec3) {
	for i in 0..<54 {
		p := &g.particles[g.particle_cursor%len(g.particles)]
		g.particle_cursor += 1
		kind := 6 if i < 12 else (5 if i < 30 else 0)
		life := (0.30 if kind == 6 else (1.2 if kind == 5 else f32(0.55)))+random_stream(&g.effect_rng)*0.35
		direction := normalized(Vec3{random_stream(&g.effect_rng)*2-1, random_stream(&g.effect_rng)*2-1, random_stream(&g.effect_rng)*2-1})
		speed := f32(7 if kind == 6 else (3 if kind == 5 else 22))
		size := 0.4+random_stream(&g.effect_rng)*0.4 if kind >= 5 else f32(0.045)
		p^ = {point+direction*0.14, direction*speed, life, life, size, kind}
	}
}
