package main

import "core:math"
import rl "vendor:raylib"
import game "game"

Sound_Kind :: enum { Shot, Jump, JumpLora, Step, Land, StepPlate, StepBoard, LandPlate, LandBoard, Wing, Collect, Hit, Explosion, Hurt, HurtLora, SentryCharge, RushCharge, CrabCharge, KettleWhistle, NannyOpen, EnemyShot, ClawSnap, SteamBurst, ShieldBreak, MechanicalBreak, KickSwing, KickHit, FragmentFire, FragmentBlast, DryFire, GCMark, GCSweep, GCOpen, AnvilFall, AnvilHit, RelayClick, PowerStart, GateSlide, FaeDeath, ShotgunFire, GibImpact, EquipRepeater, EquipFragmentator, EquipShotgun, AmmoPickup, HealthPickup, FleshHit, MetalHit, Ricochet, NannyShot, RabbitGrowl, RabbitBite, RabbitDeath }

// Shared by bank loading and the cue validation bench. Recorded cues must not
// silently exercise obsolete synthesized substitutes in regression checks.
RECORDED_SOUNDS :: bit_set[Sound_Kind]{.Shot, .ShotgunFire, .Jump, .JumpLora, .Hurt, .HurtLora, .FleshHit, .GibImpact, .FaeDeath}
Sound_Bank :: struct { voices: [8]rl.Sound, count, cursor: int }
Audio :: struct {
	ready, muted: bool,
	effects_gain, voice_gain, ambience_gain, music_gain: f32,
	banks: [Sound_Kind]Sound_Bank,
	ambience: Ambience,
	music: Music_Player,
	shots, jumps, steps, lands, wings, damage, kills: u32,
	events: u32,
	pickups: u32,
	cores: int,
}

audio_soft_limit :: proc "contextless" (value: f32) -> f32 {
	magnitude := abs(value)
	if magnitude <= 0.85 { return value }
	excess := magnitude-0.85
	return (0.85+0.15*excess/(0.15+excess))*(1 if value > 0 else f32(-1))
}

// raylib's existing mixer calls this on interleaved float stereo. It has no
// state, allocator, lock or look-ahead buffer; ordinary levels are unchanged.
// Only simultaneous loud transients receive a smooth knee before hard clipping.
audio_limiter :: proc "c" (buffer: rawptr, frames: u32) {
	samples := cast([^]f32)buffer
	for i in 0..<int(frames)*2 { samples[i] = audio_soft_limit(samples[i]) }
}

