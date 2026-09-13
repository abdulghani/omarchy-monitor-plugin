# System Monitor — Omarchy bar widget

CPU, RAM, and storage usage in the [Omarchy](https://omarchy.org/) status bar,
with a popup breaking down all three and a switch that caps CPU speed.

The bar slot carries **one** metric at a time. Which one is picked from chips at
the top of the popup, so the readout stays legible in a 26px bar instead of
crowding three figures into it.

```
bar:     󰻠 5%

popup:   SHOW IN BAR
         [ 󰻠 CPU ]  [ 󰍛 RAM ]  [ 󰋊 Disk ]
         ─────────────────────────────────
         CPU      5%          load 0.63 0.96 0.93
                                       12 cores
         ▁▃▁▂▅▁▁▂▁▁▃▁          ← per-core load
         Throttle CPU                     [  ●]
         Every core is capped at 1.1 GHz.
         ─────────────────────────────────
         MEMORY
         RAM   16%                4.6 / 30.1 GiB
         Swap   0%                0.0 / 60.2 GiB
         ─────────────────────────────────
         STORAGE
         /      8%                 37 / 475 GiB
         boot   7%                0.1 / 2.0 GiB
         ─────────────────────────────────
         FANS
         Fan                        Stopped
                        Control   Automatic
```

- **Left-click** the bar — open the popup
- **Right-click** — open `btop`
- **Hover** — all three metrics at once, whichever is on the bar

The label turns your theme's urgent color when CPU, RAM, *or* storage crosses
90% — including the metrics that are not currently shown, so a filling disk
still gets noticed while you are watching CPU.

**CPU throttle** — one switch under the CPU readout that caps every core's top
speed. On `amd-pstate` machines the cap is the driver's *lowest non-linear
frequency*, the point below which a core only gets slower rather than more
efficient (1.1 GHz on a Ryzen 5 PRO 6650U); elsewhere it is half the core's top
speed. Switching off lifts the cap entirely instead of writing today's top
speed back, so turbo enabled later — the performance profile does that — is not
pinned underneath it.

> **Set expectations.** The power-saver profile already picks the most frugal
> energy preference and turns turbo off. The cap adds to that, and it pays
> under **sustained** load — builds, video calls, a browser full of busy tabs —
> where it trades speed for watts, heat, and fan noise. Light, bursty work
> already finishes quickly and drops back to idle, so the saving there is small.

The kernel forgets the cap at reboot; the widget remembers the switch and puts
the cap back when it starts. Power profiles leave the speed cap alone, so the
switch and the profile combine rather than fight.

## Install

```bash
omarchy plugin add https://github.com/abdulghani/omarchy-monitor-plugin.git --enable --yes
omarchy restart shell
```

Then place it wherever you like on the bar:

```bash
omarchy bar move abdulghani.sysmon --section right --before omarchy.power
```

> Editing plugin files hot-reloads the code, but the bar does not re-place an
> already-laid-out widget. Run `omarchy restart shell` after any change.

The throttle switch writes CPU speed caps, which are root-owned. Grant write
access once:

```bash
sudo install -m 0644 -o root -g root \
  ~/.config/omarchy/plugins/abdulghani.sysmon/omarchy-monitor-cpu.conf \
  /etc/tmpfiles.d/omarchy-monitor-cpu.conf
sudo systemd-tmpfiles --create /etc/tmpfiles.d/omarchy-monitor-cpu.conf
```

This makes each CPU policy's `scaling_max_freq` group-writable by `wheel` and
nothing else — governors, energy preferences, and turbo stay root-only — and it
reapplies on every boot. Skip it and the switch shows the current state
read-only, and says so.

> **Trade-off worth understanding:** any process running as you can then cap
> your CPU speed. That is the price of a switch that responds without a
> password prompt.

## Remove

```bash
omarchy plugin remove abdulghani.sysmon --yes
sudo rm /etc/tmpfiles.d/omarchy-monitor-cpu.conf
rm -rf ~/.local/state/abdulghani.sysmon
omarchy restart shell
```

The bar-metric setting lives inline in the widget's `~/.config/omarchy/shell.json`
entry and is managed by the shell, so removing the widget from the bar takes it
with it. The one file kept outside the plugin's own directory is the throttle
switch's position, in `~/.local/state/abdulghani.sysmon/`.

A CPU cap left on lasts until the next reboot. To lift it straight away:

```bash
echo 2147483647 | sudo tee /sys/devices/system/cpu/cpufreq/policy*/scaling_max_freq
```

## Configuration

| Key | Values | Default | What it does |
|---|---|---|---|
| `barMetric` | `cpu`, `memory`, `storage` | `cpu` | Which metric the bar label shows |

Set from the popup, or from the CLI:

```bash
omarchy bar set abdulghani.sysmon barMetric memory
```

**Fans** — RPM per fan, plus the control level where the vendor exposes one
(ThinkPads report `auto`, `full-speed`, or a numeric level via
`/proc/acpi/ibm/fan`). A fan reading zero is shown as **Stopped** rather than
`0 rpm`, since most laptops idle with the fan off. The section hides entirely
on machines with no fan sensor.

## Requirements

Bash, `awk`, `df`, and `nproc` — all present on a stock Omarchy install. The
bar glyphs are Nerd Font icons, which Omarchy's default bar font provides.

The throttle switch needs a cpufreq driver exposing per-policy speed caps,
which nearly every laptop has, and hides itself where there is none:

```bash
ls /sys/devices/system/cpu/cpufreq/policy*/scaling_max_freq
```

## How it works

`sample.sh` emits raw counters from `/proc/stat`, `/proc/meminfo`,
`/proc/loadavg`, and `df`; the QML side diffs consecutive samples. So CPU
describes the gap between polls rather than time since boot, and no reader
process stays resident — one short-lived script per poll, nothing between
ticks.

Polling runs at 5s while only the bar label depends on it, and 1.5s while the
popup is open. A second sample 600ms after startup means CPU shows a real
figure right after login instead of holding `—` for a full interval.

hwmon indices are assigned in probe order and move between boots, so the fan
chip is found by name rather than a fixed `hwmonN` path. `acpi_fan` and a
vendor chip often report the same physical fan; the vendor chip wins, since
`acpi_fan` is frequently a stub reading zero.

Btrfs subvolumes and bind mounts report the same source device, so the sampler
keeps the first mountpoint seen per source. Otherwise one disk lists several
times with identical figures.

`throttle.sh` owns the CPU cap: `on` writes each policy's cap to
`scaling_max_freq`, `off` writes a value above any real frequency (the kernel
clamps it to whatever maximum is in force), and `status` reports the state
for `sample.sh`. Because `status` runs on every poll, it reads sysfs with shell
builtins and forks nothing. The switch's position is kept in
`~/.local/state/abdulghani.sysmon/cpu-throttle`, and `throttle.sh restore`
reapplies it once when the widget starts.

## License

MIT — see [LICENSE](LICENSE).
