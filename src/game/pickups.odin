package game

Pickup_Kind :: enum u8 { Health = 0, Fragments = 1, Launcher = 2, Shotgun = 3, Shells = 4 }
Pickup_Def :: struct { id: Object_ID, at: Location_Def, kind: Pickup_Kind, units: int }
Pickup :: struct { id: Object_ID, position: Vec3, kind: Pickup_Kind, amount: int, collected: bool }

sector_pickup :: proc(r: ^Sector_Recipe, room: Room_ID, local: u16, offset: Vec3, kind: Pickup_Kind, units: int = 1) {
	assert(r.pickup_count < len(r.pickups), "Sector pickup capacity exceeded")
	r.pickups[r.pickup_count] = {room_object_id(room, local), {room, offset}, kind, units}
	r.pickup_count += 1
}

update_pickups :: proc(g: ^State) {
	for &pickup in g.pickups[:g.pickup_count] {
		if pickup.collected { continue }
		delta := pickup.position-g.player.position-Vec3{0, 0.75, 0}
		distance := length(delta)
		if distance > 1.2 { continue }
		if world_ray(g, g.player.position+Vec3{0, 0.75, 0}, normalized(delta), distance) < distance-0.03 { continue }
		switch pickup.kind {
		case .Health:
			if g.player.health >= 100 { continue }
			g.player.health = min(100, g.player.health+f32(pickup.amount))
			sound_event(g, .HealthPickup, pickup.position)
		case .Fragments, .Launcher:
			if g.player.fragment_ammo >= FRAGMENT_AMMO_MAX && (pickup.kind != .Launcher || g.player.fragment_unlocked) { continue }
			first_weapon := !g.player.fragment_unlocked
			if pickup.kind == .Launcher { g.player.fragment_unlocked = true }
			g.player.fragment_ammo = min(FRAGMENT_AMMO_MAX, g.player.fragment_ammo+pickup.amount)
			if first_weapon && pickup.kind == .Launcher {
				equip_weapon(g, .Fragmentator)
			}
			if !first_weapon || pickup.kind == .Fragments { sound_event(g, .AmmoPickup, pickup.position) }
		case .Shotgun, .Shells:
			if g.player.shotgun_ammo >= SHOTGUN_AMMO_MAX && (pickup.kind != .Shotgun || g.player.shotgun_unlocked) { continue }
			first_weapon := !g.player.shotgun_unlocked
			if pickup.kind == .Shotgun { g.player.shotgun_unlocked = true }
			g.player.shotgun_ammo = min(SHOTGUN_AMMO_MAX, g.player.shotgun_ammo+pickup.amount)
			if first_weapon && pickup.kind == .Shotgun { equip_weapon(g, .Shotgun)
			} else { sound_event(g, .AmmoPickup, pickup.position) }
		}
		pickup.collected = true
		g.pickup_sequence += 1
		emit(g, pickup.position, 16, 1)
	}
}
