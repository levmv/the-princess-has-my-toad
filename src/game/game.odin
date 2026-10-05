package game

update :: proc(g: ^State, input: Input, dt: f32) {
	if g.won { return }
	g.in_step = true
	defer {
		g.in_step = false
		// A solved mechanism or reached checkpoint commits even if a projectile
		// kills the player later in this same tick. The restart copy sanitizes
		// health and transients before the deferred respawn uses it.
		if g.checkpoint_pending { capture_checkpoint(g) }
		if g.respawn_pending { respawn(g) }
		boss_exit_sync(g)
	}
	if input.has_look { g.player.yaw, g.player.pitch = input.look.x, clamp(input.look.y, -1.2, 1.15) }
	g.focused = input.focus
	g.time += dt
	g.message_time = max(0, g.message_time-dt)
	update_player(g, input, dt)
	if g.respawn_pending { return }
	update_mission(g)
	update_gates(g, input, dt)
	update_secrets(g)
	update_combat(g, input, dt)
	if g.respawn_pending { return }
	update_pickups(g)
	update_gibs(g, dt)
	for &flash in g.flashes { flash.life = max(0, flash.life-dt) }
	for &particle in g.particles {
		if particle.life <= 0 { continue }
		particle.life -= dt
		if particle.kind >= 5 {
			particle.velocity *= max(0, 1-dt*2)
			particle.velocity.y += 3*dt
		} else { particle.velocity.y -= 9*dt }
		particle.position += particle.velocity*dt
	}
	for &trace in g.traces { trace.life = max(0, trace.life-dt) }
	for &core, i in g.cores[:g.core_count] {
		if !core.collected && length(g.player.position+Vec3{0, 0.9, 0}-core.position) < 1.55 {
			core.collected = true
			g.collected += 1
			g.checkpoint = core.position-Vec3{0, 0.85, 0}
			g.checkpoint_id = core_object_id(i)
			g.player.health = min(100, g.player.health+30)
			emit(g, core.position, 45, 1)
			g.message = 3 if g.collected < g.core_count else 4
			g.message_time = 4
			checkpoint_changed(g)
		}
	}
	if exit_ready(g.world, g.collected, g.core_count, g.lift_started, g.boss) && length(g.player.position-g.world.exit) < 2.4 {
		g.won = true
		campaign_mark_complete(g)
	}
}
