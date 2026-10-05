package game

Difficulty :: enum u8 { Hard = 0, Brutal = 1, Nightmare = 2 }

Difficulty_Profile :: struct {
	move, windup, cooldown, projectile, damage: f32,
	health_bonus, health_pickup, ammo_pickup: int,
}

difficulty_profile :: proc(difficulty: Difficulty) -> Difficulty_Profile {
	switch difficulty {
	case .Hard: return {1, 1, 1, 1, 1, 0, 30, 6}
	case .Brutal: return {1.14, 0.88, 0.76, 1.20, 1.20, 3, 24, 5}
	case .Nightmare: return {1.30, 0.80, 0.52, 1.45, 1.50, 6, 18, 4}
	}
	unreachable()
}

difficulty_name :: proc(difficulty: Difficulty) -> string {
	switch difficulty {
	case .Hard: return "HARD"
	case .Brutal: return "BRUTAL"
	case .Nightmare: return "NIGHTMARE"
	}
	unreachable()
}

difficulty_by_name :: proc(name: string) -> (Difficulty, bool) {
	switch name {
	case "hard": return .Hard, true
	case "brutal": return .Brutal, true
	case "nightmare": return .Nightmare, true
	}
	return .Hard, false
}

begin_enemy_attack :: proc(g: ^State, e: ^Enemy) {
	e.windup_duration = enemy_windup(e.kind)*difficulty_profile(g.difficulty).windup
	e.phase, e.phase_time = .Windup, e.windup_duration
	enemy_warning(g, e)
}

enemy_charge :: proc(e: $E) -> f32 {
	if e.phase != .Windup { return 0 }
	duration := e.windup_duration if e.windup_duration > 0 else enemy_windup(e.kind)
	return clamp(1-e.phase_time/duration, 0, 1)
}

encounter_kind :: proc(w: ^World, room: Room_ID, slot: int, kind: Enemy_Kind, difficulty: Difficulty) -> Enemy_Kind {
	index := room_index(&w.sector, room)
	if index < 0 || difficulty == .Hard { return kind }
	population := w.sector.sections[index].population
	// Authored variants keep the same ID/position and flying clearance. They
	// put a pursuer in ranged galleries and add pressure to Nightmare courts.
	if kind == .Sentry {
		if population == .Sparse_Sentries && slot == 2 { return .Interceptor }
		if difficulty == .Nightmare && population == .Mixed_Patrol && slot == 5 { return .Interceptor }
	}
	return kind
}