recorded_sound :: proc(kind: Sound_Kind, variant: int) -> rl.Sound {
	assert(kind in RECORDED_SOUNDS)
	data: []u8
	if kind == .FleshHit || kind == .GibImpact || kind == .FaeDeath {
		return recorded_combat_sound(kind, variant)
	}
	if kind == .ShotgunFire {
		clips := [4][]u8{
			#load("../assets/audio/shotgun-0.wav", []u8), #load("../assets/audio/shotgun-1.wav", []u8),
			#load("../assets/audio/shotgun-2.wav", []u8), #load("../assets/audio/shotgun-3.wav", []u8),
		}
		data = clips[variant]
	} else if kind == .Shot {
		clips := [4][]u8{
			#load("../assets/audio/shot-0.wav", []u8), #load("../assets/audio/shot-1.wav", []u8),
			#load("../assets/audio/shot-2.wav", []u8), #load("../assets/audio/shot-3.wav", []u8),
		}
		data = clips[variant]
 } else if (kind == .JumpLora || kind == .HurtLora) {
  clips := [3][]u8{#load("../assets/audio/lora-jump-0.wav", []u8), #load("../assets/audio/lora-jump-1.wav", []u8), #load("../assets/audio/lora-jump-2.wav", []u8)}
  data = clips[variant]
 } else {
  assert(kind == .Jump || kind == .Hurt)
		clips := [4][]u8{
			#load("../assets/audio/jump-0.wav", []u8), #load("../assets/audio/jump-1.wav", []u8),
			#load("../assets/audio/jump-2.wav", []u8), #load("../assets/audio/jump-3.wav", []u8),
		}
		data = clips[variant]
	}
	wave := rl.LoadWaveFromMemory(".wav", raw_data(data), i32(len(data)))
	assert(rl.IsWaveValid(wave), "Embedded sound decode failed")
	defer rl.UnloadWave(wave)
	return rl.LoadSoundFromWave(wave)
}

// Environmental/UI transients are generated once. Weapon and voice use recordings.
synthesize :: proc(kind: Sound_Kind, variant: int) -> rl.Sound {
	assert(!(kind in RECORDED_SOUNDS))
	if kind >= .SentryCharge { return synthesize_enemy_cue(kind, variant) }
	samples: [22050]f32
	duration := f32(0.16)
	if kind == .Land || kind == .LandPlate || kind == .LandBoard { duration = 0.24 }
	if kind == .Wing { duration = 0.35 }
	if kind == .Collect { duration = 0.7 }
	if kind == .Explosion { duration = 0.55 }
	count := int(duration*22050)
	seed := u32(78137+variant*3191+int(kind)*671)
	low, mid := f32(0), f32(0)
	tune := 0.94+f32(variant)*0.04
	for i in 0..<count {
		t := f32(i)/22050
		seed = seed*1664525+1013904223
		noise := f32(seed>>16)/32768-1
		low += (noise-low)*0.065
		mid += (noise-mid)*0.32
		high := noise-mid
		value := f32(0)
		switch kind {
		case .Shot, .Jump, .JumpLora, .Hurt, .HurtLora: panic("Weapon and voice must use recorded_sound")
		case .Step, .Land, .StepPlate, .StepBoard, .LandPlate, .LandBoard:
			landing := kind == .Land || kind == .LandPlate || kind == .LandBoard
			force := f32(1) if landing else f32(0.52)
			value = force*((low*1.7+math.sin(t*2*math.PI*78*tune)*0.3)*math.exp(-t*38)+high*0.17*math.exp(-t*120))
			value += mid*0.15*math.exp(-t*24)*min(t*140, 1)
			if kind == .StepPlate || kind == .LandPlate { value += force*(math.sin(t*2*math.PI*310*tune)*0.11+math.sin(t*2*math.PI*473*tune)*0.05)*math.exp(-t*22) }
			if kind == .StepBoard || kind == .LandBoard { value = value*0.65+force*mid*0.28*math.exp(-t*55) }
		case .Wing:
			value = (mid*0.6+low*0.7)*math.exp(-t*13)*min(t*100, 1)
			value += high*0.12*math.exp(-t*80)
		case .Collect:
			freq := 440*math.pow(f32(2), math.floor(t/duration*3)*f32(5.0/12.0))
			value = (math.sin(t*freq*2*math.PI)*0.2+math.sin(t*freq*4*math.PI)*0.05)*math.pow(1-t/duration, 2)
		case .Hit:
			value = (mid*0.3+low+math.sin(t*2*math.PI*95)*0.18)*math.exp(-t*27)
		case .Explosion:
			value = (low*1.7+mid*0.3+math.sin(t*2*math.PI*55)*0.24)*math.exp(-t*10)
		case .SentryCharge, .RushCharge, .CrabCharge, .KettleWhistle, .NannyOpen, .EnemyShot, .ClawSnap, .SteamBurst, .ShieldBreak, .MechanicalBreak, .KickSwing, .KickHit, .FragmentFire, .FragmentBlast, .DryFire, .GCMark, .GCSweep, .GCOpen, .AnvilFall, .AnvilHit, .RelayClick, .PowerStart, .GateSlide, .FaeDeath, .ShotgunFire, .GibImpact, .EquipRepeater, .EquipFragmentator, .EquipShotgun, .AmmoPickup, .HealthPickup, .FleshHit, .MetalHit, .Ricochet, .NannyShot, .RabbitGrowl, .RabbitBite, .RabbitDeath: unreachable()
		}
		// Sub-millisecond onset and end fade avoid discontinuities at buffer edges.
		samples[i] = clamp(value*min(t*3000, 1)*min((duration-t)*400, 1), -0.9, 0.9)
	}
	wave := rl.Wave{frameCount = u32(count), sampleRate = 22050, sampleSize = 32, channels = 1, data = &samples[0]}
	return rl.LoadSoundFromWave(wave)
}

AUDIO_BANK_COUNT :: len([Sound_Kind]Sound_Bank{})
AMBIENCE_KIND_COUNT :: len([Ambience_Kind][]f32{})
AUDIO_LOAD_STEPS :: AUDIO_BANK_COUNT+AMBIENCE_KIND_COUNT+3

audio_init :: proc(a: ^Audio, muted: bool) {
	for stage in 0..<AUDIO_LOAD_STEPS { if audio_init_step(a, muted, stage) { break } }
}

// The same banks are prepared once; the browser yields between sound families.
audio_init_step :: proc(a: ^Audio, muted: bool, stage: int) -> bool {
	if stage == 0 {
		a.muted = muted
		a.effects_gain, a.voice_gain, a.ambience_gain, a.music_gain = 1, 1, 0.55, 0.55
		rl.InitAudioDevice()
		a.ready = rl.IsAudioDeviceReady()
		if !a.ready { return true }
		rl.SetMasterVolume(0 if muted else 0.8)
	} else if stage <= AUDIO_BANK_COUNT {
		kind := Sound_Kind(stage-1)
		bank := &a.banks[kind]
		bank.count = 8 if kind == .Shot else (3 if (kind == .JumpLora || kind == .HurtLora) else 4)
		for &voice, i in bank.voices[:bank.count] {
			// Independent cursors preserve tails; aliases share their sample data.
			if i >= 4 { voice = rl.LoadSoundAlias(bank.voices[i-4])
			} else if kind in RECORDED_SOUNDS { voice = recorded_sound(kind, i)
			} else { voice = synthesize(kind, i) }
			assert(rl.IsSoundValid(voice), "Sound upload failed")
		}
	} else if stage == AUDIO_BANK_COUNT+1 {
		ambience_init_stream(&a.ambience)
	} else if stage < AUDIO_LOAD_STEPS-1 {
		ambience_init_loop(&a.ambience, Ambience_Kind(stage-AUDIO_BANK_COUNT-2))
	} else {
		music_init(&a.music)
		assert(a.banks[.Shot].voices[0].stream.channels == 2 && a.banks[.Shot].voices[0].stream.sampleSize == 32, "Mixer processor expects the raylib float-stereo format")
		rl.AttachAudioMixedProcessor(audio_limiter)
		return true
	}
	return false
}

audio_sync :: proc(a: ^Audio, g: ^game.State) {
	a.shots, a.jumps, a.damage, a.kills, a.cores = g.shot_sequence, g.jump_sequence, g.damage_sequence, g.kill_sequence, g.collected
	a.steps, a.lands, a.wings = g.step_sequence, g.land_sequence, g.glide_sequence
	a.events = g.sound_sequence
	a.pickups = g.pickup_sequence
}

audio_play :: proc(a: ^Audio, kind: Sound_Kind, volume: f32 = 1, count: u32 = 1) {
	if !a.ready { return }
	bank := &a.banks[kind]
	for _ in 0..<min(count, u32(bank.count)) {
		voice := bank.voices[bank.cursor]
		rl.SetSoundVolume(voice, volume*(a.voice_gain if kind == .Jump || kind == .Hurt || kind == .JumpLora || kind == .HurtLora else a.effects_gain))
		rl.SetSoundPitch(voice, 0.79 if kind == .Hurt else (0.88 if kind == .HurtLora else 1))
		rl.SetSoundPan(voice, 0)
		rl.PlaySound(voice)
		bank.cursor = (bank.cursor+1)%bank.count
	}
}

// Discard one-shot effects, but retain the queued music/ambience and their
// sample clocks. A pause is not a restart of either persistent stream.
audio_pause :: proc(a: ^Audio) {
	if !a.ready { return }
	for &bank in a.banks { for voice in bank.voices[:bank.count] { rl.StopSound(voice) } }
	if a.ambience.ready { rl.PauseAudioStream(a.ambience.stream) }
	if a.music.ready { rl.PauseAudioStream(a.music.stream) }
}

// Stream servicing belongs to presentation: winning stops simulation ticks,
// while its music continues; cancelling an intro returns to a silent pause.
audio_update_streams :: proc(a: ^Audio, g: ^game.State, frontend, active: bool) {
	if !a.ready { return }
	if a.ambience.ready && (!active || frontend) { rl.PauseAudioStream(a.ambience.stream) }
	if !active {
		if a.music.ready { rl.PauseAudioStream(a.music.stream) }
		return
	}
	if frontend { music_stream(a, .Transfer, a.music_gain*0.40)
	} else { ambience_update(a, g); music_update(a, g) }
}

audio_update :: proc(a: ^Audio, g: ^game.State) {
	if a.ready && !a.muted {
		if g.shot_sequence > a.shots { audio_play(a, .Shot, 0.8, g.shot_sequence-a.shots) }
		if a.jumps != g.jump_sequence { audio_play(a, .JumpLora if g.hero == .Lora else .Jump, 0.65 if g.hero == .Lora else 0.75) }
		if a.steps != g.step_sequence { audio_play(a, foot_sound(g.world, g.player.position, false), 0.22) }
		if a.lands != g.land_sequence { audio_play(a, foot_sound(g.world, g.player.position, true), 0.15+g.player.land_strength*0.5) }
		if a.wings != g.glide_sequence { audio_play(a, .Wing, 0.7) }
		if a.cores < g.collected { audio_play(a, .Collect) }
		if a.damage != g.damage_sequence {
			audio_play(a, .Hit, 0.55+g.player.hurt_strength*0.4)
			if g.player.hurt_strength >= 0.55 { audio_play(a, .HurtLora if g.hero == .Lora else .Hurt, 0.9) }
		}
		audio_events(a, g)
	}
	audio_sync(a, g)
}

audio_destroy :: proc(a: ^Audio) {
	if !a.ready { return }
	rl.DetachAudioMixedProcessor(audio_limiter)
	for &bank in a.banks {
		for voice in bank.voices[min(4, bank.count):bank.count] { rl.UnloadSoundAlias(voice) }
		for voice in bank.voices[:min(4, bank.count)] { rl.UnloadSound(voice) }
	}
	ambience_destroy(&a.ambience)
	music_destroy(&a.music)
	rl.CloseAudioDevice()
}
