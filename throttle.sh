#!/usr/bin/env bash
# Cap every CPU core at its most efficient speed, or lift the cap again.
#
#   throttle.sh on        cap every core and remember the switch as on
#   throttle.sh off       lift the cap and remember the switch as off
#   throttle.sh restore   reapply the cap if the switch was left on
#   throttle.sh status    print state lines for sample.sh:
#
#     cpufreq          yes|no   (does the kernel expose per-core speed caps)
#     cpufreqwritable  yes|no   (are they group-writable)
#     cpucap           <kHz>    (the speed "on" caps cores at; highest across cores)
#     throttle         on|off   (is every core at or below its cap right now)
#     throttlesaved    on|off   (the switch's remembered position)
#
# The caps are root-owned; the tmpfiles rule omarchy-monitor-cpu.conf makes
# them group-writable by wheel. Without it, on and off exit non-zero.
#
# status runs on every poll, so it reads with builtins and forks nothing.

set -uo pipefail
export LC_ALL=C

cpufreq=/sys/devices/system/cpu/cpufreq
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/abdulghani.sysmon"
state_file="$state_dir/cpu-throttle"

# Lifting the cap writes a value above any real frequency rather than the
# hardware maximum. The kernel keeps the request as written and clamps the
# limit to whatever maximum is in force, so turbo switched on later (the
# performance profile does) is not pinned under the non-turbo top speed.
# 2147483647 is the largest value a frequency limit request holds.
unlimited=2147483647

shopt -s nullglob
policies=("$cpufreq"/policy*)

# One-line file into REPLY, or $2 when it cannot be read.
get() {
  REPLY=$2
  [ -r "$1" ] && read -r REPLY < "$1" 2>/dev/null
  [ -n "$REPLY" ] || REPLY=$2
}

# The most efficient speed a core has, into CAP. amd-pstate reports the lowest
# frequency at which performance still scales linearly with power, and below
# it the work just takes longer for no saving. Without that, half the core's
# top speed.
cap_for() {
  get "$1/amd_pstate_lowest_nonlinear_freq" 0
  if [ "$REPLY" -gt 0 ] 2>/dev/null; then
    CAP=$REPLY
  else
    get "$1/cpuinfo_max_freq" 0
    CAP=$(( REPLY / 2 ))
  fi
}

remember() { mkdir -p "$state_dir" && printf '%s\n' "$1" > "$state_file"; }

# stderr is redirected before stdout so a refused write stays quiet; the
# exit status still reports it.
write_max() { printf '%s' "$2" 2>/dev/null > "$1/scaling_max_freq"; }

apply() {
  local p failed=0
  for p in "${policies[@]}"; do
    if [ "$1" = on ]; then
      cap_for "$p"
      write_max "$p" "$CAP" || failed=1
    elif ! write_max "$p" "$unlimited"; then
      # Fall back to the turbo top speed if a kernel refuses the large value.
      get "$p/amd_pstate_max_freq" 0
      [ "$REPLY" -gt 0 ] 2>/dev/null || get "$p/cpuinfo_max_freq" 0
      write_max "$p" "$REPLY" || failed=1
    fi
  done
  return $failed
}

status() {
  if [ ${#policies[@]} -eq 0 ] || [ ! -e "${policies[0]}/scaling_max_freq" ]; then
    echo "cpufreq no"
    return
  fi

  echo "cpufreq yes"
  [ -w "${policies[0]}/scaling_max_freq" ] && echo "cpufreqwritable yes" || echo "cpufreqwritable no"

  local p highest=0 capped=on
  for p in "${policies[@]}"; do
    cap_for "$p"
    [ "$CAP" -gt "$highest" ] && highest=$CAP
    get "$p/scaling_max_freq" 0
    [ "$REPLY" -le "$CAP" ] || capped=off
  done

  echo "cpucap $highest"
  echo "throttle $capped"
  get "$state_file" off
  [ "$REPLY" = on ] && echo "throttlesaved on" || echo "throttlesaved off"
}

case "${1:-status}" in
  on | off)
    apply "$1" || exit 1
    remember "$1"
    ;;
  restore)
    get "$state_file" off
    [ "$REPLY" = on ] || exit 0
    apply on
    ;;
  status)
    status
    ;;
  *)
    echo "Usage: throttle.sh on|off|restore|status" >&2
    exit 2
    ;;
esac
