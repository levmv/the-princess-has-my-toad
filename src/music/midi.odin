package music

RATE :: 22050
MAX_EVENTS :: 16384
MAX_FRAMES :: RATE*60*30

Event :: struct { frame: u64, status, a, b: u8 }
Score :: struct { events: [dynamic]Event, frames: u64 }
Reader :: struct { data: []u8, at: int, bad: bool }

byte_read :: proc(r: ^Reader) -> u8 {
	if r.at >= len(r.data) { r.bad = true; return 0 }
	v := r.data[r.at]; r.at += 1; return v
}

big_read :: proc(r: ^Reader, count: int) -> u32 {
	v := u32(0)
	for _ in 0..<count { v = (v<<8)|u32(byte_read(r)) }
	return v
}

variable_read :: proc(r: ^Reader) -> u32 {
	v := u32(0)
	for _ in 0..<4 {
		b := byte_read(r)
		v = (v<<7)|u32(b & 0x7f)
		if b & 0x80 == 0 { return v }
	}
	r.bad = true
	return 0
}

destroy :: proc(score: ^Score) { delete(score.events); score^ = {} }

// Bounded Standard MIDI File format 0 reader for our authored scores. Convert
// ticks to absolute sample positions once, including tempo changes and running
// status. The audio fill subsequently does no parsing or allocation. Format 1,
// SMPTE timing and external sound banks are deliberately outside this player.
decode :: proc(score: ^Score, data: []u8) -> bool {
	r := Reader{data = data}
	if len(data) > 256*1024 || big_read(&r, 4) != 0x4d546864 || big_read(&r, 4) != 6 { return false }
	if big_read(&r, 2) != 0 || big_read(&r, 2) != 1 { return false }
	division := big_read(&r, 2)
	if division == 0 || division & 0x8000 != 0 || big_read(&r, 4) != 0x4d54726b { return false }
	size := big_read(&r, 4)
	if r.bad || int(size) != len(data)-r.at { return false }
	candidate: Score
	good := false
	defer { if !good { destroy(&candidate) } }
	tempo, running := u32(500000), u8(0)
	frame, remainder := u64(0), u64(0)
	denominator := u64(division)*1000000
	ended := false
	for r.at < len(data) && !r.bad {
		delta := variable_read(&r)
		// Reject unreasonable deltas before the multiplication can overflow.
		if u64(delta) > (u64(MAX_FRAMES)-frame)*denominator/(u64(tempo)*RATE) { return false }
		numerator := u64(delta)*u64(tempo)*RATE+remainder
		frame += numerator/denominator
		remainder = numerator%denominator
		if frame > MAX_FRAMES { return false }
		status := byte_read(&r)
		if status < 0x80 {
			if running == 0 { return false }
			r.at -= 1; status = running
		}
		if status == 0xff {
			kind := byte_read(&r)
			length := int(variable_read(&r))
			if r.bad || length > len(data)-r.at { return false }
			if kind == 0x51 {
				if length != 3 { return false }
				tempo = big_read(&r, 3)
				if tempo < 10000 || tempo > 4000000 { return false }
			} else {
				r.at += length
				if kind == 0x2f {
					if length != 0 || r.at != len(data) { return false }
					ended = true; break
				}
			}
			continue
		}
		if status == 0xf0 || status == 0xf7 {
			length := int(variable_read(&r))
			if r.bad || length > len(data)-r.at { return false }
			r.at += length; running = 0; continue
		}
		if status >= 0xf0 { return false }
		running = status
		a, b := byte_read(&r), u8(0)
		if status & 0xf0 != 0xc0 && status & 0xf0 != 0xd0 { b = byte_read(&r) }
		if a > 127 || b > 127 || r.bad || len(candidate.events) >= MAX_EVENTS { return false }
		append(&candidate.events, Event{frame, status, a, b})
	}
	if !ended || r.bad || frame < RATE || len(candidate.events) == 0 { return false }
	candidate.frames = frame
	destroy(score); score^ = candidate; good = true
	return true
}
