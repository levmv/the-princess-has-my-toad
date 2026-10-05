package game

// The forgiving hit volume is larger than the movement box. Its extra margin
// must not stick through a wall or ceiling when the player hugs thin cover.
player_hit_visible :: proc(w: ^World, feet, impact: Vec3) -> bool {
	relative := impact-feet
	nearest := feet+Vec3{clamp(relative.x, -PLAYER_RADIUS, PLAYER_RADIUS), clamp(relative.y, 0, PLAYER_HEIGHT), clamp(relative.z, -PLAYER_RADIUS, PLAYER_RADIUS)}
	delta := nearest-impact
	distance := length(delta)
	return distance < 0.00001 || world_ray(w, impact, delta/distance, distance) >= distance
}

// Sweep the same forgiving hit box used by the old point test. Compare both
// intersections along the segment so cover behind the player cannot eat a hit.
update_projectiles :: proc(g: ^State, dt: f32) {
	if dt <= 0 { return }
	body := Block{center = g.player.position+Vec3{0, PLAYER_HEIGHT*0.5, 0}, size = {1.1, PLAYER_HEIGHT+0.3, 1.1}}
	physical := Block{center = body.center, size = {PLAYER_RADIUS*2, PLAYER_HEIGHT, PLAYER_RADIUS*2}}
	for &bullet in g.projectiles {
		if bullet.life <= 0 { continue }
		delta := bullet.velocity*min(dt, bullet.life)
		bullet.life = max(0, bullet.life-dt)
		distance := length(delta)
		direction := normalized(delta)
		travel := world_ray(g, bullet.position, direction, distance)
		impact, hit := ray_box(bullet.position, direction, body, travel)
		if hit && !player_hit_visible(g.world, g.player.position, bullet.position+direction*impact) {
			// A corner may hide the margin while the ray itself clears the edge
			// and enters the real body later. Keep that unobstructed hit.
			impact, hit = ray_box(bullet.position, direction, physical, travel)
		}
		if hit && (impact < travel || travel == distance) {
			bullet.position += direction*impact
			bullet.life = 0
			deaths := g.deaths
			damage(g, 15*difficulty_profile(g.difficulty).damage, bullet.source)
			if g.respawn_pending || g.deaths != deaths { return }
		} else {
			bullet.position += direction*travel
			if travel < distance { bullet.life = 0; emit(g, bullet.position, 4, 0) }
		}
	}
}
