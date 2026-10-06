# Testing the Raspberry Pi 5 build over SSH

A step-by-step plan for a Pi 5 that sits somewhere else, reachable over
Tailscale SSH, running RetroPie, with the TV probably off. The desktop side
assumes the fish shell; everything typed after `ssh` runs in bash on the Pi.

## What this can and cannot show

Remotely testable: the build, the launch, which GL driver and version SDL
gets, whether every shader compiles on the V3D compiler, the intro video, the
in-engine Oxide cutscene and a demo race (the title screen starts one on its
own, so no input is needed), frame times through the game's own `--perf`
recorder, screenshots through `--screenshot-interval`, stability over several
minutes, and temperature and throttling.

Not testable without being there: controllers, audio, and how the picture
looks on the TV itself. Screenshots cover the picture well enough to catch
rendering bugs.

## 0. Desktop: name the Pi once

```fish
set PI pi@your-pi            # Tailscale machine name or IP, with your Pi user
ssh $PI true && echo ok
```

## 1. Facts about the Pi

One command. Send back the whole output.

```fish
ssh -t $PI 'echo "== os =="; head -3 /etc/os-release; echo "kernel: $(uname -r)  machine: $(uname -m)  userland_bits: $(getconf LONG_BIT)  dpkg_arch: $(dpkg --print-architecture)  foreign: $(dpkg --print-foreign-architectures | tr "\n" " ")"; echo "== hardware =="; cat /proc/device-tree/model; echo; free -h | head -2; df -h / | tail -1; echo "== gpu =="; ls -l /dev/dri/; for f in /sys/class/drm/card*-HDMI-A-*/status; do echo "$f: $(cat "$f")"; done; dpkg -l | grep -E "libgl1-mesa-dri|libegl-mesa0|libgbm1|libdrm2 " | awk "{print \$2, \$3}"; echo "== retropie =="; ls -d ~/RetroPie-Setup /opt/retropie 2>&1; pgrep -a emulationstation || echo "emulationstation not running"; echo "== user =="; id; echo "== audio =="; aplay -l 2>&1 | grep "^card" || echo "no alsa cards"; echo "== input =="; ls /dev/input/by-id/ 2>/dev/null || echo "no input devices"; echo "== kernel alignment fixups =="; sudo modprobe configs 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep -i COMPAT_ALIGNMENT || echo "kernel config not readable"; echo "== apt sources =="; grep -rh "^deb " /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; echo "== temperature =="; vcgencmd measure_temp; vcgencmd get_throttled'
```

What matters in it: `userland_bits` (32 means a native build, 64 means the
armhf cross-build through multiarch), the HDMI `status` lines (`connected` is
needed for KMSDRM even with the TV off), the Mesa package versions, and
whether EmulationStation is running.

## 2. Get the armhf package

Pick one.

**A. GitHub Actions.** On a fork, Actions are disabled until you open the
repository's *Actions* tab once and enable them. Then: *Actions* > *Build
native PC builds* > *Run workflow* > branch
`claude/affectionate-davinci-v46g7q` > *Run workflow*. The armhf job takes
about two minutes; the whole run, with the Windows and x86 jobs, longer.
The tarball is uploaded as-is so it keeps its executable bit, which means
the artifact is named after the file, `ctr-turbocharged-<branch>-<sha>-linux-armhf.tar.gz`,
not after the upload step. Download it from the run page, or with the GitHub
CLI, giving the run ID from the run's URL and matching the name by pattern:

```fish
gh workflow run build-native.yml -R tazua/Crash-Team-Racing-Turbocharged --ref claude/affectionate-davinci-v46g7q
gh run list -R tazua/Crash-Team-Racing-Turbocharged -w build-native.yml -L 3
gh run download <run-id> -R tazua/Crash-Team-Racing-Turbocharged -p '*linux-armhf.tar.gz' -D pi-build
find pi-build -name '*.tar.gz'
```

Without a run ID, `gh run download` picks a run itself and may land on the
format-check run, which has no artifacts. If the download arrives as a zip,
unzip it to get the `.tar.gz`.

**B. Container build on the desktop.** Needs Docker or Podman. Takes about
ten minutes and leaves the package in `dist/`.

```fish
cd ~/path/to/Crash-Team-Racing-Turbocharged
git fetch origin
git checkout claude/affectionate-davinci-v46g7q
./tools/build-armhf-in-container.sh        # prefix with sudo if docker refuses the socket
ls dist/*linux-armhf.tar.gz
```

**C. Build on the Pi.** Slowest, but it is what the RetroPie module does;
see step 8.

## 3. Copy the package and your disc image to the Pi

```fish
scp dist/ctr-turbocharged-*-linux-armhf.tar.gz $PI:   # or the file under pi-build/ from Actions
scp /path/to/your/ctr-u.bin $PI:
ssh $PI
```

On the Pi:

