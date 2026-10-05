package main

import "core:math"
import rl "vendor:raylib"
import game "game"

cue_sound :: proc(cue: game.Sound_Cue) -> Sound_Kind {
	switch cue {
	case .SentryCharge: return .SentryCharge
	case .RushCharge: return .RushCharge
	case .CrabCharge: return .CrabCharge
	case .KettleWhistle: return .KettleWhistle
	case .NannyOpen: return .NannyOpen
	case .EnemyShot: return .EnemyShot
	case .ClawSnap: return .ClawSnap
	case .SteamBurst: return .SteamBurst
	case .ShieldBreak: return .ShieldBreak
	case .MechanicalBreak: return .MechanicalBreak
	case .KickSwing: return .KickSwing
	case .KickHit: return .KickHit
	case .FragmentFire: return .FragmentFire
	case .FragmentBlast: return .FragmentBlast
	case .DryFire: return .DryFire
	case .GCMark: return .GCMark
	case .GCSweep: return .GCSweep
	case .GCOpen: return .GCOpen
	case .AnvilFall: return .AnvilFall
	case .AnvilHit: return .AnvilHit
	case .RelayClick: return .RelayClick
	case .PowerStart: return .PowerStart
	case .GateSlide: return .GateSlide
	case .FaeDeath: return .FaeDeath
	case .ShotgunFire: return .ShotgunFire
	case .GibImpact: return .GibImpact
	case .EquipRepeater: return .EquipRepeater
	case .EquipFragmentator: return .EquipFragmentator
	case .EquipShotgun: return .EquipShotgun
	case .AmmoPickup: return .AmmoPickup
	case .HealthPickup: return .HealthPickup
	case .FleshHit: return .FleshHit
	case .MetalHit: return .MetalHit
	case .Ricochet: return .Ricochet
	case .NannyShot: return .NannyShot
	case .RabbitGrowl: return .RabbitGrowl
	case .RabbitBite: return .RabbitBite
	case .RabbitDeath: return .RabbitDeath

	}
	unreachable()
}

