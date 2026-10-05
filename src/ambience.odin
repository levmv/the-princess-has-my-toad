package main

import "core:math"
import rl "vendor:raylib"
import game "game"

Ambience_Kind :: enum { Hall, Duct, Open, Quiet, Machine_Off, Machine_On }
AMBIENCE_RATE :: 22050
AMBIENCE_FRAMES :: 2048
Ambience :: struct {
	stream: rl.AudioStream,
	loops: [Ambience_Kind][]f32,
	weights: [Ambience_Kind]f32,
	cursor: int,
	ready: bool,
}

// Four-second periodic beds. Filter warm-up traverses the loop boundary before
// recording; no sample, oscillator or noise discontinuity is baked into the seam.
ambience_samples :: proc(kind: Ambience_Kind, samples: []f32) {
	assert(len(samples) == AMBIENCE_RATE*4)
	low, mid := f32(0), f32(0)
	for i in 0..<len(samples)+4096 {
		index := i%len(samples)
		seed := u32(index)+u32(kind)*0x9E3779B9+311
		seed = (seed ~ (seed>>16))*0x7FEB352D
		seed = (seed ~ (seed>>15))*0x846CA68B
		noise := f32(seed>>8)/8388608-1
		low += (noise-low)*0.008
		mid += (noise-mid)*0.065
		t := f32(index)/AMBIENCE_RATE
		value := f32(0)
		switch kind {
		case .Hall:
			value = math.sin(t*2*math.PI*55)*0.15+math.sin(t*2*math.PI*82.5)*0.07+low*0.9
			value *= 0.85+0.15*math.sin(t*math.PI*0.5)
		case .Duct:
			value = mid*0.62+low*0.4+math.sin(t*2*math.PI*137.5)*0.045
			pulse := math.mod(t+0.3, 1)
			value += math.sin(pulse*2*math.PI*720)*0.025*math.exp(-pulse*22)
		case .Open: value = low*1.1+mid*0.13+math.sin(t*2*math.PI*47.5)*0.025
		case .Quiet:
			value = low*0.4+math.sin(t*2*math.PI*60)*0.045
			pulse := math.mod(t+0.5, 2)
			value += math.sin(pulse*2*math.PI*935)*0.045*math.exp(-pulse*13)
		case .Machine_Off:
			value = math.sin(t*2*math.PI*50)*0.10+math.sin(t*2*math.PI*150)*0.03+low*0.5
		case .Machine_On:
			value = math.sin(t*2*math.PI*90)*0.14+math.sin(t*2*math.PI*180)*0.065+mid*0.43
			value *= 0.82+0.18*math.sin(t*2*math.PI*12)
		}
		if i >= 4096 { samples[i-4096] = clamp(value, -0.38, 0.38) }
	}
}

ambience_init :: proc(a: ^Ambience) {
	ambience_init_stream(a)
	for kind in Ambience_Kind { ambience_init_loop(a, kind) }
}

ambience_init_stream :: proc(a: ^Ambience) {
	rl.SetAudioStreamBufferSizeDefault(AMBIENCE_FRAMES)
	a.stream = rl.LoadAudioStream(AMBIENCE_RATE, 32, 2)
	a.ready = rl.IsAudioStreamValid(a.stream)
	if a.ready {
		rl.SetAudioStreamPan(a.stream, 0)
		rl.PlayAudioStream(a.stream)
		rl.PauseAudioStream(a.stream)
	}
}

ambience_init_loop :: proc(a: ^Ambience, kind: Ambience_Kind) {
	if !a.ready { return }
	a.loops[kind] = make([]f32, AMBIENCE_RATE*4)
	ambience_samples(kind, a.loops[kind])
}

ambience_destroy :: proc(a: ^Ambience) {
	if a.ready { rl.UnloadAudioStream(a.stream) }
	for loop in a.loops { delete(loop) }
	a^ = {}
}

