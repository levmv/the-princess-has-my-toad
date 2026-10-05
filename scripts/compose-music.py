#!/usr/bin/env python3
"""Original THE PRINCESS HAS MY TOAD scores. Deterministic SMF-0, no audio libraries/assets.

Musical form is authored: intro, two riffs, sparse middle, reprise, turnaround.
Small velocity/timing accents are deterministic, not random notes at runtime.
Programs follow GM numbering (zero based); channel 10 carries percussion.
"""
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]
PPQ = 480


def vlq(value):
    out = [value & 127]
    while value > 127:
        value >>= 7
        out.insert(0, (value & 127) | 128)
    return bytes(out)


class Score:
    def __init__(self, title, bpm):
        self.events = []
        self.add(0, b'\xff\x03' + vlq(len(title)) + title.encode())
        self.add(0, b'\xff\x51\x03' + round(60_000_000 / bpm).to_bytes(3, 'big'))
        self.add(0, b'\xff\x58\x04\x04\x02\x18\x08')
        for ch, program, volume, pan in [(0, 30, 101, 35), (1, 38, 109, 64),
                                          (2, 81, 72, 91), (3, 50, 58, 72),
                                          (4, 4, 72, 41), (9, 0, 103, 64)]:
            self.add(0, bytes([0xC0 | ch, program]))
            self.add(0, bytes([0xB0 | ch, 7, volume]))
            self.add(0, bytes([0xB0 | ch, 10, pan]))

    def add(self, beat, event):
        self.events.append((round(beat * PPQ), len(self.events), event))

    def note(self, beat, duration, channel, key, velocity):
        assert 0 <= key < 128 and 0 < velocity < 128 and duration > 0
        self.add(beat, bytes([0x90 | channel, key, velocity]))
        self.add(beat + duration, bytes([0x80 | channel, key, 0]))

    def write(self, name, bars):
        self.add(bars * 4, b'\xff\x2f\x00')
        data, previous = bytearray(), 0
        for tick, _, event in sorted(self.events):
            data.extend(vlq(tick - previous)); data.extend(event); previous = tick
        header = b'MThd' + struct.pack('>IHHH', 6, 0, 1, PPQ)
        out = header + b'MTrk' + struct.pack('>I', len(data)) + data
        (ROOT / 'assets/music' / name).write_bytes(out)
        print(f'{name}: {bars} bars, {len(self.events)} events, {len(out)} bytes')


def compose(name, title, bpm, boss=False, transfer=False):
    score = Score(title, bpm)
    bars = 64 if not transfer else 48
    roots = [40, 40, 43, 41, 40, 47, 43, 38] if not boss else [38, 38, 41, 39, 38, 44, 41, 37]
    if transfer:
        roots = [45, 45, 48, 43, 45, 40, 43, 47]
    riff_a = [(0, 0), (.5, 0), (.75, 12), (1.5, 0), (2, 7), (2.75, 0), (3.25, 3), (3.5, 1)]
    riff_b = [(0, 0), (.75, 7), (1.25, 12), (1.75, 0), (2.5, 3), (3, 0), (3.75, 7)]
    melody = [(0, 24), (.75, 27), (1.5, 26), (2.75, 31), (3.5, 26)]
    for bar in range(bars):
        at = bar * 4
        sparse = 32 <= bar < 40 or (transfer and 24 <= bar < 32)
        intro = bar < 4
        finish = bar == bars - 1
        root = roots[(bar // 2) % len(roots)]
        motif = riff_b if (bar // 8) % 2 else riff_a
        # Tail keeps release/delay natural across a loop, not a cut to silence.
        if finish:
            for note in [root, root + 7, root + 12]:
                score.note(at, 2.8, 0, note, 81)
            score.note(at, 2.8, 1, root - 12, 99)
            score.note(at, .1, 9, 49, 75)
            continue
        for beat, interval in motif:
            if intro and beat not in (0, 2, 2.5):
                continue
            if sparse:
                score.note(at + beat, .7, 4, root + 12 + interval, 55 + (bar % 3) * 4)
            else:
                velocity = 96 if beat in (0, 2) else 75 + (int(beat * 4) % 3) * 7
                score.note(at + beat, .20 if beat % 1 else .34, 0, root + interval, velocity)
                # Sparse power fifths leave room for the bass and effects.
                if beat in (0, 2, 2.5):
                    score.note(at + beat + .0125, .32, 0, root + interval + 7, velocity - 19)
            score.note(at + beat, .31, 1, root - 12 + (interval if interval < 8 else 0), 96 if beat == 0 else 78)
        # A musical pulse remains in the quiet section; attacks still breathe.
        for beat in ([0, 2.5] if sparse else [0, 1.75, 2.5, 3.5] if boss else [0, 1.5, 2, 2.75]):
            score.note(at + beat, .1, 9, 36, 99 if beat == 0 else 78)
        if not intro:
            for beat in ([2] if sparse else [1, 3]):
                score.note(at + beat + .008, .12, 9, 38, 87 if not sparse else 53)
        for step in range(8 if not sparse else 4):
            beat = step * (.5 if not sparse else 1)
            score.note(at + beat, .08, 9, 46 if step == 7 and bar % 4 == 3 else 42,
                       54 if step % 2 == 0 else 36)
        if bar % 8 == 0:
            score.note(at, .2, 9, 49, 66 if not sparse else 38)
        if bar % 8 == 7 and not sparse:
            for step, drum in enumerate([38, 38, 45, 41]):
                score.note(at + 3 + step * .25, .1, 9, drum, 59 + step * 7)
        if bar % 2 == 0:
            for note in [root + 12, root + 19, root + 26]:
                score.note(at, 7.6, 3, note, 48 if not sparse else 65)
        if (16 <= bar < 24 or 48 <= bar < 56) and bar % 2 == 0:
            for beat, interval in melody:
                score.note(at + beat, .45 if beat != 2.75 else .65, 2, root + interval, 72)
    score.write(name, bars)


if __name__ == '__main__':
    compose('cold-boot.mid', 'Cold Boot / memory pressure', 132)
    compose('collector.mid', 'Collector / stop the world', 158, boss=True)
    compose('transfer.mid', 'Transfer / address unknown', 116, transfer=True)
