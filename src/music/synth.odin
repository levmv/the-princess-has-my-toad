package music

import "core:math"

Voice :: struct {
	phase, modulator, increment, amplitude, envelope, release, age, low: f32,
	channel, note, instrument: u8,
	noise: u32,
	active, released: bool,
}
Channel :: struct { volume, expression, pan, bend: f32, program: u8, sustain: bool }
Synth :: struct {
	voices: [32]Voice,
	channels: [16]Channel,
	wave: [2048]f32,
	pitches: [128]f32,
	delay: [2][4096]f32,
	delay_cursor: int,
	frame, loops: u64,
	event: int,
	gain: f32,
	stolen: u32,
}

init :: proc(s: ^Synth) {
	s^ = {}
	for &sample, i in s.wave { sample = math.sin(f32(i)*2*math.PI/f32(len(s.wave))) }
	for &pitch, i in s.pitches { pitch = 440*math.pow(f32(2), f32(i-69)/12)/RATE }
	reset(s)
}

reset :: proc(s: ^Synth) {
	s.voices, s.delay, s.delay_cursor, s.frame, s.event, s.loops = {}, {}, 0, 0, 0, 0
	for &channel in s.channels { channel = Channel{volume = 0.8, expression = 1, pan = 0.5, bend = 1} }
}

sine :: proc(s: ^Synth, phase: f32) -> f32 {
	x := phase*f32(len(s.wave))
	index := int(math.floor(x))
	fraction := x-f32(index)
	a, b := s.wave[index & (len(s.wave)-1)], s.wave[(index+1) & (len(s.wave)-1)]
	return a+(b-a)*fraction
}

dispatch :: proc(s: ^Synth, e: Event) {
	channel := e.status & 15
	c := &s.channels[channel]
	kind := e.status & 0xf0
	if kind == 0x80 || (kind == 0x90 && e.b == 0) {
		for &v in s.voices { if v.active && v.channel == channel && v.note == e.a && channel != 9 { v.released = true } }
		return
	}
	switch kind {
	case 0x90:
		chosen, weakest := -1, f32(1e9)
		for v, i in s.voices {
			if !v.active { chosen = i; break }
			weight := v.amplitude*v.envelope
			if weight < weakest { chosen, weakest = i, weight }
		}
		if s.voices[chosen].active { s.stolen += 1 }
		v := &s.voices[chosen]
		v^ = Voice{active = true, channel = channel, note = e.a, instrument = c.program, increment = s.pitches[e.a], amplitude = f32(e.b)/127, noise = u32(e.a)*7919+u32(s.frame%100000)*13+1, envelope = 1, release = 1}
		// GM channel 10, with the drum notes used by the bundled scores.
		if channel == 9 && (e.a == 42 || e.a == 44 || e.a == 46) {
			for &other in s.voices { if &other != v && other.channel == 9 && (other.note == 42 || other.note == 46) { other.released = true } }
		}
	case 0xc0: c.program = e.a
	case 0xb0:
		switch e.a {
		case 7: c.volume = f32(e.b)/127
		case 10: c.pan = f32(e.b)/127
		case 11: c.expression = f32(e.b)/127
		case 64: c.sustain = e.b >= 64
		case 120, 123:
			for &v in s.voices { if v.channel == channel { v.released = true; if e.a == 120 { v.active = false } } }
		}
	case 0xe0: c.bend = math.pow(f32(2), (f32(u16(e.a)|(u16(e.b)<<7))-8192)/8192/6)
	}
}