ambience_targets :: proc(g: ^game.State) -> [Ambience_Kind]f32 {
	weights: [Ambience_Kind]f32
	i := game.room_at(&g.world.sector, g.player.position)
	if i < 0 { weights[.Open] = 0.65; return weights }
	s := g.world.sector.sections[i]
	if s.intent == .Secret { weights[.Quiet] = 0.8; return weights }
	switch s.role {
	case .Service_Passage, .Bus_Passage: weights[.Duct] = 0.8
	case .Address_Bridge, .Fracture_Span, .Launch_Terrace, .Charge_Causeway, .Receiver_Terrace: weights[.Open] = 0.9
	case .Air_Lift:
		weights[.Hall] = 0.25
		weights[.Machine_On if g.lift_started else .Machine_Off] = 0.8
	case .Switching_Hall: weights[.Hall], weights[.Machine_On] = 0.65, 0.3
	case .GC_Chamber:
		weights[.Hall] = 0.3
		weights[.Quiet if g.boss.phase == .Dead || g.boss.phase == .Dormant else .Machine_On] = 0.6
	case .Junction, .Branch_Landing: weights[.Quiet] = 0.75
	case .Bank, .Capacitor_Court, .Combat_Bay, .Stair_Hall, .Memory_Gallery, .Capacitor_Garden: weights[.Hall] = 0.85
	}
	return weights
}

ambience_mix :: proc(a: ^Ambience, target: [Ambience_Kind]f32, samples: []f32) {
	assert(len(samples)%2 == 0)
	frames := len(samples)/2
	change: [Ambience_Kind]f32
	for weight, kind in a.weights { change[kind] = clamp(target[kind]-weight, -0.12, 0.12)/f32(frames) }
	for i in 0..<frames {
		left, right := f32(0), f32(0)
		for loop, kind in a.loops {
			a.weights[kind] += change[kind]
			if a.weights[kind] <= 0.00001 { continue }
			value := loop[a.cursor]
			// Most low-frequency energy stays centred; a little decorrelated air
			// avoids a mono hiss pasted across every room.
			left += value*a.weights[kind]
			right += (value*0.85+loop[(a.cursor+97)%len(loop)]*0.15)*a.weights[kind]
		}
		samples[i*2], samples[i*2+1] = left*0.30, right*0.30
		a.cursor = (a.cursor+1)%(AMBIENCE_RATE*4)
	}
}

ambience_update :: proc(a: ^Audio, g: ^game.State) {
	bed := &a.ambience
	if !bed.ready { return }
	target := ambience_targets(g)
	// Background recedes under automatic fire and readable attack warnings.
	duck := f32(0.50) if g.player.recoil > 0.05 || g.boss.phase == .Mark else f32(1)
	for e in g.enemies[:g.enemy_count] {
		if e.health > 0 && e.phase == .Windup && game.length(e.position-g.player.position) < 16 { duck = min(duck, 0.60) }
	}
	for &v in target { v *= a.ambience_gain*duck }
	// At most two buffers, without a synthesis callback, worker or allocation.
	// The audio library consumes this persistent stream normally.
	for _ in 0..<2 {
		if !rl.IsAudioStreamProcessed(bed.stream) { break }
		samples: [AMBIENCE_FRAMES*2]f32
		ambience_mix(bed, target, samples[:])
		rl.UpdateAudioStream(bed.stream, &samples[0], AMBIENCE_FRAMES)
	}
	if !rl.IsAudioStreamPlaying(bed.stream) { rl.ResumeAudioStream(bed.stream) }
}

foot_surface :: proc(w: ^game.World, position: game.Vec3) -> int {
	from := position+game.Vec3{0, 0.2, 0}
	distance, style := f32(0.6), 0
	for block in w.blocks {
		if t, hit := game.ray_box(from, {0, -1, 0}, block, distance); hit { distance, style = t, block.style }
	}
	return style
}

foot_sound :: proc(w: ^game.World, position: game.Vec3, landing: bool) -> Sound_Kind {
	surface := foot_surface(w, position)
	if surface == 6 { return .LandBoard if landing else .StepBoard }
	room := game.room_at(&w.sector, position)
	if surface == 8 || (surface == 9 && room >= 0 && w.sector.sections[room].role == .Service_Passage) { return .LandPlate if landing else .StepPlate }
	return .Land if landing else .Step
}
