package game

// IDs are authored identities, never array offsets or addresses. Renaming or
// moving a room must retain its ID so saves and generated variants can find it.
Room_ID :: distinct u16
Object_ID :: distinct u32
Sector_ID :: enum u16 { None = 0, RAM_Bank_01 = 1, RAM_Transfer = 2, RAM_Combat_Lab = 3 }

SECTOR_ROOM_CAPACITY :: 64
SECTOR_LINK_CAPACITY :: 96
SECTOR_CHECKPOINT_CAPACITY :: 8

Room_Intent :: enum u8 { Arrival, Transit, Combat, Ambush, Branch, Mechanism, Traversal, Finale, Secret }
Exit_Rule :: enum u8 { Reach, Power }
Mechanism_Kind :: enum u8 { None, Shot_Lift }

Location_Def :: struct { room: Room_ID, offset: Vec3 }
Checkpoint_Def :: struct { id: Object_ID, at: Location_Def, radius: f32 }
Checkpoint :: struct { id: Object_ID, position: Vec3, radius: f32 }

Region_Def :: struct {
	id: Region,
	name, character: string,
	wall_style, floor_style, service_style, board_style: int,
	implemented: bool,
}

region_definition :: proc(id: Region) -> Region_Def {
	switch id {
	case .RAM: return {id, "RAM", "Banks, service ducts, capacitors and suspended address bridges", 5, 9, 8, 6, true}
	case .Bus: return {id, "BUS", "Fast lanes, moving packets and transfers between routes", 5, 9, 8, 6, false}
	case .HDD: return {id, "HDD", "Concentric tracks, mechanical heads and displaced sectors", 5, 9, 8, 6, false}
	case .CPU: return {id, "CPU", "Dense vertical cells, clocked mechanisms and the top of the Tower", 5, 9, 8, 6, false}
	}
	unreachable()
}

// A direction for the campaign, not a claim that four regions are playable.
campaign_regions :: proc() -> [4]Region { return {.RAM, .Bus, .HDD, .CPU} }

Sector_Def :: struct {
	id, next: Sector_ID,
	path, title: string,
	region: Region,
	preview: bool,
}

sector_definition :: proc(id: Sector_ID) -> Sector_Def {
	switch id {
	case .RAM_Bank_01: return {id, .RAM_Transfer, "ram/bank-01", "COLD BOOT", .RAM, false}
	case .RAM_Transfer: return {id, .None, "ram/transfer", "TRANSFER / UNFINISHED", .RAM, true}
	case .RAM_Combat_Lab: return {id, .None, "ram/combat-lab", "CONTACT / COMBAT LAB", .RAM, true}
	case .None: return {}
	}
	unreachable()
}

sector_by_path :: proc(path: string) -> Sector_ID {
	for id in Sector_ID { if id != .None && sector_definition(id).path == path { return id } }
	return .None
}

Campaign_Progress :: struct {
	seed: u32,
	current: Sector_ID,
	completed: u64,
}

campaign_mark_complete :: proc(g: ^State) {
	id := g.world.sector.key
	if id == .None || sector_definition(id).preview { return }
	g.campaign.completed |= u64(1)<<u16(id)
}

campaign_next :: proc(g: ^State) -> Sector_ID {
	if !g.won { return .None }
	return sector_definition(g.campaign.current).next
}

// Called between frames; the renderer observes the world's new revision.
// Allocation for a level transition is intentionally outside the fixed tick.
advance_campaign :: proc(g: ^State) -> bool {
	next := campaign_next(g)
	if next == .None { return false }
	player := g.player
	world_load_sector(g.world, next, g.campaign.seed)
	init(g)
	g.player.health = player.health
	g.player.weapon, g.player.fragment_unlocked, g.player.fragment_ammo = player.weapon, player.fragment_unlocked, player.fragment_ammo
	g.player.shotgun_unlocked, g.player.shotgun_ammo = player.shotgun_unlocked, player.shotgun_ammo
	capture_checkpoint(g)
	return true
}

room_index :: proc(r: ^Sector_Recipe, id: Room_ID) -> int {
	if id == 0 { return -1 }
	for i in 0..<r.count { if r.sections[i].id == id { return i } }
	return -1
}

resolve_location :: proc(r: ^Sector_Recipe, at: Location_Def) -> (Vec3, bool) {
	i := room_index(r, at.room)
	if i < 0 { return {}, false }
	return r.sections[i].origin+at.offset, true
}

room_object_id :: proc(room: Room_ID, local: u16) -> Object_ID {
	assert(room != 0 && local != 0)
	return Object_ID(u32(room)<<16 | u32(local))
}

