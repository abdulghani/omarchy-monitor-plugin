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