```bash
mkdir -p ~/ctr-test && cd ~/ctr-test
tar -xzf ~/ctr-turbocharged-*-linux-armhf.tar.gz
cd ctr-turbocharged-*-linux-armhf
mv ~/ctr-u.bin assets/ctr-u.bin
# Skip the first-boot language and preset prompts, which would wait for input.
printf 'language=2\npreset_seen=1\n' > config.ini
./ctr_native --version
ldd ./ctr_native | grep -i "not found" || echo "all libraries present"
```

If `ldd` lists missing libraries on a 64-bit OS, install the armhf runtime:

```bash
sudo dpkg --add-architecture armhf && sudo apt update
sudo apt install libgl1-mesa-dri:armhf libgl1:armhf libegl1:armhf libgbm1:armhf \
    libasound2:armhf libpulse0:armhf libudev1:armhf libdbus-1-3:armhf libx11-6:armhf
```

## 4. Free the GPU and check the display

EmulationStation owns the display while it runs, so stop it first. It comes
back after a reboot (step 9).

```bash
cat /sys/class/drm/card*-HDMI-A-*/status
pkill emulationstation; sleep 2; pgrep -a emulationstation || echo "EmulationStation stopped"
```

If every HDMI connector reports `disconnected` (TV off and not holding the
hotplug line), make the kernel drive the output anyway, then reboot, SSH
back in and stop EmulationStation again:

```bash
sudo cp /boot/firmware/cmdline.txt /boot/firmware/cmdline.txt.bak
sudo sed -i '1 s/$/ video=HDMI-A-1:1920x1080@60D/' /boot/firmware/cmdline.txt
sudo reboot
```

Undo later with `sudo cp /boot/firmware/cmdline.txt.bak /boot/firmware/cmdline.txt`.

## 5. Run for six minutes, hands off

```bash
cd ~/ctr-test/ctr-turbocharged-*-linux-armhf
timeout -s INT 360 ./ctr_native --fullscreen --perf --screenshot-interval 20 2>&1 | tee run1.txt
```

Left alone, the game plays the intro video, reaches the title, plays the
Oxide intro cutscene, returns to the title and starts a demo race. The
`timeout` sends the same signal as closing the window, so the game shuts down
cleanly and writes its perf summary. Every 20 seconds it saves
`screenshot-NNN.bmp` into the folder.

If it stops at once, read `run1.txt`:

| Message | Meaning |
| --- | --- |
| `Failed to initialise SDL window` | No usable display. Check step 4; `SDL_VIDEODRIVER=kmsdrm` in front of the command forces KMSDRM and gives a clearer error. |
| `OpenGL 3.x is not supported` | The driver offered no desktop GL 3.x context. The `*OpenGL version:` line, if present, says what it offered. |
| `permission denied` on `/dev/dri` or a DRM master error | Try `sudo -E ./ctr_native ...` once, then `sudo chown -R "$USER": .` afterwards. |
| `SDL audio unavailable` | Not fatal; expected with the TV off. |
| `Failed to load assets` or disc errors | Check `assets/ctr-u.bin` is the raw MODE2/2352 image. |

## 6. Collect the results

```bash
mkdir -p ~/ctr-results
cp run1.txt *.log config.ini screenshot-*.bmp ~/ctr-results/ 2>/dev/null
cp -r debug/perf/perf-latest ~/ctr-results/perf 2>/dev/null
{ vcgencmd measure_temp; vcgencmd get_throttled; uptime; } > ~/ctr-results/system.txt
sudo dmesg | tail -n 80 > ~/ctr-results/dmesg.txt
exit
```

Back on the desktop:

```fish
scp -r $PI:ctr-results ./pi-results
ls pi-results
```

Screenshots are BMP; any image viewer opens them. `get_throttled` reports
`0x0` when the Pi never throttled; anything else means heat or power limits
affected the run.

## 7. A second run with lighter settings

Only if the first run stuttered. The game rewrote `config.ini` on exit, so
edit values in place rather than appending:

```bash
sed -i 's/^ps1_resolution=.*/ps1_resolution=1/; s/^anti_aliasing=.*/anti_aliasing=0/' config.ini
timeout -s INT 360 ./ctr_native --fullscreen --perf-dir debug/perf/run2 --screenshot-interval 20 2>&1 | tee run2.txt
```

## 8. The real installation: the RetroPie module

Once the package runs, install the port the way players would. The steps are
in `packaging/retropie/README.md`; they clone and build on the Pi (about 700
MB of RAM for the compile, so stop EmulationStation first) and add the
launcher under Ports. Launching from EmulationStation is best checked with
someone at the TV.

## 9. Put the Pi back

```bash
sudo reboot
```

EmulationStation returns on boot. If you changed `cmdline.txt` in step 4,
restore the backup first.

## What to send back

- The output of step 1.
- `run1.txt` and the `.log` file from the game folder.
- `perf/summary.txt` and, if small enough, `perf/frame_times.csv`.
- Two or three screenshots, especially ones from the race.
- `system.txt` and `dmesg.txt`.
