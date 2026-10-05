package game

Boss_Def :: struct { id: Object_ID, at: Location_Def }
Boss_Phase :: enum u8 { Dormant = 0, Mark = 1, Sweep = 2, Exposed = 3, Stagger = 4, Dead = 5 }
Sweep_Lane :: struct { a, b: Vec3, width: f32 }
Boss_State :: struct {
	id: Object_ID,
	phase: Boss_Phase,
	health, stage: int,
	cycle: u32,
	timer, duration, flash: f32,
	lanes: [3]Sweep_Lane,
	lane_count, pass: int,
	aim: Vec3,
}

BOSS_HEALTH :: 36
BOSS_DEATH_DURATION :: f32(3)
BOSS_BRUSH_HEIGHT :: f32(1.25)

boss_origin :: proc(w: ^World) -> Vec3 {
	p, _ := resolve_location(&w.sector, w.sector.boss.at)
	return p
}

boss_room_origin :: proc(w: ^World) -> Vec3 {
	i := room_index(&w.sector, w.sector.boss.at.room)
	return w.sector.sections[i].origin if i >= 0 else Vec3{}
}

boss_core :: proc(w: ^World) -> Vec3 { return boss_origin(w)+Vec3{0, 4, 3.0} }
boss_open :: proc(b: $B) -> bool { return b.phase == .Exposed && b.timer <= b.duration-0.18 }
boss_defeated :: proc(w: ^World, b: Boss_State) -> bool { return w.sector.boss.id == 0 || (b.id == w.sector.boss.id && b.phase == .Dead) }

boss_hit :: proc(w: ^World, b: Boss_State, origin, direction: Vec3, limit: f32) -> (f32, Hit_Zone) {
	if b.id == 0 || b.phase == .Dead { return limit, .None }
	distance, hit := ray_sphere(origin, direction, boss_core(w), 0.65, limit)
	return distance, (.Weak if boss_open(b) else .Armour) if hit else .None
}

boss_phase :: proc(b: ^Boss_State, phase: Boss_Phase, duration: f32) {
	b.phase, b.timer, b.duration = phase, duration, duration
}

boss_mark :: proc(g: ^State, first: bool) {
	b := &g.boss
	duration := f32(1.45)-f32(int(g.difficulty))*0.15 if first else f32(1.0)-f32(int(g.difficulty))*0.10
	boss_phase(b, .Mark, duration)
	b.aim = g.player.position+Vec3{0, 0.8, 0}
	sound_event(g, .GCMark, (b.lanes[b.pass].a+b.lanes[b.pass].b)*0.5)
}

// Plans are frozen when painted. No invisible tracking after the warning.
// Stage 1 sweeps one strip, stage 2 crosses two, stage 3 combs three strips
// and fires a slow committed volley, including at elevated hiding places.
boss_plan :: proc(g: ^State) {
	b := &g.boss
	c := boss_room_origin(g.world)
	p := g.player.position-c
	x_axis := b.cycle%2 == 0
	b.cycle += 1
	b.lane_count, b.pass = b.stage+1, 0
	for i in 0..<b.lane_count {
		axis := !x_axis if b.stage == 1 && i == 1 else x_axis
		coordinate := p.z if axis else p.x
		if b.stage == 2 { coordinate = clamp(coordinate, -11, 11)+f32(0 if i == 0 else (6 if i == 1 else -6)) }
		coordinate = clamp(coordinate, -18, 18)
		a, z := Vec3{-19, 0.16, coordinate}, Vec3{19, 0.16, coordinate}
		if !axis { a, z = {coordinate, 0.16, 19}, {coordinate, 0.16, -19} }
		if b.cycle%2 == 0 { a, z = z, a }
		b.lanes[i] = {c+a, c+z, 3.8 if b.stage < 2 else 3.0}
	}
	boss_mark(g, true)
}

boss_brush_position :: proc(b: $B) -> Vec3 {
	if b.lane_count <= 0 { return {} }
	lane := b.lanes[b.pass]
	t := clamp(1-b.timer/max(0.001, b.duration), 0, 1) if b.phase == .Sweep else f32(0)
	return lane.a+(lane.b-lane.a)*t
}

boss_brush_contact :: proc(g: ^State, from, to: Vec3, lane: Sweep_Lane) {
	p := &g.player
	if p.position.y >= lane.a.y+BOSS_BRUSH_HEIGHT || p.position.y+PLAYER_HEIGHT <= lane.a.y { return }
	axis := normalized(lane.b-lane.a)
	right := cross(axis, Vec3{0, 1, 0})
	delta := p.position+Vec3{0, 0.7, 0}-(from+to)*0.5
	if abs(dot(delta, axis)) > length(to-from)*0.5+0.70+PLAYER_RADIUS || abs(dot(delta, right)) > lane.width*0.5+PLAYER_RADIUS { return }
	// A platform or solid body protects the player; the brush cannot hurt
	// through it. The moving contact covers the full tick, including fast sweeps.
	source := from+Vec3{0, 0.65, 0}
	line := p.position+Vec3{0, 0.7, 0}-source
	if world_ray(g.world, source, normalized(line), length(line)) < length(line)-0.05 { return }
	if p.invulnerable > 0 { return }
	damage(g, 28*difficulty_profile(g.difficulty).damage, .GC)
	if !g.respawn_pending { p.velocity += axis*11+Vec3{0, 5, 0}; p.grounded = false }
}

