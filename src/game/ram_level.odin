package game

import "core:math"

ram_block :: proc(w: ^World, center, size: Vec3, style: int = 6, bevel: f32 = 0.55) {
	add_block(w, center, size, style)
	bevel_block(&w.blocks[len(w.blocks)-1], min(bevel, min(size.x, size.z)*0.2), 0.14)
}

ram_local :: proc(s: Section_Recipe, p: Vec3) -> Vec3 {
	return s.origin+(Vec3{-p.z, p.y, p.x} if s.width > s.depth else p)
}

ram_bank :: proc(w: ^World, s: Section_Recipe, seed: ^u32) {
	rows := 5 if s.depth > 70 else 3
	for side in 0..<2 {
		sign := f32(side*2-1)
		for row in 0..<rows {
			z := (f32(row)/f32(rows-1)-0.5)*s.depth*0.7
			p := s.origin+Vec3{sign*(s.width*0.31+(random_stream(seed)-0.5)), 1.1, z}
			ram_block(w, p, {3.3, 2.2, 4.8}, 3)
			for pin in 0..<6 {
				for edge in 0..<2 {
					x := p.x+f32(edge*2-1)*1.75
					pin_z := p.z-1.8+f32(pin)*0.72
					add_decor_beam(w, {x, s.origin.y+0.12, pin_z}, {x, s.origin.y+1, pin_z}, 0.10, 0.10, {203, 161, 82}, 0, 4)
				}
			}
			add_decor_beam(w, p+Vec3{-1, 1.13, 0}, p+Vec3{1, 1.13, 0}, 0.045, 0.045, {125, 147, 145})
			// Tall edge modules make galleries read as rooms between memory banks.
			q := s.origin+Vec3{sign*(s.width*0.5-1.7), s.height*0.35, z}
			ram_block(w, q, {1.8, s.height*0.7, 6}, 3, 0.25)
			add_decor_beam(w, q-Vec3{sign*0.94, s.height*0.28, 1.5}, q+Vec3{-sign*0.94, s.height*0.28, -1.5}, 0.04, 0.04, DECOR_MINT, 3, 4)
		}
	}
}

ram_passage :: proc(w: ^World, s: Section_Recipe) {
	service := s.role == .Service_Passage
	span := max(s.width, s.depth)
	half := min(s.width, s.depth)*0.5
	accent := ram_theme_accent(ram_theme(s))
	for side in 0..<2 {
		sign := f32(side*2-1)
		add_decor_beam(w, ram_local(s, {sign*(half-0.7), 0.15, -span*0.5+1}), ram_local(s, {sign*(half-0.7), 0.15, span*0.5-1}), 0.06, 0.06, accent, 3, 4)
		if service {
			for pipe in 0..<3 {
				y := 1.2+f32(pipe)*0.7
				add_decor_beam(w, ram_local(s, {sign*(half-0.95), y, -span*0.5+1}), ram_local(s, {sign*(half-0.95), y, span*0.5-1}), 0.16, 0.16, {89, 106, 119}, 2, 8)
			}
		}
	}
	for rib in 0..<int(span/8) {
		z := -span*0.5+4+f32(rib)*8
		for side in 0..<2 {
			x := f32(side*2-1)*(half-0.65)
			add_decor_beam(w, ram_local(s, {x, 0.2, z}), ram_local(s, {x, s.height-0.4, z}), 0.12, 0.12, {47, 65, 76}, 0, 6)
		}
		if !s.open_roof { add_decor_beam(w, ram_local(s, {-half+0.6, s.height-0.35, z}), ram_local(s, {half-0.6, s.height-0.35, z}), 0.12, 0.12, {47, 65, 76}) }
	}
}

ram_capacitors :: proc(w: ^World, s: Section_Recipe, seed: ^u32) {
	rows := 4 if s.depth > 70 else 2
	radius := min(3, s.width*0.11)
	for side in 0..<2 {
		for row in 0..<rows {
			height := 5.5+random_stream(seed)*2.0
			p := s.origin+Vec3{f32(side*2-1)*s.width*0.32, height*0.5, (f32(row)/f32(rows-1)-0.5)*s.depth*0.55}
			// The clipping planes describe a decagon with this apothem. Its
			// corners and trim must use the circumradius, not a smaller circle
			// that disappears inside the shell between every pair of corners.
			outer := radius/math.cos(f32(math.PI/10))
			add_block(w, p, {outer*2, height, outer*2}, 7)
			b := &w.blocks[len(w.blocks)-1]
			for face in 0..<10 {
				a := f32(face)*2*math.PI/10
				n := Vec3{math.cos(a), 0, math.sin(a)}
				clip_block(b, n, p+n*radius)
			}
			for ring in 0..<2 {
				y := s.origin.y+0.35+f32(ring)*(height-0.7)
				for segment in 0..<10 {
					a, z := (f32(segment)*2+1)*math.PI/10, (f32(segment+1)*2+1)*math.PI/10
					add_decor_beam(w, {p.x+math.cos(a)*(outer+0.05), y, p.z+math.sin(a)*(outer+0.05)}, {p.x+math.cos(z)*(outer+0.05), y, p.z+math.sin(z)*(outer+0.05)}, 0.06, 0.06, DECOR_ORANGE, 3, 4)
				}
			}
			add_decor_beam(w, p+Vec3{-radius*0.7, height*0.5+0.015, 0}, p+Vec3{radius*0.7, height*0.5+0.015, 0}, 0.035, 0.035, {42, 58, 68}, 0, 4)
		}
	}
}

