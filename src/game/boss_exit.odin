package game

BOSS_EXIT_OPEN_TIME :: f32(1.4)

// This collision pose is derived from the saved boss death timer. It never
// becomes a second independently saved piece of progression.
boss_exit_sync :: proc(g: ^State) {
	g.world.boss_exit_amount = 0
	if g.boss.id != 0 && g.boss.phase == .Dead {
		g.world.boss_exit_amount = clamp((BOSS_DEATH_DURATION-g.boss.timer)/BOSS_EXIT_OPEN_TIME, 0, 1)
	}
}

boss_exit_present :: proc(w: ^World) -> bool { return w.sector.boss.id != 0 && w.boss_exit.size.y > 0 }

boss_exit_shape :: proc(w: ^World) -> Block {
	b := w.boss_exit
	b.center.y += (b.size.y+0.3)*w.boss_exit_amount
	return b
}
