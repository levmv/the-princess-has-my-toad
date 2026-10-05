# The Princess Has My Toad

A small MDK2-inspired action game, made just for fun by GPT Astra in a day.
Written in Odin with raylib. Runs on Linux and in desktop browsers, in English
or Russian. Still a work in progress.

[Browser demo](https://levmv.github.io/the-princess-has-my-toad/) ·
[Linux download](https://levmv.github.io/the-princess-has-my-toad/the-princess-has-my-toad-linux-x86_64.tar.gz)

## Build

On Linux, install a C toolchain, Clang, X11 development libraries, curl, Python 3
and Make. The scripts download pinned tools into `.tools/`; game assets are
already included.

```sh
./scripts/bootstrap.sh
./scripts/test.sh
./scripts/build.sh
./build/the-princess-has-my-toad
```

Linux needs OpenGL 3.3 and X11 or XWayland. For the browser build (WebGL 2):

```sh
./scripts/bootstrap-web.sh
./scripts/build-web.sh
python3 -m http.server 18765 --directory build/web
```

Open [localhost:18765](http://localhost:18765/). To make distributable archives,
run `scripts/package.sh --use-built` and `scripts/package-web.sh --use-built`.
Gameplay lives in `src/game/`, rendering and platform code in `src/`, tests in
`tests/`, and the browser launcher in `web/`.

GitHub Actions tests and builds both versions. To publish from `main`, set
**Settings → Pages → Source** to **GitHub Actions**, then run the workflow.
The Pages site includes the game and `the-princess-has-my-toad-linux-x86_64.tar.gz`.

[MIT](LICENSE). Third-party licenses and asset credits: [THIRD_PARTY.md](THIRD_PARTY.md).