ram_air_lift :: proc(w: ^World, s: Section_Recipe) {
	c := s.origin
	vent := c-Vec3{0, 0, s.depth*0.5-6}
	controlled := w.sector.mechanism == .Shot_Lift && s.id == w.sector.mechanism_room
	if controlled { ram_lift_switch(w, s, len(w.vents)) }
	append(&w.vents, Vent{position = vent, radius = 3.0, top = c.y+18, controlled = controlled})
	for side in 0..<2 {
		sign := f32(side*2-1)
		ram_block(w, vent+Vec3{sign*7, 6, 0}, {2.2, 12, 3}, 3)
		for fin in 0..<9 {
			add_decor_beam(w, vent+Vec3{sign*5.8, f32(fin)+1, -1.5}, vent+Vec3{sign*5.8, f32(fin)+1, 2.5}, 0.18, 0.18, {103, 140, 142}, 0, 4)
		}
	}
}

ram_lamps :: proc(w: ^World, s: Section_Recipe) {
	span := max(s.width, s.depth)
	count := max(1, int(span/20))
	y := min(5.5, s.height-0.5)
	nav := &w.room_navigation[room_index(&w.sector, s.id)]
	if nav.count > 0 { count = min(4, nav.count) }
	for i in 0..<count {
		z := (f32(i)+0.5)*span/f32(count)-span*0.5
		p := ram_local(s, {0, y, z})
		if nav.count > 0 { p = nav.points[i*nav.count/count]+Vec3{0, y, 0} }
		append(&w.lamps, p)
		add_decor_beam(w, p-Vec3{0.8, 0, 0}, p+Vec3{0.8, 0, 0}, 0.08, 0.08, ram_theme_accent(ram_theme(s)), 3, 6)
		if !s.open_roof {
			add_decor_beam(w, p+Vec3{0, 0.1, 0}, {p.x, s.origin.y+s.height+0.95, p.z}, 0.05, 0.05, {45, 61, 74})
		} else {
			// Exterior lamps hang from real supports instead of floating in air.
			size := Vec3{s.width, 0.22, 0.26} if s.depth >= s.width else Vec3{0.26, 0.22, s.depth}
			add_block(w, p+Vec3{0, 0.35, 0}, size, 3)
			add_decor_beam(w, p, p+Vec3{0, 0.3, 0}, 0.05, 0.05, {45, 61, 74})
		}
	}
}

ram_backdrop :: proc(w: ^World, seed: ^u32) {
	lo, hi := Vec3{1e6, 0, 1e6}, Vec3{-1e6, 0, -1e6}
	for i in 0..<w.sector.count {
		s := w.sector.sections[i]
		lo.x, lo.z = min(lo.x, s.origin.x-s.width*0.5), min(lo.z, s.origin.z-s.depth*0.5)
		hi.x, hi.z = max(hi.x, s.origin.x+s.width*0.5), max(hi.z, s.origin.z+s.depth*0.5)
	}
	for side in 0..<2 {
		x := lo.x-90 if side == 0 else hi.x+90
		normal := f32(1 if side == 0 else -1)
		for board in 0..<int((hi.z-lo.z)/34)+1 {
			z := hi.z-f32(board)*34
			height := 58+random_stream(seed)*18
			shape := Block{center = {x, height*0.5-42, z}, size = {2, height, 24}}
			bevel_block(&shape, 0.35, 0.25)
			append(&w.decor_blocks, Decor_Block{shape, {24, 71, 61}, {78, 137, 114}})
			// Distant DIMMs descend into the dark below the playable supports.
			// Packages and contacts make them read as hardware instead of panels.
			for row in 0..<3 {
				y := height-49-f32(row)*15
				chip := Block{center = {x+normal*1.3, y, z}, size = {1.2, 9, 17}}
				bevel_block(&chip, 0.3, 0.2)
				append(&w.decor_blocks, Decor_Block{chip, {19, 28, 32}, {46, 63, 66}})
				for pin in 0..<6 {
					pz := z-7+f32(pin)*2.8
					add_decor_beam(w, {x+normal*1.95, y-4.6, pz}, {x+normal*1.95, y-6, pz}, 0.17, 0.17, {171, 135, 70}, 0, 4)
				}
			}
			add_decor_beam(w, {x+normal*1.1, -40, z-10.5}, {x+normal*1.1, height-44, z-10.5}, 0.13, 0.13, {83, 137, 102}, 0, 4)
		}
	}
}

world_init_ram :: proc(w: ^World, seed: u32 = DEFAULT_SEED) { world_build_ram(w, ram_cold_boot(), seed) }

