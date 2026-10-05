package tests

import "core:testing"
import "core:mem"
import "core:math"
import music "../src/music"

@(test)
midi_scores_are_bounded_and_block_size_does_not_change_the_audio :: proc(t: ^testing.T) {
	files := [3][]u8{#load("../assets/music/cold-boot.mid", []u8), #load("../assets/music/collector.mid", []u8), #load("../assets/music/transfer.mid", []u8)}
	for bytes in files {
		score: music.Score
		defer music.destroy(&score)
		testing.expect(t, music.decode(&score, bytes))
		testing.expect(t, score.frames > music.RATE*90 && len(score.events) > 1000)
		a, b: music.Synth
		music.init(&a); music.init(&b)
		whole, split: [8192]f32
		{
			context.allocator, context.temp_allocator = mem.panic_allocator(), mem.panic_allocator()
			music.mix(&a, &score, whole[:], 0.33)
			music.mix(&b, &score, split[:2048], 0.33)
			music.mix(&b, &score, split[2048:], 0.33)
		}
		testing.expect_value(t, whole, split)
		energy := f32(0)
		for sample in whole { energy += sample*sample; testing.expect(t, abs(sample) < 1 && !math.is_nan(sample)) }
		testing.expect(t, energy > 0.001)
		// Failed decoding is transactional and retains the previous score.
		count, duration := len(score.events), score.frames
		for size in ([6]int{0, 5, 14, 21, len(bytes)/2, len(bytes)-1}) { testing.expect(t, !music.decode(&score, bytes[:size])) }
		testing.expect(t, len(score.events) == count && score.frames == duration)
	}
}

@(test)
midi_tempo_running_status_and_note_releases_use_the_sample_clock :: proc(t: ^testing.T) {
	// One quarter note at 120 BPM, followed by four at 240 BPM.
	data := []u8{77,84,104,100, 0,0,0,6, 0,0,0,1, 1,224, 77,84,114,107, 0,0,0,31,
		0,0x90,60,100, 0x83,0x60,60,0, 0,0xff,0x51,3,3,0xd0,0x90,
		0,0x90,64,100, 0x87,0x40,64,0, 0x87,0x40,0xff,0x2f,0}
	// The explicit length comes from the track payload, not the whole file.
	data[21] = u8(len(data)-22)
	score: music.Score
	defer music.destroy(&score)
	testing.expect(t, music.decode(&score, data))
	testing.expect(t, score.frames == music.RATE*1.5 && len(score.events) == 4)
	testing.expect(t, score.events[1].frame == music.RATE/2 && score.events[2].frame == music.RATE/2)
	synth: music.Synth
	music.init(&synth)
	buffer: [1024]f32
	for _ in 0..<int(score.frames)/512+2 { music.mix(&synth, &score, buffer[:], 0.3) }
	testing.expect(t, synth.loops == 1)
	music.dispatch(&synth, {status = 0xb0, a = 123})
	for _ in 0..<100 { music.mix(&synth, &score, buffer[:], 0) }
	for sample in buffer { testing.expect(t, abs(sample) < 0.00001) }
}
