package game

spawn_enemy :: proc(g: ^State, position: Vec3, health: int = 3, fire_delay: f32 = 0, kind: Enemy_Kind = .Sentry, encounter: int = 0, awareness: f32 = 80, content_id: Object_ID = 0) -> (Enemy_ID, bool) {
	assert(health > 0)
	for &enemy, i in g.enemies {
		if enemy.health > 0 { continue }
		g.next_enemy_generation += 1
		if g.next_enemy_generation == 0 { g.next_enemy_generation = 1 }
		enemy = Enemy{content_id = content_id, anchor = position, position = position, health = health, fire_timer = fire_delay, sight_timer = f32(i%12)*STEP, generation = g.next_enemy_generation, kind = kind, encounter = encounter, facing = {0, 0, 1}, awareness = awareness}
		g.enemy_count = max(g.enemy_count, i+1)
		g.enemy_total += 1
		return {u32(i), enemy.generation}, true
	}
	return {}, false
}

find_enemy :: proc(g: ^State, id: Enemy_ID) -> ^Enemy {
	if int(id.slot) >= g.enemy_count { return nil }
	e := &g.enemies[id.slot]
	return e if enemy_active(e^) && e.generation == id.generation else nil
}

spawn_projectile :: proc(g: ^State, projectile: Projectile) -> bool {
	for offset in 0..<len(g.projectiles) {
		index := (g.projectile_cursor+offset)%len(g.projectiles)
		if g.projectiles[index].life > 0 { continue }
		g.projectiles[index] = projectile
		g.projectile_cursor = (index+1)%len(g.projectiles)
		return true
	}
	// Refuse the new shot; a visible, live projectile must never disappear.
	g.projectiles_refused += 1
	return false
}
