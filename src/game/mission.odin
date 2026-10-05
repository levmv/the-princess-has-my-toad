package game

exit_ready :: proc(w: ^World, collected, core_count: int, started: bool, boss: Boss_State = {}) -> bool {
	if w.kind == .Arena { return collected == core_count }
	return (w.sector.exit_rule == .Reach || started) && boss_defeated(w, boss)
}

mission_checkpoint :: proc(g: ^State, stage: u8, position: Vec3) {
	if g.mission_checkpoint >= stage { return }
	g.mission_checkpoint = stage
	if int(stage) <= g.world.checkpoint_count { g.checkpoint_id = g.world.checkpoints[stage-1].id }
	g.checkpoint = position
	g.player.health = min(100, g.player.health+30)
	g.message_time = 0
	checkpoint_changed(g)
}

update_mission :: proc(g: ^State) {
	if g.world.kind != .RAM { return }
	for c, i in g.world.checkpoints[:g.world.checkpoint_count] {
		if length(g.player.position-c.position) < c.radius { mission_checkpoint(g, u8(i+1), c.position) }
	}
}
