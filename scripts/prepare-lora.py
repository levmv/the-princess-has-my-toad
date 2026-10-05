#!/usr/bin/env python3
"""Rebuild Lora's embedded efforts from the documented CC0 source archive.
Extract it under build/audio-source/female-rpg before running. Requires ffmpeg.
Normal builds use the checked-in WAVs and require no asset tools or downloads.
"""
import array
import hashlib
import json
from pathlib import Path
import subprocess
import wave

ROOT = Path(__file__).resolve().parents[1]
manifest = json.loads((ROOT/'assets/audio/lora-sources.json').read_text())
for entry in manifest['clips']:
    source = ROOT/'build/audio-source/female-rpg'/entry['source']
    assert hashlib.sha256(source.read_bytes()).hexdigest() == entry['source_sha256']
    raw = subprocess.check_output(['ffmpeg','-v','error','-i',str(source),'-af',entry['filters'],
                                   '-ar',str(entry['rate']),'-ac','1','-f','f32le','-'])
    data = array.array('f',raw)[entry['start_sample']:entry['end_sample']]
    gain = entry['peak']/max(abs(x) for x in data)
    pcm = array.array('h',(round(max(-1,min(1,x*gain*min(1,j/16,(len(data)-1-j)/200)))*32767)
                            for j,x in enumerate(data)))
    target = ROOT/'assets/audio'/entry['file']
    with wave.open(str(target),'wb') as out:
        out.setnchannels(1);out.setsampwidth(2);out.setframerate(entry['rate']);out.writeframes(pcm.tobytes())
    assert hashlib.sha256(target.read_bytes()).hexdigest() == entry['output_sha256']
    print(entry['file'],len(data)/entry['rate'],'seconds')