// Distinct, quiet mechanical cues; no attempt to synthesize a human voice.
// The rising kettle pressure and umbrella music box belong to the creatures.
enemy_cue_samples :: proc(kind: Sound_Kind, variant: int, samples: []f32) -> int {
	assert(!(kind in RECORDED_SOUNDS))
	duration := f32(0.55)
	if kind == .KettleWhistle { duration = 0.65 }
	if kind == .MechanicalBreak { duration = 0.95 }
	if kind == .NannyOpen { duration = 0.78 }
	if kind == .EnemyShot || kind == .ClawSnap { duration = 0.23 }
	if kind == .ShieldBreak { duration = 0.32 }
	if kind == .KickSwing || kind == .KickHit { duration = 0.20 }
	if kind == .FragmentFire { duration = 0.27 }
	if kind == .FragmentBlast { duration = 0.75 }
	if kind == .MetalHit || kind == .Ricochet { duration = 0.19 }
	if kind == .NannyShot { duration = 0.26 }
	if kind == .AmmoPickup || kind == .HealthPickup { duration = 0.30 }
	if kind == .EquipRepeater || kind == .EquipFragmentator || kind == .EquipShotgun { duration = 0.48 }
	if kind == .DryFire { duration = 0.07 }
	if kind == .GCMark || kind == .GCSweep { duration = 0.95 }
	if kind == .GCOpen || kind == .AnvilFall { duration = 0.85 }
	if kind == .RelayClick { duration = 0.16 }
	if kind == .PowerStart || kind == .GateSlide { duration = 0.95 }
	count := int(duration*22050)
	assert(count <= len(samples))
	seed := u32(66113+variant*931+int(kind)*437)
	low, mid, oscillator := f32(0), f32(0), f32(0)
	tune := 0.97+f32(variant)*0.018
	for i in 0..<count {
		t := f32(i)/22050
		seed = seed*1664525+1013904223
		noise := f32(seed>>16)/32768-1
		low += (noise-low)*0.035
		mid += (noise-mid)*0.24
		value := f32(0)
		switch kind {
		case .SentryCharge:
			oscillator += (310+t*900)*tune*2*math.PI/22050
			value = (math.sin(oscillator)*0.11+math.sin(oscillator*2.03)*0.055+mid*0.07)*min(t*24, 1)*(1-t/duration)
		case .RushCharge:
			oscillator += (110+t*160)*tune*2*math.PI/22050
			value = (math.sin(oscillator)*0.19+math.sin(oscillator*1.49)*0.085+mid*0.24)*min(t*24, 1)*(1-t/duration*0.65)
		case .CrabCharge:
			click := math.mod(t, 0.11)
			value = (mid*0.38+math.sin(click*2*math.PI*760*tune)*0.11)*math.exp(-click*75)
		case .KettleWhistle:
			oscillator += (580+t*750+math.sin(t*27)*12)*tune*2*math.PI/22050
			value = (math.sin(oscillator)*0.14+math.sin(oscillator*2)*0.04+mid*0.20+low*0.65)*min(t*15, 1)*(0.85+0.15*math.sin(t*43))
		case .NannyOpen:
			notes := [3]f32{659.25, 523.25, 392}
			note := min(2, int(t/0.20))
			local := t-f32(note)*0.20
			freq := notes[note]*tune
			value = (math.sin(local*freq*2*math.PI)*0.18+math.sin(local*freq*5.4*math.PI)*0.04)*math.exp(-local*13)
			value += mid*0.12*math.exp(-t*26)
		case .EnemyShot, .ClawSnap:
			value = (low*2.1+mid*0.75+math.sin(t*2*math.PI*96*tune)*0.28)*math.exp(-t*24)
			value += (noise-mid)*0.25*math.exp(-t*180)
			if kind == .ClawSnap { value += (noise-mid)*0.22*math.exp(-t*60) }
		case .SteamBurst:
			value = (mid*0.46+low*1.1)*math.exp(-t*7)+math.sin(t*2*math.PI*61)*0.2*math.exp(-t*18)
		case .ShieldBreak:
			value = (math.sin(t*2*math.PI*1280*tune)*0.14+math.sin(t*2*math.PI*2169*tune)*0.09+mid*0.12)*math.exp(-t*18)
		case .MechanicalBreak:
			value = (low*2.3+mid*0.65)*math.exp(-t*13)+math.sin(t*2*math.PI*59)*0.30*math.exp(-t*15)
			for hit in ([3]f32{0.14, 0.33, 0.61}) {
				local := t-hit
				if local < 0 { continue }
				value += (math.sin(local*2*math.PI*237*tune)*0.17+math.sin(local*2*math.PI*491*tune)*0.075+mid*0.4)*math.exp(-local*26)*(1-hit)
			}
		case .KickSwing: value = mid*0.5*math.sin(t/duration*math.PI)*math.exp(-t*8)
		case .KickHit: value = (low*1.7+mid*0.45+math.sin(t*2*math.PI*115)*0.24)*math.exp(-t*30)
		case .FragmentFire: value = (low*2.8+mid*0.55+math.sin(t*2*math.PI*(88-t*130))*0.32)*math.exp(-t*19)
		case .FragmentBlast:
			value = (low*3.0+mid*0.68)*math.exp(-t*5.5)+math.sin(t*2*math.PI*(65-t*28))*0.38*math.exp(-t*9)
			value += (noise-mid)*0.38*math.exp(-t*140)
		case .EquipRepeater, .EquipFragmentator, .EquipShotgun:
			pitch := f32(710 if kind == .EquipRepeater else (310 if kind == .EquipFragmentator else 470))
			for click in ([3]f32{0.01, 0.11, 0.25}) {
				local := t-click
				if local >= 0 { value += (mid*0.52+low*0.9+math.sin(local*2*math.PI*pitch*tune)*0.16)*math.exp(-local*55) }
			}
			if kind == .EquipShotgun { value += mid*0.26*math.sin(min(t/0.3, 1)*math.PI) }
		case .AmmoPickup:
			value = (mid*0.28+low*0.65)*math.exp(-t*45)
			if t > 0.06 { value += (math.sin((t-0.06)*2*math.PI*1730*tune)*0.12+mid*0.18)*math.exp(-(t-0.06)*38) }
		case .HealthPickup:
			value = math.sin(t*2*math.PI*(590+t*750))*0.16*math.exp(-t*10)+mid*0.15*math.exp(-t*30)
		case .MetalHit: value = (low*0.85+mid*0.55+math.sin(t*2*math.PI*420*tune)*0.17)*math.exp(-t*35)
		case .Ricochet:
			oscillator += (2850-t*7900)*tune*2*math.PI/22050
			value = (math.sin(oscillator)*0.24+mid*0.40)*math.exp(-t*33)
		case .NannyShot:
			value = (mid*0.42+low*0.80+math.sin(t*2*math.PI*1290*tune)*0.16)*math.exp(-t*32)
		case .RabbitGrowl, .RabbitDeath:
			pitch := f32(94 if kind == .RabbitGrowl else 185)*(1-t/duration*0.55)*tune
			oscillator += pitch*2*math.PI/22050
			throat := math.sin(oscillator)+math.sin(oscillator*2.07)*0.45+math.sin(oscillator*3.13)*0.25
			value = (throat*0.17+mid*0.22+low*0.7)*(0.65+0.35*math.sin(t*71))*min(t*22, 1)*(1-t/duration)
		case .RabbitBite:
			value = (mid*0.85+low*2.5)*math.exp(-t*26)+math.sin(t*2*math.PI*132)*0.28*math.exp(-t*18)
		case .DryFire: value = (mid*0.22+noise*0.07)*math.exp(-t*90)
		case .GCMark:
			pulse := math.mod(t, 0.22)
			value = (math.sin(t*2*math.PI*185)*0.23+math.sin(t*2*math.PI*370)*0.09+mid*0.06)*min(pulse*100, 1)*math.exp(-pulse*13)
		case .GCSweep:
			value = (low*1.5+mid*0.45+math.sin(t*2*math.PI*87)*0.16)*math.sin(t/duration*math.PI)
		case .GCOpen:
			value = (math.sin(t*2*math.PI*440)*0.19+math.sin(t*2*math.PI*554.37)*0.11)*math.exp(-t*5)+mid*0.20*math.exp(-t*18)
		case .AnvilFall:
			oscillator += (1200-t*850)*2*math.PI/22050
			value = math.sin(oscillator)*0.16*min(t*12, 1)*(1-t/duration)+mid*0.04
		case .AnvilHit:
			value = (math.sin(t*2*math.PI*310)*0.24+math.sin(t*2*math.PI*623)*0.16+mid*0.6+low*1.3)*math.exp(-t*11)
		case .RelayClick: value = (mid*0.35+math.sin(t*2*math.PI*520)*0.18)*math.exp(-t*60)
		case .PowerStart:
			oscillator += (40+t*110)*2*math.PI/22050
			value = (math.sin(oscillator)*0.20+low*1.5+mid*0.20)*min(t*10, 1)*(1-t/duration*0.7)
		case .GateSlide: value = (low*1.2+mid*0.35+math.sin(t*2*math.PI*97)*0.06)*math.sin(t/duration*math.PI)
		case .Shot, .ShotgunFire, .Jump, .JumpLora, .Hurt, .HurtLora, .FaeDeath, .FleshHit, .GibImpact, .Step, .Land, .StepPlate, .StepBoard, .LandPlate, .LandBoard, .Wing, .Collect, .Hit, .Explosion: unreachable()
		}
		samples[i] = clamp(value*min(t*1500, 1)*min((duration-t)*80, 1), -0.75, 0.75)
	}
	return count
}

