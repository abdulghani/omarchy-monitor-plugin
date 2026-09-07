#!/usr/bin/env bash
# One sample of CPU / memory / storage, as flat whitespace-delimited lines.
# Counters are emitted raw; the QML side diffs consecutive samples so CPU
# percentages describe the gap between polls rather than the time since boot.
#
#   cpu   <name> <total-jiffies> <idle-jiffies>   (aggregate "cpu", then cpu0..N)
#   mem   <MemTotal|MemAvailable|SwapTotal|SwapFree> <kB>
#   load  <1m> <5m> <15m>
#   cores <n>
#   disk  <mountpoint> <used-bytes> <size-bytes>
#   fan   <label> <rpm>                 (one per fan on the chosen chip)
#   fanlevel <level>                    (ThinkPad fan control level, if exposed)

set -uo pipefail
export LC_ALL=C

# $2..$9 are user nice system idle iowait irq softirq steal; idle+iowait is the
# part of the interval the core was not doing work.
awk '/^cpu/ { print "cpu", $1, $2+$3+$4+$5+$6+$7+$8+$9, $5+$6 }' /proc/stat

awk '/^MemTotal:|^MemAvailable:|^SwapTotal:|^SwapFree:/ { print "mem", $1, $2 }' /proc/meminfo

awk '{ print "load", $1, $2, $3 }' /proc/loadavg

printf 'cores %s\n' "$(nproc)"

# Real filesystems only. Btrfs subvolumes and bind mounts report the same
# device, so keep the first mountpoint seen per source and drop the rest —
# otherwise one disk is listed four times with identical figures.
df -B1 -x tmpfs -x devtmpfs -x efivarfs -x squashfs -x overlay -x ramfs \
   --output=source,target,used,size 2>/dev/null |
  tail -n +2 |
  awk '!seen[$1]++ { print "disk", $2, $3, $4 }'

# ---- Fans ------------------------------------------------------------------
# hwmon indices are assigned in probe order and move between boots, so the chip
# is found by name rather than by a fixed hwmonN path.
#
# acpi_fan and a vendor chip often report the same physical fan, which would
# list it twice. Prefer the vendor chip: it reports real RPM where acpi_fan is
# frequently a stub reading zero.
fan_chip=""
for h in /sys/class/hwmon/hwmon*; do
  [ -r "$h/name" ] || continue
  ls "$h"/fan*_input >/dev/null 2>&1 || continue
  name=$(cat "$h/name" 2>/dev/null)
  if [ "$name" != "acpi_fan" ]; then
    fan_chip="$h"
    break
  fi
  [ -z "$fan_chip" ] && fan_chip="$h"
done

if [ -n "$fan_chip" ]; then
  for f in "$fan_chip"/fan*_input; do
    [ -r "$f" ] || continue
    base=${f%_input}
    # A chip may name its fans; fall back to the bare fanN when it does not.
    label=$(cat "${base}_label" 2>/dev/null) || label=""
    [ -n "$label" ] || label=$(basename "$base")
    printf 'fan %s %s\n' "$(printf '%s' "$label" | tr ' ' '-')" "$(cat "$f" 2>/dev/null || echo 0)"
  done
fi

# ThinkPad exposes the control level alongside the reading: "auto", "full-speed",
# or 0-7. Useful context for a fan sitting at 0 RPM.
if [ -r /proc/acpi/ibm/fan ]; then
  level=$(awk -F':' '/^level:/ { gsub(/[ \t]/, "", $2); print $2 }' /proc/acpi/ibm/fan 2>/dev/null)
  [ -n "$level" ] && printf 'fanlevel %s\n' "$level"
fi
