# System Monitor — Omarchy bar widget

CPU, RAM, and storage usage in the [Omarchy](https://omarchy.org/) status bar,
with a popup breaking down all three.

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
         ─────────────────────────────────
         MEMORY
         RAM   16%                4.6 / 30.1 GiB
         Swap   0%                0.0 / 60.2 GiB
         ─────────────────────────────────
         STORAGE
         /      8%                 37 / 475 GiB
         boot   7%                0.1 / 2.0 GiB
```

- **Left-click** the bar — open the popup
- **Right-click** — open `btop`
- **Hover** — all three metrics at once, whichever is on the bar

The label turns your theme's urgent color when CPU, RAM, *or* storage crosses
90% — including the metrics that are not currently shown, so a filling disk
still gets noticed while you are watching CPU.

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

## Remove

```bash
omarchy plugin remove abdulghani.sysmon --yes
omarchy restart shell
```

The plugin writes nothing outside its own directory. Its one setting lives
inline in the widget's `~/.config/omarchy/shell.json` entry and is managed by
the shell, so removing the widget from the bar takes the setting with it. No
state files, no caches, nothing left behind.

## Configuration

| Key | Values | Default | What it does |
|---|---|---|---|
| `barMetric` | `cpu`, `memory`, `storage` | `cpu` | Which metric the bar label shows |

Set from the popup, or from the CLI:

```bash
omarchy bar set abdulghani.sysmon barMetric memory
```

## Requirements

Bash, `awk`, `df`, and `nproc` — all present on a stock Omarchy install. The
bar glyphs are Nerd Font icons, which Omarchy's default bar font provides.

## How it works

`sample.sh` emits raw counters from `/proc/stat`, `/proc/meminfo`,
`/proc/loadavg`, and `df`; the QML side diffs consecutive samples. So CPU
describes the gap between polls rather than time since boot, and no reader
process stays resident — one short-lived script per poll, nothing between
ticks.

Polling runs at 5s while only the bar label depends on it, and 1.5s while the
popup is open. A second sample 600ms after startup means CPU shows a real
figure right after login instead of holding `—` for a full interval.

Btrfs subvolumes and bind mounts report the same source device, so the sampler
keeps the first mountpoint seen per source. Otherwise one disk lists several
times with identical figures.

## License

MIT — see [LICENSE](LICENSE).
