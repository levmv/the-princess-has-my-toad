THE PRINCESS HAS MY TOAD — Cold Boot / Web demo

An original Odin + raylib action game. The princess has kidnapped the toad.
Reach the top of the tower. Rescue the toad. Save the world.

Run this folder through an HTTP server, not by double-clicking index.html:
    python3 -m http.server 18765 --directory .
Then visit http://localhost:18765/ in a desktop browser with WebGL 2.
No server-side game code, external services or CDN are required. To share
online, upload the contents of this folder to a static website host.
Keep game.wasm, game.js, odin.js and the other files beside index.html.

Russian / English: use the cover buttons, ?lang=ru / ?lang=en, or Tab in menus.
The tower display shows download and preparation progress. Once ready, click
Enter, choose New Game, watch the intro and choose Duke or Lora.
Quit returns to this page; Return reuses the prepared game without a reload.
Click the mouse-capture prompt if shown. Escape pauses and releases the mouse.
Use the Fullscreen button below the game for browser fullscreen.
Canvas resolution follows the physical display pixels, including fractional
DPI/zoom. The explicit 3D scale in Settings can reduce GPU work if needed.

WASD: move; mouse: aim; left button: fire; right button: scope.
Space: jump; release, then press and hold again in the air to glide.
F: kick; Left Shift: dash; E: use.
1: repeater; 2: shotgun; 3: fragmentator. Wheel: cycle owned weapons.
F5: quicksave; F9: quickload. Controls can be rebound in Settings.

Settings and saves are local to this browser and this website address.
Clearing site data removes them. They are separate from the Linux saves.
Prototype updates can invalidate saves; start a new game when their version differs.
This build targets keyboard and mouse, not touchscreen controls.

Project license: LICENSE (MIT).
Third-party notices and audio credits: THIRD_PARTY.md and licenses/.