// Ground-based and flying actors share this graph but apply their own clearance
// and elevation rules when choosing a connection.
room_at :: proc(r: ^Sector_Recipe, position: Vec3) -> int {
	for i in 0..<r.count {
		s := &r.sections[i]
		p := position-s.origin
		if abs(p.x) <= s.width*0.5 && abs(p.z) <= s.depth*0.5 && p.y >= -0.2 && p.y <= s.height+1.4 { return i }
	}
	return -1
}

Content_Error :: enum {
	None, Capacity, Metadata, Room_ID, Room_Bounds, Room_Overlap,
	Portal, Connection, Disconnected, Location, Checkpoint, Mechanism, Pickup, Variant, Gate, Boss,
}

validate_sector :: proc(r: ^Sector_Recipe) -> (Content_Error, int) {
	if r.pickup_count < 0 || r.pickup_count > len(r.pickups) { return .Capacity, -1 }
	if r.gate_count < 0 || r.gate_count > len(r.gates) { return .Capacity, -1 }
	if r.count < 1 || r.count > len(r.sections) || r.connection_count < 0 || r.connection_count > len(r.connections) || r.checkpoint_count < 0 || r.checkpoint_count > len(r.checkpoints) { return .Capacity, -1 }
	if r.key == .None || len(r.id) == 0 || len(r.title) == 0 || r.generator_version == 0 { return .Metadata, -1 }
	secret_count := 0
	for i in 0..<r.count {
		s := &r.sections[i]
		if s.intent == .Secret { secret_count += 1 }
		if secret_count > 8 { return .Capacity, i }
		if s.variant != .Authored && s.role != .Memory_Gallery && s.role != .Service_Passage { return .Variant, i }
		if s.role == .Memory_Gallery && (s.width < 24 || s.depth < 40 || s.width > s.depth) { return .Variant, i }
		if s.role == .Service_Passage && s.variant != .Authored && (min(s.width, s.depth) < 8 || max(s.width, s.depth) < 32) { return .Variant, i }
		if s.id == 0 { return .Room_ID, i }
		if !(s.width > 2 && s.depth > 2 && s.height > PLAYER_HEIGHT+0.5 && s.width < 1000 && s.depth < 1000 && s.height < 1000) || !(abs(s.origin.x) < 1e6 && abs(s.origin.y) < 1e6 && abs(s.origin.z) < 1e6) { return .Room_Bounds, i }
		if s.door_count < 0 || s.door_count > len(s.doors) { return .Capacity, i }
		for j in 0..<i {
			t := &r.sections[j]
			if s.id == t.id { return .Room_ID, i }
			dx, dz := abs(s.origin.x-t.origin.x), abs(s.origin.z-t.origin.z)
			if dx < (s.width+t.width)*0.5-0.01 && dz < (s.depth+t.depth)*0.5-0.01 && s.origin.y < t.origin.y+t.height && t.origin.y < s.origin.y+s.height { return .Room_Overlap, i }
		}
		for d in 0..<s.door_count {
			p := s.doors[d]
			span := s.width if p.side == .North || p.side == .South else s.depth
			if !(p.width >= PLAYER_RADIUS*2+0.5 && p.height >= PLAYER_HEIGHT+0.5 && p.bottom >= 0 && p.bottom+p.height <= s.height && abs(p.offset)+p.width*0.5 <= span*0.5) { return .Portal, i }
			for other in 0..<d {
				q := s.doors[other]
				if q.side == p.side && abs(q.offset-p.offset) < (q.width+p.width)*0.5 { return .Portal, i }
			}
		}
	}
	degree: [SECTOR_ROOM_CAPACITY]int
	for i in 0..<r.connection_count {
		c := r.connections[i]
		a, b := room_index(r, c.a), room_index(r, c.b)
		if a < 0 || b < 0 || a == b { return .Connection, i }
		if !(c.width >= PLAYER_RADIUS*2+0.5 && c.height >= PLAYER_HEIGHT+0.5) { return .Connection, i }
		for earlier in 0..<i {
			p := r.connections[earlier]
			if (c.a == p.a && c.b == p.b) || (c.a == p.b && c.b == p.a) { return .Connection, i }
		}
		ends := [2]int{a, b}
		for index in ends {
			s := &r.sections[index]
			found := false
			for d in 0..<s.door_count {
				p := s.doors[d]
				position := s.origin+Vec3{0, p.bottom, 0}
				switch p.side {
				case .North: position.x += p.offset; position.z -= s.depth*0.5
				case .South: position.x += p.offset; position.z += s.depth*0.5
				case .West: position.z += p.offset; position.x -= s.width*0.5
				case .East: position.z += p.offset; position.x += s.width*0.5
				}
				if length(position-c.position) < 0.01 && abs(p.width-c.width) < 0.01 && abs(p.height-c.height) < 0.01 { found = true; break }
			}
			if !found { return .Connection, i }
			degree[index] += 1
		}
	}
	for i in 0..<r.count { if degree[i] != r.sections[i].door_count { return .Connection, i } }
	visited: [SECTOR_ROOM_CAPACITY]bool
	queue: [SECTOR_ROOM_CAPACITY]int
	visited[0] = true
	head, tail := 0, 1
	for head < tail {
		id := r.sections[queue[head]].id
		head += 1
		for i in 0..<r.connection_count {
			c := r.connections[i]
			other := c.b if c.a == id else (c.a if c.b == id else Room_ID(0))
			if other == 0 { continue }
			index := room_index(r, other)
			if visited[index] { continue }
			visited[index] = true
			queue[tail] = index
			tail += 1
		}
	}
	if tail != r.count { return .Disconnected, -1 }
	locations := [2]Location_Def{r.entry, r.exit}
	for at in locations {
		p, ok := resolve_location(r, at)
		if !ok || room_at(r, p) != room_index(r, at.room) { return .Location, -1 }
	}
	if r.wing_hint.room != 0 {
		p, ok := resolve_location(r, r.wing_hint)
		if !ok || room_at(r, p) != room_index(r, r.wing_hint.room) { return .Location, -1 }
	}
	for i in 0..<r.checkpoint_count {
		c := r.checkpoints[i]
		p, ok := resolve_location(r, c.at)
		if c.id == 0 || !ok || room_at(r, p) != room_index(r, c.at.room) || !(c.radius > 0 && c.radius < 20) { return .Checkpoint, i }
		for j in 0..<i { if r.checkpoints[j].id == c.id { return .Checkpoint, i } }
	}
	if r.mechanism == .Shot_Lift {
		i := room_index(r, r.mechanism_room)
		if i < 0 || r.sections[i].role != .Air_Lift { return .Mechanism, -1 }
	} else if r.exit_rule == .Power { return .Mechanism, -1 }
	for i in 0..<r.pickup_count {
		p := r.pickups[i]
		position, ok := resolve_location(r, p.at)
		if p.id == 0 || !ok || room_at(r, position) != room_index(r, p.at.room) || p.units < 1 || p.units > 10 { return .Pickup, i }
		for earlier in r.pickups[:i] { if earlier.id == p.id { return .Pickup, i } }
		for checkpoint in r.checkpoints[:r.checkpoint_count] { if checkpoint.id == p.id { return .Pickup, i } }
	}
	for gate, i in r.gates[:r.gate_count] {
		point, ok := resolve_location(r, gate.control)
		if gate.id == 0 || !ok || room_at(r, point) != room_index(r, gate.control.room) { return .Gate, i }
		found := false
		for c in r.connections[:r.connection_count] {
			if (c.a == gate.a && c.b == gate.b) || (c.a == gate.b && c.b == gate.a) { found = true }
		}
		if !found { return .Gate, i }
		for other in r.gates[:i] {
			if gate.id == other.id || (gate.a == other.a && gate.b == other.b) || (gate.a == other.b && gate.b == other.a) { return .Gate, i }
		}
		for p in r.pickups[:r.pickup_count] { if p.id == gate.id { return .Gate, i } }
		for c in r.checkpoints[:r.checkpoint_count] { if c.id == gate.id { return .Gate, i } }
	}
	if r.boss.id != 0 {
		i := room_index(r, r.boss.at.room)
		if i < 0 || r.sections[i].role != .GC_Chamber || r.sections[i].intent != .Finale || r.sections[i].population != .None { return .Boss, -1 }
		s := r.sections[i]
		if s.width < 60 || s.depth < 56 || s.height < 10 || r.boss.at.offset != (Vec3{0, 0, -7}) || r.exit.room != s.id { return .Boss, -1 }
		for p in r.pickups[:r.pickup_count] { if p.id == r.boss.id { return .Boss, -1 } }
		for c in r.checkpoints[:r.checkpoint_count] { if c.id == r.boss.id { return .Boss, -1 } }
		for gate in r.gates[:r.gate_count] { if gate.id == r.boss.id { return .Boss, -1 } }
	}
	return .None, -1
}
