# surface-studio-linux

Fixes for running Linux on a **Microsoft Surface Studio 2+** (i7-11370H, RTX 3060 Laptop
GPU, 28" 4500x3000 3:2 touch panel), from daily use on Arch +
[Omarchy](https://omarchy.org) / Hyprland.

Each fix says what goes wrong, why, and how to install it. These are one person's
working setup, not a supported distribution. Read each file before installing it.

Companion projects: [re:dial](https://github.com/bybrooksco/redial) (Surface Dial and
Pen) and [dummy-edid](https://github.com/bybrooksco/dummy-edid) (3:2 streaming).

| Area | Problem | Status |
|------|---------|--------|
| [GPU](#gpu-rtx-3060-cuda-without-wrecking-the-panel) | CUDA on the RTX 3060 corrupts the panel | Fixed for compute; NVIDIA driving the panel is not solved yet |
| [Heat](#heat-sustained-throttling) | Package sits at 100 °C and throttles | Fixed |
| [Touch](#touch-single-touch-only) | Panel boots single-touch / mouse emulation | Fixed |
| [Display](#display-red-line-on-the-top-edge) | Red line along the top edge after an Omarchy update | Fixed |
| [Pen](#pen-tip-stops-working) | Pen tip goes dead | Recovery procedure |
| [Streaming](#streaming-full-screen-3-2-game-streaming) | Moonlight/Sunshine letterboxed, input and decode quirks | Fixed |

---

## GPU: RTX 3060 CUDA without wrecking the panel

**Symptom.** Loading the NVIDIA driver (for CUDA, local AI, etc.) corrupts or blanks the
panel.

**Cause.** The panel is driven through the RTX 3060. The UEFI boot console (the
framebuffer the desktop runs on via `simpledrm`) lives in the GPU's VRAM, behind
BAR1, at **BAR1 + 0x10000** rather than BAR1 + 0. The driver's resource manager only
protects a boot console that starts exactly at BAR1, so it misses this one and allocates
VRAM over the live framebuffer.

**Fix.** [`nvidia/surface-studio-console-offset.patch`](nvidia/surface-studio-console-offset.patch)
for the `nvidia-open` kernel modules. It reports the console as starting at BAR1 + 0,
with its size padded by the offset, so the driver reserves and preserves that VRAM. It
also logs one `studio-nvidia: boot console ...` line per GPU init, so you can confirm the
protection in `dmesg`.

The working setup (Omarchy, `nvidia-open-dkms`):
- `nvidia_drm` and `nvidia_modeset` are blacklisted
  (`module_blacklist=nvidia_drm,nvidia_modeset`), so Hyprland keeps running on the boot
  framebuffer (`simpledrm`).
- The patched `nvidia` module gives CUDA and `nvidia-smi`.
- A pacman hook re-applies the patch to the DKMS source on every driver upgrade, before
  DKMS rebuilds. It has carried forward from 610.x to 615.x unchanged.

```sh
sudo install -Dm644 nvidia/surface-studio-console-offset.patch /etc/studio-nvidia/surface-studio-console-offset.patch
sudo install -Dm755 nvidia/apply-console-patch.sh /usr/local/lib/studio-nvidia/apply-console-patch.sh
sudo install -Dm644 nvidia/60-studio-nvidia-console.hook /etc/pacman.d/hooks/60-studio-nvidia-console.hook
sudo /usr/local/lib/studio-nvidia/apply-console-patch.sh && sudo dkms autoinstall
```

**Not solved yet.** NVIDIA driving the panel itself (`nvidia_drm` modeset). The patch
pads the console's size but not its width, height or pitch, so a modeset console restore
would draw 64 KB off. Suspend/resume with the driver loaded is also unreliable on this
machine. Both are being worked on.

## Heat: sustained throttling

**Symptom.** Under sustained load the package hits its 100 °C limit and
`package_throttle_count` keeps climbing.

**Cause.** The fan is a binary ACPI `PNP0C0B` device: on or off, with no variable speed,
and already at maximum under load. The stock sustained power limit (PL1 = 45 W) is more
than that airflow can remove.

**Fix.** [`thermal/cpu-power-cap.service`](thermal/cpu-power-cap.service) caps PL1 at
28 W through RAPL and leaves PL2 alone, so short bursts still get full turbo. Under real
desktop load this held the high 70s to low 80s °C with no new throttle events, versus
continuous throttling at 45 W.

```sh
sudo install -Dm644 thermal/cpu-power-cap.service /etc/systemd/system/cpu-power-cap.service
sudo systemctl enable --now cpu-power-cap.service
```

## Touch: single-touch only

**Symptom.** The touch panel (`045e:0911`) works as a single-touch mouse, with no
multitouch gestures.

**Cause.** The digitizer boots in mouse-emulation mode. Windows switches it by sending
HID Feature Report 10 = `0x02` (the Windows 8 digitizer "Device Mode" convention). This
descriptor exposes InputMode (usage `0x52`) only as an Input field, so `hid-multitouch`
never sends the switch.

**Fix.** A udev rule runs [`touch/surface-touch-multitouch`](touch/surface-touch-multitouch),
a short Python script, to send that report at boot and hotplug.

```sh
sudo install -Dm755 touch/surface-touch-multitouch /usr/local/bin/surface-touch-multitouch
sudo install -Dm644 touch/99-surface-touch-multitouch.rules /etc/udev/rules.d/99-surface-touch-multitouch.rules
sudo udevadm control --reload && sudo udevadm trigger -s hidraw
```

## Display: red line on the top edge

**Symptom.** After an Omarchy update, a thin red line appears along the very top edge.
It shows even on a text console, but not in screenshots.

**Cause.** An Omarchy migration added `quiet: yes` to `/boot/limine.conf`.

**Fix.** Back up `/boot/limine.conf`, change that line to `quiet: no`, and reboot. Setting
it explicitly to `no` also stops the migration from adding it back.

## Pen: tip stops working

The Surface Pen's tip and hover go through the panel's own USB HID digitizer, not
Bluetooth; Bluetooth carries only the tail button. So a dead tip is not a pen battery
problem.

If the digitizer is silent at the kernel level (no events in `evtest` or `libinput
debug-events`, from either the pen or touch), a USB reset or rebind is not enough.
**Shut down and unplug the Studio from power for a minute.** That full power cut is what
brought it back.

Pen buttons and the Surface Dial are handled by
[re:dial](https://github.com/bybrooksco/redial).

## Streaming: full-screen 3:2 game streaming

The Studio makes a good thin client for a Sunshine gaming PC through
[Moonlight](https://moonlight-stream.org).

- **Fill the 3:2 screen.** A headless host's dummy plug only advertises 16:9. Give it a
  3:2 mode with [dummy-edid](https://github.com/bybrooksco/dummy-edid). 3600x2400@60 fits
  HDMI 2.0; 3840x2560@60 does not.
- **Launcher.** [`streaming/moonlight-stream`](streaming/moonlight-stream) holds the
  known-good flags, each explained in its comments:
  - `QT_QPA_PLATFORM=xcb` for mouse capture on Hyprland
  - hardware VA-API decode on the Intel iGPU
  - `--no-hdr`, which avoids a black-band glitch
  - 3600x2400 at 100 Mbps
- **Heat.** Decode runs on the iGPU (about 10% CPU), so bitrate adds little load. If long
  sessions run warm, lower `--bitrate`.

```sh
install -Dm755 streaming/moonlight-stream ~/.local/bin/moonlight-stream
moonlight-stream 192.168.1.50   # your Sunshine host
```

## License

MIT, see `LICENSE`.
