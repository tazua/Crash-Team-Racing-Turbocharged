# RetroPie port module

`ctr-turbocharged.sh` is a RetroPie-Setup scriptmodule. It builds the game on
the Pi, installs it under `/opt/retropie/ports/ctr-turbocharged`, and adds
**Crash Team Racing - Turbocharged** to the Ports system in EmulationStation.
The game data, your settings and your saves live in
`~/RetroPie/roms/ports/ctr-turbocharged`.

The game needs your own NTSC-U disc dump; the module never downloads game data.

## Requirements

- Raspberry Pi 5 (the module is flagged `rpi5`; 2 GB of RAM is enough).
- RetroPie installed with the setup script on Raspberry Pi OS Bookworm Lite.
  RetroPie documents the 64-bit OS for the Pi 5; the module handles that by
  cross-compiling a 32-bit (armhf) binary through Debian multiarch, because the
  game needs 4-byte pointers. On a 32-bit OS it builds natively instead.
- Internet access for the clone and the build dependencies, and about 1 GB of
  free space for the source tree and build.

## Install

```sh
cd ~
git clone --depth 1 https://github.com/tazua/Crash-Team-Racing-Turbocharged.git ctr-turbocharged-src
sudo mkdir -p ~/RetroPie-Setup/ext/ctr-turbocharged/scriptmodules/ports
sudo cp ctr-turbocharged-src/packaging/retropie/ctr-turbocharged.sh \
    ~/RetroPie-Setup/ext/ctr-turbocharged/scriptmodules/ports/
cd ~/RetroPie-Setup
sudo ./retropie_packages.sh ctr-turbocharged
```

The last command installs the build dependencies, clones the `turbocharged`
branch, builds the game and registers the port. It is also available in the
RetroPie-Setup menu under *Manage packages > Manage experimental packages*
once the file is in `ext/`. Expect the build to take a while on the Pi; SDL is
built from source along with the game.

To build from a different fork or branch, edit `rp_module_repo` in the
scriptmodule before running it.

## Add your disc image

Copy your raw NTSC-U **Crash Team Racing** disc image to:

```text
~/RetroPie/roms/ports/ctr-turbocharged/assets/ctr-u.bin
```

It must be the single-track raw BIN layout (MODE2/2352 sectors, data track at
byte 0). A 2048-byte `.iso` will not work, and the `.cue` is not needed. The
folder is inside the `roms` share, so the file can be copied over the network
like any ROM. The desktop first-run picker needs a file dialog service, which
a RetroPie console does not have, so place the file by hand.

Optional: put `crash-a-like.ttf` in `assets/fonts/` next to it and pick it
under *Options > Interface > Font*.

## Launch

Restart EmulationStation after installing, then start **Crash Team Racing -
Turbocharged** from Ports. The launcher runs:

```sh
CTR_TURBOCHARGED_DATA_DIR=~/RetroPie/roms/ports/ctr-turbocharged \
    /opt/retropie/ports/ctr-turbocharged/ctr_native --fullscreen
```

`--fullscreen` applies to that run only, so the window mode saved in
`config.ini` is left alone. Gamepads are picked up through SDL; rebind them in
*Options*. Settings are written to `config.ini` and saves to `memcards/` in the
data folder.

## Update or remove

```sh
cd ~/RetroPie-Setup
sudo ./retropie_packages.sh ctr-turbocharged        # rebuild from the latest branch head
sudo ./retropie_packages.sh ctr-turbocharged remove # remove the port (keeps the data folder)
```

## Troubleshooting

- Run it from a terminal (over SSH, or after quitting EmulationStation) to see
  the log. The game also writes a `.log` file into the data folder. The lines
  `*Video adapter:` and `*OpenGL version:` show which driver and GL version
  SDL got.
- No display server is running on a RetroPie console, so SDL uses KMSDRM. To
  force it, run with `SDL_VIDEODRIVER=kmsdrm`.
- Sound goes through ALSA on a Lite image. If a driver opens but stays
  silent, try `SDL_AUDIO_DRIVER=alsa` or `SDL_AUDIO_DRIVER=pulseaudio`.
- Heavy settings cost frames on the Pi. Start with FXAA rather than MSAA or
  SSAA, the Classic renderer, and *PS1 resolution* or a 720p mode, then raise
  them. The *PS1* preset is a quick way to get there.

Please report what works and what does not, with the `.log` file, through
the project's GitHub issues.
