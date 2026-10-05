#!/usr/bin/env python3
"""Rebuild the shotgun from the CC0 firearm library (see THIRD_PARTY.md).

Requires ffmpeg and O_21P.wav / K_22P.wav in build/audio-source/guns.
Normal builds embed the finished WAVs; no DSP or source library is needed at run time.
"""
import array
import hashlib
import json
import math
from pathlib import Path
import random
import subprocess
import wave

ROOT = Path(__file__).resolve().parents[1]
RATE = 32000
DURATION = 0.78
COUNT = round(RATE * DURATION)
OUTPUT = ROOT / 'assets/audio'


def decode(path, start, filters):
    raw = subprocess.check_output([
        'ffmpeg', '-nostdin', '-v', 'error', '-i', str(path),
        '-af', f'atrim=start={start}:duration=0.72,asetpts=PTS-STARTPTS,{filters}',
        '-ar', str(RATE), '-ac', '1', '-f', 'f32le', '-'])
    return array.array('f', raw)


def lowpass(samples, frequency):
    alpha = 1 - math.exp(-2 * math.pi * frequency / RATE)
    previous = 0.0
    result = []
    for x in samples:
        previous += alpha * (x - previous)
        result.append(previous)
    return result


manifest = []
for variant, (name, start, balance) in enumerate([
        ('O_21P.wav', 0.4285, 0.62), ('K_22P.wav', 0.8415, 0.58),
        ('O_21P.wav', 3.4634, 0.44), ('K_22P.wav', 7.4445, 0.48)]):
    path = ROOT / 'build/audio-source/guns' / name
    filters = (f'pan=mono|c0={balance}*c0+{1-balance}*c1,'
               f'aresample={RATE},highpass=f=42,'
               'equalizer=f=165:t=q:w=0.8:g=5,lowpass=f=11500')
    raw = decode(path, start, filters)
    # Leave a sharp leading crack, but lift the pressure body and the recorded
    # decay instead of spending all the available headroom on one tiny peak.
    source_peak = max(abs(x) for x in raw)
    shot = [math.tanh(x / source_peak * 2.3) * 0.62 *
            (1 + 1.6 * min(i / (RATE * 0.10), 1)) for i, x in enumerate(raw)]
    mix = shot[:COUNT] + [0.0] * max(0, COUNT-len(shot))
    body = lowpass(shot, 1250)
    # Slightly stretched low/mid pressure; linear interpolation avoids the
    # grit of the old nearest-neighbour down-pitched automatic rifle sample.
    speed = 0.71 + variant * 0.012
    for i in range(COUNT):
        position = i * speed
        index = int(position)
        if index + 1 >= len(body):
            break
        sample = body[index] * (1-position+index) + body[index+1] * (position-index)
        mix[i] += sample * 0.70 * math.exp(-i / (RATE * 0.24))
    # A short, diffuse tail. Many quiet, dark reflections merge into a body;
    # none becomes a separate second shot or a long wash over combat cues.
    rng = random.Random(941 + variant)
    reflection = lowpass(shot, 2300)
    for tap in range(28):
        delay = 0.013 + tap * 0.0065 + rng.uniform(-0.002, 0.002)
        gain = 0.13 * math.exp(-delay / 0.075) * rng.uniform(0.8, 1.2)
        offset = round(delay * RATE)
        for i in range(min(len(reflection), COUNT-offset)):
            mix[i+offset] += reflection[i] * gain
    # A broad, non-tonal low pressure layer remains audible on small speakers.
    noise = [rng.uniform(-1, 1) for _ in range(COUNT)]
    bass = lowpass(noise, 480)
    sub = lowpass(bass, 65)
    for i in range(COUNT):
        t = i / RATE
        mix[i] += (bass[i]-sub[i]) * 1.45 * min(t / 0.004, 1) * math.exp(-t / 0.080)
        # Short pressure pulse under the recorded blast, with a falling
        # frequency rather than a sustained electronic bass note.
        phase = 2*math.pi*((72+variant)*t + 1.1*(1-math.exp(-t/0.028)))
        mix[i] += math.sin(phase) * 0.24 * min(t/0.0025, 1) * math.exp(-t/0.075)
    # Two compact rack/lock strokes. Lower than the blast, with no loud shell
    # jingle or voice that would obscure the next enemy warning.
    metal = lowpass(noise, 4100)
    dull = lowpass(metal, 420)
    for onset, strength, decay in [(0.29, 0.16, 0.022), (0.44, 0.22, 0.015)]:
        onset += variant * 0.003
        for i in range(round(onset * RATE), COUNT):
            t = i / RATE-onset
            strike = (metal[i]-dull[i] + 0.13*math.sin(t*2*math.pi*570))
            mix[i] += strike * strength * min(t / 0.001, 1) * math.exp(-t / decay)
    # Remove DC and keep a genuine peak margin; do not hard-clip the blast.
    dc = lowpass(mix, 25)
    mix = [(x-dc[i])*min(1, i/8, (COUNT-1-i)/(RATE*0.05)) for i, x in enumerate(mix)]
    gain = 0.82 / max(abs(x) for x in mix)
    pcm = array.array('h', (round(x * gain * 32767) for x in mix))
    target = OUTPUT / f'shotgun-{variant}.wav'
    with wave.open(str(target), 'wb') as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(pcm.tobytes())
    # Check the shipped PCM, including silence at both boundaries and the
    # intended .85 s cadence. The sound must finish before the next shot.
    assert len(pcm)/RATE < 0.85 and pcm[0] == 0 and pcm[-1] == 0
    assert max(abs(x) for x in pcm) < 32767
    assert abs(sum(pcm)/len(pcm)/32768) < 0.001
    rms = lambda a, b: math.sqrt(sum((x/32768)**2 for x in pcm[round(a*RATE):round(b*RATE)]) / round((b-a)*RATE))
    print(f'{target.name}: peak={max(abs(x) for x in pcm)/32768:.3f}, '
          f'body RMS={rms(0.015, 0.15):.4f}, tail RMS={rms(0.15, 0.28):.4f}, '
          f'{target.stat().st_size} bytes')
    manifest.append(dict(file=target.name, source=name, start=start, filters=filters,
                         source_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                         duration=DURATION, rate=RATE, peak=0.82, seed=941+variant,
                         processing='Recorded crack/body, stretched low-mid layer, diffuse early reflections, pressure noise, rack/lock, DC filter, normalization, boundary fades; prepare-shotgun-audio.py',
                         output_sha256=hashlib.sha256(target.read_bytes()).hexdigest()))

(OUTPUT/'shotgun-sources.json').write_text(json.dumps(manifest, indent=2)+'\n')
