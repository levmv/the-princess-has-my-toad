# Third-party components

- [Odin](https://odin-lang.org/), dev-2026-09, by Ginger Bill and contributors.
  Compiler libraries/runtime: zlib license, reproduced in `licenses/odin.txt`.
- [raylib](https://www.raylib.com/), 6.0, by Ramon Santamaria and contributors.
  The Odin distribution supplies bindings and a static raylib archive.
  zlib license, reproduced in `licenses/raylib.txt`; raylib's bundled dependency
  acknowledgements are preserved in `licenses/raylib-dependencies.txt`.
- [DejaVu](https://dejavu-fonts.github.io/) Sans, Sans Bold and Sans Mono.
  The fonts in `assets/fonts` are modified Latin/Cyrillic subsets with hinting removed,
  created using FontTools. Their notice is in `assets/fonts/LICENSE.txt`
  (`licenses/fonts.txt` in the web package).

- Short recorded weapon sounds in `assets/audio/shot-*.wav` are edits of
  `D_32P.wav` (AR-15, near stereo recording) from
  [The Free Firearm Sound Library](https://opengameart.org/content/the-free-firearm-sound-library).
  Recorded by Ben Jaszczak, Brian Nelson, Kevin Heras, and Matthew Nanney;
  used under CC0 1.0. Edits: excerpting two shots, stereo balance, mono downmix,
  equalization, resampling, normalization and end fades.
- Shotgun clips in `assets/audio/shotgun-*.wav` use `O_21P.wav` (Benelli Nova)
  and `K_22P.wav` (Winchester Model 12) from the same CC0 firearm library.
  Edits: excerpting, mono downmix, equalization, saturation, a stretched low/mid
  layer, short reflections, generated pressure/mechanism layers and boundary
  fades. `assets/audio/shotgun-sources.json` records provenance and output hashes;
  `scripts/prepare-shotgun-audio.py` recreates the four variants.
- Short voice efforts in `assets/audio/jump-*.wav` are edits of
  `3grunt1.wav`, `3grunt3.wav`, `3grunt4.wav`, and `3grunt5.wav` from
  [Male Grunt/Yelling sounds](https://opengameart.org/content/male-gruntyelling-sounds)
  by HaelDB, used under the offered CC0 1.0 option.
  Edits: trimming silence, mono downmix, filtering, resampling, normalization
  and boundary fades. These are provisional voice effects, not a full character voice set.

CC0 text is reproduced in `licenses/audio-cc0.txt`. Exact source hashes, offsets
and processing are in `assets/audio/sources.json`; `scripts/prepare-audio.py`
recreates the clips from extracted originals. The original large libraries are
only development inputs and are not included in the game distribution.

The MIDI compositions in `assets/music` and their deterministic authoring script
`scripts/compose-music.py` are original to this project. The FM synthesizer uses
no third-party instrument samples or SoundFont.

All arena geometry, character geometry, material synthesis, remaining sound
synthesis, gameplay and shaders in this project were created for this prototype.
No assets from MDK, MDK2 or Quake are distributed.

Lora's short jump efforts (`assets/audio/lora-jump-*.wav`) are edits of the
Type 3 jump recordings in [Female RPG Voice Starter Pack](https://opengameart.org/content/female-rpg-voice-starter-pack)
by Cici Fyre (cicifyre), licensed CC0 1.0. Edits: high/low-pass filtering,
mono 32 kHz conversion, silence trimming, gain and boundary fades. No voice
cloning or pitch conversion. Provenance and exact processing boundaries are in
`assets/audio/lora-sources.json`; `scripts/prepare-lora.py` recreates them.

Combat impacts (`flesh-*.wav`, `gib-*.wav`) are edited from
[Slimy monster or murder sounds](https://opengameart.org/content/slimy-monster-or-murder-sounds9)
by pauliuw, CC0 1.0. Fairy death clips combine the Type 1 damage recordings from
Cici Fyre's CC0 pack above with quiet layers of `zombieDeath1–4.wav` from
[Zombie-Skeleton-Monster voice effects](https://opengameart.org/content/zombie-skeleton-monster-voice-effects)
by ArcadeParty, CC0 1.0. Edits include trimming, filtering, time/pitch adjustment,
layering, normalization and fades. `assets/audio/combat-sources.json` records
source/output hashes and processing; `scripts/prepare-combat-audio.py` rebuilds them.

The optional web build uses Emscripten 4.0.16 (MIT/University of Illinois NCSA
licenses, see `licenses/emscripten.txt`) and compiles raylib 6.0 for OpenGL ES 3 /
WebGL 2. The accompanying `odin.js` runtime comes from the pinned Odin toolchain
and is covered by its license above. No web service, telemetry or external CDN
is required to run the packaged page.