voice_sample :: proc(s: ^Synth, v: ^Voice) -> f32 {
	c := &s.channels[v.channel]
	v.age += 1.0/RATE
	inc := v.increment*c.bend
	v.phase += inc
	v.phase -= math.floor(v.phase)
	v.modulator += inc*2.003
	v.modulator -= math.floor(v.modulator)
	value := f32(0)
	attack := min(1, v.age*350)
	if v.channel == 9 {
		v.noise = v.noise*1664525+1013904223
		noise := f32(v.noise>>8)/8388608-1
		v.low += (noise-v.low)*0.2
		switch v.note {
		case 35, 36:
			v.increment = (46+100*max(0, 1-v.age*24))/RATE
			v.envelope *= 0.99948
			value = sine(s, v.phase)*0.80+(noise-v.low)*max(0, 1-v.age*90)*0.18
		case 38, 40:
			v.increment = 185.0/RATE
			v.envelope *= 0.99922
			value = (noise-v.low)*0.6+sine(s, v.phase)*max(0, 1-v.age*18)*0.34
		case 42, 44, 46:
			v.envelope *= 0.99967 if v.note == 46 else 0.9974
			value = (noise-v.low)*0.22
		case 49, 51:
			v.envelope *= 0.99989
			value = (noise-v.low)*0.24+sine(s, v.phase+sine(s, v.modulator)*0.4)*0.07
		case: // Toms / percussion.
			v.increment = max(35, 75+f32(int(v.note)-40)*8)/RATE
			v.envelope *= 0.9995
			value = sine(s, v.phase)*0.5+v.low*0.12
		}
		if v.released { v.release *= 0.995 }
	} else {
		if v.released && !c.sustain { v.release *= 0.99965 if v.instrument == 50 else 0.9986 }
		switch v.instrument {
		case 30: // Palm-muted FM guitar: rounded cabinet, pick transient.
			v.envelope *= 0.99996
			fm := sine(s, v.modulator)*(0.16+0.10*max(0, 1-v.age*9))
			value = sine(s, v.phase+fm)*0.7+sine(s, v.phase*2)*0.13
			v.low += (value-v.low)*0.28
			value = v.low*0.44
		case 38: // Firm low bass without an external SoundFont.
			v.envelope *= 0.99998
			value = (sine(s, v.phase)+sine(s, v.phase+sine(s, v.modulator)*0.08)*0.35)*0.40
		case 50: // Slow, dark string bed.
			attack = min(1, v.age*3)
			value = (sine(s, v.phase)+sine(s, v.modulator)*0.35+sine(s, v.phase*3)*0.10)*0.18
		case 81: // Restrained lead, not a piercing square wave.
			value = (sine(s, v.phase+sine(s, v.modulator)*0.11)+sine(s, v.phase*2)*0.17)*0.26
		case: // Bell / electric keys used in the quiet middle section.
			v.envelope *= 0.99990
			value = sine(s, v.phase+sine(s, v.modulator)*v.envelope*0.2)*0.28
		}
	}
	if v.envelope*v.release < 0.0005 || v.age > 20 { v.active = false }
	return value*v.amplitude*v.envelope*v.release*attack*c.volume*c.expression
}

// Interleaved stereo; fixed voices and delay storage, no allocation or locks.
// Sample-clock scheduling stays independent of render/simulation frame rate.
mix :: proc(s: ^Synth, score: ^Score, samples: []f32, gain: f32) {
	assert(len(samples)%2 == 0 && score.frames > 0)
	for i in 0..<len(samples)/2 {
		if s.frame >= score.frames {
			s.frame, s.event = 0, 0
			s.loops += 1
			for &v in s.voices { v.released = true }
		}
		for s.event < len(score.events) && score.events[s.event].frame <= s.frame {
			dispatch(s, score.events[s.event]); s.event += 1
		}
		left, right := f32(0), f32(0)
		for &v in s.voices {
			if !v.active { continue }
			value := voice_sample(s, &v)
			pan := s.channels[v.channel].pan
			left += value*(1-pan*0.65); right += value*(0.35+pan*0.65)
		}
		// Short cross-feedback reflections add space while preserving attacks.
		a, b := s.delay[0][s.delay_cursor], s.delay[1][(s.delay_cursor+997)%4096]
		s.delay[0][s.delay_cursor], s.delay[1][s.delay_cursor] = left+b*0.22, right+a*0.22
		s.delay_cursor = (s.delay_cursor+1)%4096
		s.gain += (gain-s.gain)*0.00025
		left, right = (left+a*0.15)*s.gain, (right+b*0.15)*s.gain
		samples[i*2], samples[i*2+1] = left/(1+abs(left)*0.4), right/(1+abs(right)*0.4)
		s.frame += 1
	}
}
