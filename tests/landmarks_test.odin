package tests

import "core:testing"
import "core:mem"
import game "../src/game"

@(test)
landing_guard_stays_on_its_column_and_the_reward_can_be_bypassed :: proc(t: ^testing.T) {
	w: game.World
	game.world_init_ram(&w)
	defer game.world_destroy(&w)
	s := w.sector.sections[game.room_index(&w.sector, 1011)]
	g := game.State{world = &w, difficulty = .Nightmare}
	game.init(&g)
	guard := -1
	for &e, i in g.enemies[:g.enemy_count] {
		if w.encounters[e.encounter-1].room == 1011 && e.kind == .Crab { guard = i
		} else { e.health = 0 }
	}
	if !testing.expect(t, guard >= 0) { return }
	e := &g.enemies[guard]
	initial := e.position
	g.player.invulnerable = 1000
	// Looking at the preceding landing must not walk the guard off its perch.
	g.player.position = s.origin+game.CHARGE_LANDINGS[2]+game.Vec3{0, 0.04, 0}
	e.alerted, e.memory_time, e.last_known = true, 100, g.player.position
	{
		context.allocator, context.temp_allocator = mem.panic_allocator(), mem.panic_allocator()
		for _ in 0..<2400 { game.update_enemies(&g, game.STEP) }
	}
	testing.expectf(t, e.position.y >= initial.y-0.1, "Guard walked off its landing: %v", e.position)
	// A committed charge towards the same empty space must brake too.
	e.position = initial
	e.phase, e.phase_time, e.attack_direction = .Attack, 0.5, {0, 0, 1}
	for _ in 0..<90 { game.update_enemies(&g, game.STEP) }
	testing.expect(t, e.position.y >= initial.y-0.1 && e.phase != .Attack)
	g.player.position, g.player.velocity = s.origin+game.CHARGE_LANDINGS[2]+game.Vec3{0, 0.04, 0}, {}
	for _ in 0..<60 { game.update(&g, {}, game.STEP) }
	wings := g.glide_sequence
	testing.expectf(t, fly_to(&g, s.origin+game.CHARGE_LANDINGS[4]), "Guard bypass failed at %v", g.player.position)
	testing.expect(t, g.deaths == 0 && g.glide_sequence > wings && e.health > 0)
}

@(test)
cargo_hides_its_hunter_but_leaves_a_clear_walking_lane :: proc(t: ^testing.T) {
	w: game.World
	game.world_init_ram(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	s := w.sector.sections[game.room_index(&w.sector, 1014)]
	hunter: game.Vec3
	hunter_index := -1
	for &e, i in g.enemies[:g.enemy_count] {
		if w.encounters[e.encounter-1].room == 1014 && e.kind == .Crab { hunter, hunter_index = e.position, i }
		e.health = 0
	}
	testing.expect(t, hunter != game.Vec3{})
	eye := s.origin+game.Vec3{0, game.EYE_HEIGHT, 36}
	delta := hunter-eye
	testing.expect(t, game.world_ray(&w, eye, game.normalized(delta), game.length(delta)) < game.length(delta)-1)
	g.player.position = s.origin+game.Vec3{2, 0.04, 36}
	testing.expect(t, walk_to_grounded(&g, s.origin+game.Vec3{2, 0.04, -36}))
	testing.expect(t, g.deaths == 0 && g.jump_sequence == 0)
	if hunter_index < 0 { return }
	g.player.position, g.player.invulnerable = s.origin+game.Vec3{2, 0.04, 20}, 1000
	e := &g.enemies[hunter_index]
	e.health, e.alerted, e.memory_time, e.last_known = 24, true, 100, g.player.position
	for _ in 0..<1800 {
		game.update_enemies(&g, game.STEP)
		if game.length(e.position-g.player.position) < 5 { break }
	}
	testing.expectf(t, game.length(e.position-g.player.position) < 5, "Cargo hunter cannot leave its cover: %v", e.position)
}

@(test)
pony_monument_is_solid_cover_with_passable_flanks :: proc(t: ^testing.T) {
	w: game.World
	game.world_init_ram(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	for &e in g.enemies { e.health = 0 }
	s := w.sector.sections[game.room_index(&w.sector, 1015)]
	from := s.origin+game.Vec3{4, 1.5, 12}
	testing.expect(t, game.world_ray(&w, from, {0, 0, -1}, 25) < 15)
	for side in ([2]f32{-1, 1}) {
		g.player.position, g.player.velocity = s.origin+game.Vec3{4+side*9, 0.04, 13}, {}
		testing.expectf(t, walk_to_grounded(&g, s.origin+game.Vec3{4+side*9, 0.04, -14}), "Monument flank blocked: %v", g.player.position)
	}
}
