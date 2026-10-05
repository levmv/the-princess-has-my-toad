#!/usr/bin/env python3
"""Rebuild CC0 combat clips from build/audio-source (see THIRD_PARTY.md).
No audio tools or source archives are needed for normal game builds.
"""
import array, hashlib, json, math, subprocess, wave
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT/'build/audio-source'
OUTPUT = ROOT/'assets/audio'
RATE = 22050
manifest = []

def decode(path, filters):
    data = subprocess.check_output(['ffmpeg','-nostdin','-v','error','-i',str(path),'-af',filters,
                                    '-ar',str(RATE),'-ac','1','-f','f32le','-'])
    return array.array('f',data)

def clip(name, layers, duration, peak):
    count = int(duration*RATE)
    mix = [0.0]*count
    sources = []
    for relative, filters, gain in layers:
        path = SOURCE/relative
        data = decode(path,filters)
        for i,x in enumerate(data[:count]): mix[i] += x*gain
        sources.append(dict(source=relative,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),filters=filters,gain=gain))
    scale = peak/max(abs(x) for x in mix)
    pcm = array.array('h',(round(x*scale*min(1,i/8,(count-i-1)/280)*32767) for i,x in enumerate(mix)))
    target = OUTPUT/name
    with wave.open(str(target),'wb') as out:
        out.setnchannels(1); out.setsampwidth(2); out.setframerate(RATE); out.writeframes(pcm.tobytes())
    manifest.append(dict(file=name,layers=sources,duration=duration,rate=RATE,peak=peak,sha256=hashlib.sha256(target.read_bytes()).hexdigest()))
    print(name, target.stat().st_size)

for i,n in enumerate((1,2,4,5)):
    source=f'combat/squish-{n}.mp3'
    clip(f'flesh-{i}.wav',[(source,'atrim=start=0.022,highpass=f=110,lowpass=f=5500',1)],0.20,0.52)
    clip(f'gib-{i}.wav',[(source,'atrim=start=0.022,asetrate=22050*0.80,aresample=22050,highpass=f=65,lowpass=f=6500',1)],0.36,0.73)
    voice=f'female-rpg/RPG Voice Starter Pack/Type 1/damaged{i%3+1}.wav'
    corpse=f'combat/zombieDeath{i+1}.wav'
    clip(f'fae-death-{i}.wav',[(voice,'atempo=0.64,highpass=f=220,lowpass=f=7500',1.7),
                             (corpse,'atrim=start=0.02,asetrate=44100*1.30,aresample=22050,highpass=f=250,lowpass=f=4200',0.17)],0.62,0.67)
(OUTPUT/'combat-sources.json').write_text(json.dumps(manifest,indent=2)+'\n')