synthesize_enemy_cue :: proc(kind: Sound_Kind, variant: int) -> rl.Sound {
	samples: [22050]f32
	count := enemy_cue_samples(kind, variant, samples[:])
	if kind == .FragmentFire {
		// Layer the licensed gun transient over the fragmentator's low body.
		clips := [4][]u8{#load("../assets/audio/shot-0.wav", []u8), #load("../assets/audio/shot-1.wav", []u8), #load("../assets/audio/shot-2.wav", []u8), #load("../assets/audio/shot-3.wav", []u8)}
		data := clips[variant%len(clips)]
		shot := rl.LoadWaveFromMemory(".wav", raw_data(data), i32(len(data)))
		assert(rl.IsWaveValid(shot))
		defer rl.UnloadWave(shot)
		rl.WaveFormat(&shot, 22050, 32, 1)
		pcm := cast([^]f32)shot.data
		for i in 0..<count {
			source := int(f32(i)*0.82)
			if source >= int(shot.frameCount) { break }
			samples[i] = clamp(samples[i]*0.65+pcm[source]*0.70, -0.85, 0.85)
		}
	}
	wave := rl.Wave{frameCount = u32(count), sampleRate = 22050, sampleSize = 32, channels = 1, data = &samples[0]}
	return rl.LoadSoundFromWave(wave)
}

audio_events :: proc(a: ^Audio, g: ^game.State) {
	Candidate :: struct { kind: Sound_Kind, volume, pan, priority: f32 }
	selected: [8]Candidate
	count := 0
	// Saturating catch-up also handles a wrapped sequence counter. A load/reset
	// calls audio_sync, so old events are never replayed by the new world.
	pending := min(g.sound_sequence-a.events, u32(len(g.sound_events)))
	for offset in 0..<pending {
		sequence := g.sound_sequence-pending+offset+1
		event := g.sound_events[(sequence-1)%u32(len(g.sound_events))]
		if event.sequence != sequence { continue }
		volume, pan := game.sound_projection(g.world, &g.player, event.position, 90 if event.cue == .FragmentBlast else 48)
		if volume < 0.02 { continue }
		priority := volume*(2 if event.cue <= .NannyOpen || event.cue == .GCMark || event.cue == .AnvilFall else f32(1))
		index := count
		if index == len(selected) {
			index = 0
			for candidate, i in selected { if candidate.priority < selected[index].priority { index = i } }
			if priority <= selected[index].priority { continue }
		} else { count += 1 }
		gain := f32(0.60)
		if event.cue == .FleshHit || event.cue == .MetalHit { gain = 0.38 }
		selected[index] = {cue_sound(event.cue), volume*gain, pan, priority}
	}
	used: [Sound_Kind]int
	for _ in 0..<count {
		index := 0
		for candidate, i in selected[:count] { if candidate.priority > selected[index].priority { index = i } }
		candidate := &selected[index]
		bank := &a.banks[candidate.kind]
		if used[candidate.kind] < bank.count {
			voice := bank.voices[bank.cursor]
			rl.SetSoundVolume(voice, candidate.volume*a.effects_gain)
			rl.SetSoundPan(voice, candidate.pan)
			rl.PlaySound(voice)
			bank.cursor = (bank.cursor+1)%bank.count
			used[candidate.kind] += 1
		}
		candidate.priority = -1
	}
}
