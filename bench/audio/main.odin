package audio_checks

import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import "core:time"
import app "../../src"
import game "../../src/game"
import music "../../src/music"

main :: proc() {
	bed: app.Ambience
	defer app.ambience_destroy(&bed)
	for &loop, kind in bed.loops {
		loop = make([]f32, app.AMBIENCE_RATE*4)
		app.ambience_samples(kind, loop)
		peak, energy, delta := f32(0), f32(0), f32(0)
		for sample, i in loop {
			assert(!math.is_nan(sample) && abs(sample) <= 0.38)
			peak, energy = max(peak, abs(sample)), energy+sample*sample
			if i > 0 { delta = max(delta, abs(sample-loop[i-1])) }
		}
		seam := abs(loop[0]-loop[len(loop)-1])
		assert(energy/f32(len(loop)) > 0.0001 && seam <= delta*1.5)
		path: [128]u8
		name := fmt.bprintf(path[:], "build/ambience-%v.f32", kind)
		assert(os.write_entire_file(name, mem.slice_to_bytes(loop)) == nil)
		fmt.printf("%v: peak %.3f RMS %.3f seam %.5f (max adjacent %.5f)\n", kind, peak, math.sqrt(energy/f32(len(loop))), seam, delta)
	}
	buffer: [app.AMBIENCE_FRAMES*2]f32
	target: [app.Ambience_Kind]f32
	target[.Hall], target[.Machine_On] = 0.4, 0.3
	start := time.tick_now()
	{
		context.allocator, context.temp_allocator = mem.panic_allocator(), mem.panic_allocator()
		for _ in 0..<200 { app.ambience_mix(&bed, target, buffer[:]) }
	}
	fmt.printf("Stereo fill: %.3f ms per %d-frame buffer; samples generated per %.2f ms of audio\n", time.duration_seconds(time.tick_since(start))*1000/200, app.AMBIENCE_FRAMES, f64(app.AMBIENCE_FRAMES)/app.AMBIENCE_RATE*1000)
	for v in buffer { assert(abs(v) < 0.2 && !math.is_nan(v)) }
	for i in 0..<len(buffer) { buffer[i] = (f32(i)/f32(len(buffer)-1)-0.5)*12 }
	app.audio_limiter(&buffer[0], u32(len(buffer)/2))
	for v, i in buffer {
		assert(abs(v) < 1 && !math.is_nan(v))
		if i > 0 { assert(v >= buffer[i-1]) }
	}
	w: game.World
	game.world_init_ram(&w)
	defer game.world_destroy(&w)
	g := game.State{world = &w}
	game.init(&g)
	g.player.position = w.checkpoints[4].position
	quiet := app.ambience_targets(&g)
	g.lift_started = true
	running := app.ambience_targets(&g)
	assert(quiet[.Machine_Off] > 0 && quiet[.Machine_On] == 0 && running[.Machine_On] > 0 && running[.Machine_Off] == 0)
	for _ in 0..<16 { app.ambience_mix(&bed, {}, buffer[:]) }
	for v in buffer { assert(abs(v) < 0.00001) }
	fmt.println("AUDIO CHECK OK: six seamless beds, bounded crossfade, power state, silence and stereo soft limiter; no device required.")
	player: app.Music_Player
	app.music_scores(&player)
	defer app.music_destroy(&player)
	for &score, track in player.scores {
		music.reset(&player.synth)
		player.synth.gain, player.synth.stolen = 0, 0
		clip := make([]f32, int(score.frames)*2)
		peak, energy, dc := f32(0), f64(0), f64(0)
		voices := 0
		music_start := time.tick_now()
		for at := 0; at < len(clip); at += app.MUSIC_FRAMES*2 {
			end := min(len(clip), at+app.MUSIC_FRAMES*2)
			{
				context.allocator, context.temp_allocator = mem.panic_allocator(), mem.panic_allocator()
				music.mix(&player.synth, &score, clip[at:end], 0.33)
			}
			active := 0
			for v in player.synth.voices { if v.active { active += 1 } }
			voices = max(voices, active)
		}
		elapsed := time.duration_seconds(time.tick_since(music_start))
		for sample in clip {
			assert(!math.is_nan(sample) && abs(sample) < 1)
			peak, energy, dc = max(peak, abs(sample)), energy+f64(sample*sample), dc+f64(sample)
		}
		assert(energy/f64(len(clip)) > 0.00005 && abs(dc/f64(len(clip))) < 0.005)
		assert(player.synth.stolen == 0, "Bundled score exceeded the fixed voice budget")
		path: [128]u8
		name := fmt.bprintf(path[:], "build/music-%v.f32", track)
		assert(os.write_entire_file(name, mem.slice_to_bytes(clip)) == nil)
		seam := clip[len(clip)-2]
		music.mix(&player.synth, &score, buffer[:], 0.33)
		assert(player.synth.loops == 1 && abs(buffer[0]-seam) < 0.1)
		fmt.printf("MIDI %v: %.2f sec, peak %.3f RMS %.3f, voices <=%d/32, %.2f%% of one CPU core; loop seam %.6f; %s\n", track, f64(score.frames)/music.RATE, peak, math.sqrt(energy/f64(len(clip))), voices, elapsed/(f64(score.frames)/music.RATE)*100, abs(buffer[0]-seam), name)
		delete(clip)
	}
	fmt.println("MUSIC CHECK OK: three actual MIDI scores, complete sample-clock playback, loop/release, finite stereo mix, no voice stealing or fill allocations.")
}
