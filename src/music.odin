package main

import rl "vendor:raylib"
import game "game"
import music "music"

Music_Track :: enum { Cold_Boot, Collector, Transfer }
MUSIC_FRAMES :: 2048
Music_Player :: struct {
	stream: rl.AudioStream,
	scores: [Music_Track]music.Score,
	synth: music.Synth,
	current: Music_Track,
	ready: bool,
}

music_scores :: proc(player: ^Music_Player) {
	data := [Music_Track][]u8{
		.Cold_Boot = #load("../assets/music/cold-boot.mid", []u8),
		.Collector = #load("../assets/music/collector.mid", []u8),
		.Transfer = #load("../assets/music/transfer.mid", []u8),
	}
	for bytes, track in data { assert(music.decode(&player.scores[track], bytes), "Invalid embedded MIDI score") }
	music.init(&player.synth)
}

music_init :: proc(player: ^Music_Player) {
	rl.SetAudioStreamBufferSizeDefault(MUSIC_FRAMES)
	player.stream = rl.LoadAudioStream(music.RATE, 32, 2)
	player.ready = rl.IsAudioStreamValid(player.stream)
	if !player.ready { return }
	music_scores(player)
	rl.SetAudioStreamPan(player.stream, 0)
	// Play resets raylib's queue. Arm it once, before filling, then use only
	// Pause/Resume so queued samples survive menus and loss of focus.
	rl.PlayAudioStream(player.stream)
	rl.PauseAudioStream(player.stream)
}

music_destroy :: proc(player: ^Music_Player) {
	if player.ready { rl.UnloadAudioStream(player.stream) }
	for &score in player.scores { music.destroy(&score) }
	player^ = {}
}

music_track :: proc(g: ^game.State) -> Music_Track {
	if g.boss.id != 0 && g.boss.phase != .Dormant && g.boss.phase != .Dead { return .Collector }
	return .Cold_Boot if g.world.sector.key == .RAM_Bank_01 else .Transfer
}

music_update :: proc(a: ^Audio, g: ^game.State) {
	p := &a.music
	if !p.ready { return }
	requested := music_track(g)
	gain := a.music_gain*0.60
	if g.won { gain *= 0.45 }
	for e in g.enemies[:g.enemy_count] {
		if e.health > 0 && e.phase == .Windup && game.length(e.position-g.player.position) < 25 { gain *= 0.72; break }
	}
	music_stream(a, requested, gain)
}

music_stream :: proc(a: ^Audio, requested: Music_Track, requested_gain: f32) {
	p := &a.music
	if !p.ready { return }
	gain := requested_gain
	for _ in 0..<2 {
		if !rl.IsAudioStreamProcessed(p.stream) { break }
		// Fade through silence when changing scores, including boss entry and
		// exit. A paused stream keeps its musical position on resume.
		if requested != p.current {
			gain = 0
			if p.synth.gain < 0.001 { p.current = requested; music.reset(&p.synth); gain = requested_gain }
		}
		samples: [MUSIC_FRAMES*2]f32
		music.mix(&p.synth, &p.scores[p.current], samples[:], gain)
		rl.UpdateAudioStream(p.stream, &samples[0], MUSIC_FRAMES)
	}
	if !rl.IsAudioStreamPlaying(p.stream) { rl.ResumeAudioStream(p.stream) }
}