world_build_ram :: proc(w: ^World, recipe: Sector_Recipe, seed: u32) {
	checked := recipe
	resolve_room_variants(&checked, seed)
	error, _ := validate_sector(&checked)
	assert(error == .None, "Invalid sector content: validate_sector returns the failing kind and index")
	profile := region_definition(recipe.region)
	assert(profile.implemented)
	clear_blocks(w)
	clear(&w.vents)
	clear(&w.core_spawns)
	clear(&w.enemy_spawns)
	clear(&w.lamps)
	clear(&w.decor_blocks)
	clear(&w.decor_beams)
	clear(&w.encounters)
	w.kind, w.seed, w.sector = .RAM, seed, checked
	w.room_navigation = {}
	w.gates, w.gate_count = {}, 0
	w.checkpoints, w.checkpoint_count = {}, recipe.checkpoint_count
	w.pickup_spawns, w.pickup_count = {}, recipe.pickup_count
	for i in 0..<recipe.pickup_count {
		pickup := recipe.pickups[i]
		position, _ := resolve_location(&w.sector, pickup.at)
		w.pickup_spawns[i] = {pickup.id, position, pickup.kind, pickup.units, false}
	}
	w.lift = {vent_index = -1}
	w.boss_exit, w.boss_exit_amount = {}, 0
	w.spawn, _ = resolve_location(&w.sector, recipe.entry)
	w.exit, _ = resolve_location(&w.sector, recipe.exit)
	decor_seed := seed+0x928A21
	if decor_seed == 0 { decor_seed = 1 }
	for i in 0..<recipe.count {
		s := checked.sections[i]
		layout_seed := content_seed(seed, u32(s.id), 0x194C73)
		enemy_seed := content_seed(seed, u32(s.id), 0x629AF1)
		floor_style := profile.board_style if s.role == .Bank || s.role == .Bus_Passage || s.role == .Memory_Gallery else profile.floor_style
		wall_style := 3 if s.role == .Capacitor_Court else (profile.service_style if s.role == .Service_Passage || s.role == .Air_Lift else profile.wall_style)
		if recipe.key == .RAM_Bank_01 { wall_style, floor_style = ram_theme_styles(s) }
		if !exterior_section(s.role) { room_shell(w, s, wall_style, floor_style) }
		switch s.role {
		case .Bank: ram_bank(w, s, &layout_seed)
		case .Bus_Passage: ram_passage(w, s)
		case .Service_Passage:
			if s.variant == .Authored { ram_passage(w, s) } else { ram_service_variant(w, s) }
		case .Capacitor_Court: ram_capacitors(w, s, &layout_seed)
		case .Air_Lift: ram_air_lift(w, s)
		case .Junction:
		case .Combat_Bay: ram_combat_bay(w, s)
		case .Stair_Hall: ram_stair_hall(w, s)
		case .Memory_Gallery: ram_memory_gallery(w, s)
		case .Capacitor_Garden: ram_capacitor_garden(w, s)
		case .Branch_Landing: ram_branch_landing(w, s)
		case .Address_Bridge: ram_address_bridge(w, s)
		case .Switching_Hall: ram_switching_hall(w, s)
		case .GC_Chamber: ram_gc_chamber(w, s)
		case .Fracture_Span: ram_fracture_span(w, s)
		case .Launch_Terrace: ram_launch_terrace(w, s)
		case .Charge_Causeway: ram_charge_causeway(w, s)
		case .Receiver_Terrace: ram_receiver_terrace(w, s)
		}
		if s.intent == .Secret { ram_secret_scene(w, s) }
		if s.id == 1003 {
			// A cabinet masks the service niche from the ordinary forward route.
			ram_block(w, s.origin+Vec3{-11, 2.5, -8}, {3.4, 5, 9}, 3, 0.6)
			add_decor_beam(w, s.origin+Vec3{-9.24, 0.8, -11}, s.origin+Vec3{-9.24, 3.9, -11}, 0.05, 0.05, DECOR_ORANGE, 3, 4)
		}
		if recipe.key == .RAM_Bank_01 {
			ram_identity(w, s)
			ram_banner_mount(w, s)
			if s.id == 1001 { ram_patch_cabinet(w, s) }
			if s.id == 1003 { ram_induction_coil(w, s) }
			if s.id == 1014 && s.variant == .Authored { ram_cargo_ambush(w, s) }
		}
		if !exterior_section(s.role) && s.role != .Capacitor_Garden { ram_lamps(w, s) }
		ram_encounter(w, s, &enemy_seed)
	}
	for i in 0..<recipe.checkpoint_count {
		c := recipe.checkpoints[i]
		position, _ := resolve_location(&w.sector, c.at)
		w.checkpoints[i] = {c.id, position, c.radius}
	}
	total := 0
	for e in w.encounters { total += e.count }
	assert(total <= ENEMY_CAPACITY, "Sector population exceeds the enemy pool")
	ram_backdrop(w, &decor_seed)
	world_commit(w)
	build_gates(w)
	build_room_navigation(w)
}

content_seed :: proc(seed, id, domain: u32) -> u32 {
	r := seed ~ (id*0x9E3779B9) ~ domain
	if r == 0 { r = 1 }
	for _ in 0..<3 { random_stream(&r) }
	return r
}
