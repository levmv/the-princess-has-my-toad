#!/usr/bin/env python3
"""Build embedded clips from the CC0 sources documented in THIRD_PARTY.md.

Requires ffmpeg. Source archives must already be extracted under
build/audio-source/{guns,voices/yelling sounds}. Normal builds use the
checked-in WAVs and need neither ffmpeg nor the source archives.
"""
import array
import hashlib
import json
import math
from pathlib import Path
import subprocess
import wave

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'build/audio-source'
OUTPUT = ROOT / 'assets/audio'
OUTPUT.mkdir(parents=True, exist_ok=True)
RATE = 32000
manifest = []


def build_clip(source, name, start, duration, filters, peak):
    command = ['ffmpeg', '-nostdin', '-v', 'error', '-i', str(source),
               '-ss', str(start), '-t', str(duration), '-af', filters,
               '-ar', str(RATE), '-ac', '1', '-f', 'f32le', '-']
    raw = subprocess.check_output(command)
    samples = array.array('f', raw)
    scale = peak / max(abs(v) for v in samples)
    pcm = array.array('h')
    # Keep transients intact; fades remove only boundary discontinuities.
    fade_in = max(1, int(RATE * 0.00025))
    fade_out = max(1, int(RATE * (0.035 if name.startswith('shot') else 0.012)))
    for i, value in enumerate(samples):
        envelope = min(1, i / fade_in, (len(samples)-1-i) / fade_out)
        pcm.append(round(max(-1, min(1, value*scale*envelope))*32767))
    target = OUTPUT / name
    with wave.open(str(target), 'wb') as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(pcm.tobytes())
    manifest.append(dict(file=name, source=source.name, source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                         start=start, duration=duration, filters=filters, peak=peak,
                         output_sha256=hashlib.sha256(target.read_bytes()).hexdigest()))
    print(name, len(pcm)/RATE, 'seconds', target.stat().st_size, 'bytes')


# Two close microphone shots, with different stereo balances. No resynthesis.
for i, (start, balance) in enumerate([(0.701, 0.72), (5.645, 0.72), (0.701, 0.28), (5.645, 0.28)]):
    filters = f'pan=mono|c0={balance}*c0+{1-balance}*c1,highpass=f=55,equalizer=f=145:t=q:w=0.85:g=3,lowpass=f=12500'
    build_clip(SOURCE/'guns/D_32P.wav', f'shot-{i}.wav', start, 0.255, filters, 0.64)

# One vocalist, short exertions. Leading studio silence is removed so the voice
# begins at takeoff rather than hundreds of milliseconds into the jump.
for i, (file, start, duration) in enumerate([
        ('3grunt1.wav', 0.528, 0.34), ('3grunt3.wav', 0.018, 0.425),
        ('3grunt4.wav', 0.267, 0.185), ('3grunt5.wav', 0.148, 0.345)]):
    build_clip(SOURCE/'voices/yelling sounds'/file, f'jump-{i}.wav', start, duration,
               'pan=mono|c0=0.5*c0+0.5*c1,highpass=f=90,lowpass=f=7500', 0.60)

(OUTPUT/'sources.json').write_text(json.dumps(manifest, indent=2)+'\n')

# Verify the actual 24 Hz layering leaves digital headroom, including tails.
shots = []
for i in range(4):
    with wave.open(str(OUTPUT/f'shot-{i}.wav')) as f:
        shots.append(array.array('h', f.readframes(f.getnframes())))
mix = [0.0] * (RATE*3)
for shot in range(60):
    offset = round(shot*RATE/24)
    for i, value in enumerate(shots[shot%4]):
        mix[offset+i] += value/32768*0.8
peak = max(abs(v) for v in mix)
rms = math.sqrt(sum(v*v for v in mix)/len(mix))
assert peak < 0.94, f'Burst clips: peak={peak}'
print(f'24 Hz burst before master volume: peak={peak:.3f}, RMS={rms:.3f}; assets={sum(p.stat().st_size for p in OUTPUT.glob("*.wav"))} bytes')
with wave.open(str(ROOT/'build/audio-burst-preview.wav'), 'wb') as out:
    out.setnchannels(1); out.setsampwidth(2); out.setframerate(RATE)
    out.writeframes(array.array('h', (round(v*32767) for v in mix)).tobytes())