boss_volley :: proc(g: ^State) {
	from := boss_core(g.world)+Vec3{0, 0.2, 0.2}
	direction := normalized(g.boss.aim-from)
	right := normalized(cross(direction, Vec3{0, 1, 0}))
	for i in -1..=1 { spawn_projectile(g, {from, normalized(direction+right*f32(i)*0.10)*(21+f32(int(g.difficulty))*2), 4, .GC}) }
	sound_event(g, .GCSweep, from)
	light_flash(g, from, {1, 0.25, 0.05}, 10, 5, 0.15)
}

update_boss :: proc(g: ^State, dt: f32) {
	b := &g.boss
	if b.id == 0 { return }
	b.flash = max(0, b.flash-dt)
	if b.phase == .Dead { b.timer = max(0, b.timer-dt); return }
	room := room_at(&g.world.sector, g.player.position)
	if room < 0 || g.world.sector.sections[room].id != g.world.sector.boss.at.room {
		// Retreat is possible. Returning starts a new readable warning, with
		// already inflicted damage retained; death restores the pre-fight copy.
		boss_phase(b, .Dormant, 0)
		return
	}
	if b.phase == .Dormant {
		if g.player.position.z-boss_room_origin(g.world).z > 18 { return }
		// Flying over the positional checkpoint must not turn a boss retry into
		// a long run back through the previous bank. Commit the authored entry.
		for checkpoint, i in g.world.checkpoints[:g.world.checkpoint_count] {
			if Room_ID(u32(checkpoint.id)>>16) == g.world.sector.boss.at.room { mission_checkpoint(g, u8(i+1), checkpoint.position); break }
		}
		boss_plan(g)
		return
	}
	before := boss_brush_position(b^)
	b.timer = max(0, b.timer-dt)
	switch b.phase {
	case .Mark:
		if b.timer > 0.25 { b.aim = g.player.position+Vec3{0, 0.8, 0} }
		if b.timer <= 0 {
			lane := b.lanes[b.pass]
			boss_phase(b, .Sweep, length(lane.b-lane.a)/(20+f32(int(g.difficulty))*3))
			sound_event(g, .GCSweep, lane.a)
			if b.stage == 2 { boss_volley(g) }
		}
	case .Sweep:
		boss_brush_contact(g, before, boss_brush_position(b^), b.lanes[b.pass])
		if g.respawn_pending { return }
		if b.timer <= 0 {
			b.pass += 1
			if b.pass < b.lane_count { boss_mark(g, false)
			} else {
				b.pass = b.lane_count-1
				boss_phase(b, .Exposed, 2.8-f32(int(g.difficulty))*0.3)
				sound_event(g, .GCOpen, boss_core(g.world))
			}
		}
	case .Exposed, .Stagger: if b.timer <= 0 { boss_plan(g) }
	case .Dormant, .Dead:
	}
}

damage_boss :: proc(g: ^State, amount: int, point: Vec3) -> bool {
	b := &g.boss
	if b.id == 0 || b.phase == .Dead { return false }
	if !boss_open(b^) { emit(g, point, 6, 2); return false }
	// Each broken reservoir visibly ends a phase; an explosive cannot skip
	// the entire encounter. Four precise basic rounds break one reservoir.
	floor := BOSS_HEALTH-(b.stage+1)*12
	b.health = max(floor, b.health-amount)
	b.flash, g.player.hit_marker = 0.18, 0.22
	emit(g, point, 15, 0)
	if b.health > floor { return true }
	light_flash(g, boss_core(g.world), {1, 0.4, 0.08}, 15, 8, 0.6)
	sound_event(g, .MechanicalBreak, boss_core(g.world))
	if b.health > 0 {
		b.stage += 1
		boss_phase(b, .Stagger, 1.05)
	} else {
		boss_phase(b, .Dead, BOSS_DEATH_DURATION)
		sound_event(g, .GateSlide, g.world.boss_exit.center)
		g.player.health = min(100, g.player.health+25)
		g.message, g.message_time = 13, 7
		checkpoint_changed(g)
		emit(g, boss_core(g.world), 110, 0)
	}
	return true
}

boss_valid :: proc(w: ^World, b: Boss_State) -> bool {
	if b.id != w.sector.boss.id { return false }
	if b.id == 0 { return b == Boss_State{} }
	if b.phase < .Dormant || b.phase > .Dead || b.stage < 0 || b.stage > 2 || b.health < 0 || b.health > BOSS_HEALTH { return false }
	if b.phase == .Dead { if b.health != 0 || b.stage != 2 { return false }
	} else if b.health <= BOSS_HEALTH-(b.stage+1)*12 || b.health > BOSS_HEALTH-b.stage*12 { return false }
	if !(b.timer >= 0 && b.timer <= b.duration && b.duration <= 10 && b.flash >= 0 && b.flash <= 1) { return false }
	if b.lane_count < 0 || b.lane_count > 3 || b.pass < 0 || b.pass >= max(1, b.lane_count) { return false }
	if b.phase != .Dormant && b.phase != .Dead && b.lane_count < 1 { return false }
	c := boss_room_origin(w)
	for i in 0..<b.lane_count {
		lane := b.lanes[i]
		if !(lane.width >= 3 && lane.width <= 4) { return false }
		for p in ([2]Vec3{lane.a-c, lane.b-c}) { if abs(p.x) > 24 || abs(p.z) > 20 || abs(p.y-0.16) > 0.01 { return false } }
		if !((lane.a.x == lane.b.x) != (lane.a.z == lane.b.z)) || length(lane.b-lane.a) < 30 { return false }
	}
	return true
}
