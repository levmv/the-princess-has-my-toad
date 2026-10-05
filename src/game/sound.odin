package game

// This transient ring crosses the simulation/presentation boundary. Gameplay
// never calls an audio library and does not depend on whether a device exists.
Sound_Cue :: enum u8 { SentryCharge, RushCharge, CrabCharge, KettleWhistle, NannyOpen, EnemyShot, ClawSnap, SteamBurst, ShieldBreak, MechanicalBreak, KickSwing, KickHit, FragmentFire, FragmentBlast, DryFire, GCMark, GCSweep, GCOpen, AnvilFall, AnvilHit, RelayClick, PowerStart, GateSlide, FaeDeath, ShotgunFire, GibImpact, EquipRepeater, EquipFragmentator, EquipShotgun, AmmoPickup, HealthPickup, FleshHit, MetalHit, Ricochet, NannyShot, RabbitGrowl, RabbitBite, RabbitDeath }
Sound_Event :: struct { sequence: u32, cue: Sound_Cue, position: Vec3 }

sound_event :: proc(g: ^State, cue: Sound_Cue, position: Vec3) {
	g.sound_sequence += 1
	g.sound_events[(g.sound_sequence-1)%u32(len(g.sound_events))] = {g.sound_sequence, cue, position}
}

enemy_warning :: proc(g: ^State, e: ^Enemy) {
	switch e.kind {
	case .Sentry: sound_event(g, .SentryCharge, e.position)
	case .Interceptor: sound_event(g, .RushCharge, e.position)
	case .Crab: sound_event(g, .CrabCharge, e.position)
	case .Kettle: sound_event(g, .KettleWhistle, e.position)
	case .Nanny: sound_event(g, .NannyOpen, e.position)
	case .Rabbit, .Rabbit_Young, .Rabbit_Kit: sound_event(g, .RabbitGrowl, e.position)
	}
}

sound_projection :: proc(w: ^World, listener: ^Player, point: Vec3, radius: f32 = 48) -> (volume, pan: f32) {
	from := listener.position+Vec3{0, EYE_HEIGHT, 0}
	delta := point-from
	distance := length(delta)
	if distance > radius { return 0, 0 }
	direction := normalized(delta)
	right := cross(forward(listener.yaw, 0), Vec3{0, 1, 0})
	pan = clamp(dot(direction, right)*0.82, -0.82, 0.82)
	volume = 1/(1+distance*distance*0.012*(48/radius)*(48/radius))
	if world_ray(w, from, direction, distance) < distance-0.1 { volume *= 0.38 }
	return
}
