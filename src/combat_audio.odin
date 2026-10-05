package main

import rl "vendor:raylib"

recorded_combat_sound :: proc(kind: Sound_Kind, variant: int) -> rl.Sound {
	clips: [4][]u8
	#partial switch kind {
	case .FleshHit: clips = {#load("../assets/audio/flesh-0.wav", []u8), #load("../assets/audio/flesh-1.wav", []u8), #load("../assets/audio/flesh-2.wav", []u8), #load("../assets/audio/flesh-3.wav", []u8)}
	case .GibImpact: clips = {#load("../assets/audio/gib-0.wav", []u8), #load("../assets/audio/gib-1.wav", []u8), #load("../assets/audio/gib-2.wav", []u8), #load("../assets/audio/gib-3.wav", []u8)}
	case .FaeDeath: clips = {#load("../assets/audio/fae-death-0.wav", []u8), #load("../assets/audio/fae-death-1.wav", []u8), #load("../assets/audio/fae-death-2.wav", []u8), #load("../assets/audio/fae-death-3.wav", []u8)}
	case: unreachable()
	}
	data := clips[variant%len(clips)]
	wave := rl.LoadWaveFromMemory(".wav", raw_data(data), i32(len(data)))
	assert(rl.IsWaveValid(wave), "Embedded combat sound decode failed")
	defer rl.UnloadWave(wave)
	return rl.LoadSoundFromWave(wave)
}
