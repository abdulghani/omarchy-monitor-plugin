.pragma library

// Turn one sample.sh run into a plain object. Unknown line kinds are ignored
// so the script can grow new ones without breaking an older panel.
function parse(text) {
  var out = {
    cpu: {},            // name -> { total, idle }
    mem: {},            // MemTotal / MemAvailable / SwapTotal / SwapFree, in kB
    load: [0, 0, 0],
    cores: 0,
    disks: [],          // { mount, used, size }
    fans: [],           // { label, rpm }
    fanLevel: "",
    cpufreq: false,     // per-core speed caps exposed by the kernel
    cpufreqWritable: false,
    cpuCap: 0,          // kHz the throttle caps every core at
    throttle: false
  }

  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var f = lines[i].trim().split(/\s+/)
    if (f.length < 2) continue

    switch (f[0]) {
    case "cpu":
      if (f.length >= 4) out.cpu[f[1]] = { total: Number(f[2]), idle: Number(f[3]) }
      break
    case "mem":
      out.mem[f[1].replace(":", "")] = Number(f[2])
      break
    case "load":
      if (f.length >= 4) out.load = [Number(f[1]), Number(f[2]), Number(f[3])]
      break
    case "cores":
      out.cores = Number(f[1])
      break
    case "disk":
      if (f.length >= 4) out.disks.push({ mount: f[1], used: Number(f[2]), size: Number(f[3]) })
      break
    case "fan":
      if (f.length >= 3) out.fans.push({ label: f[1].replace(/-/g, " "), rpm: Number(f[2]) || 0 })
      break
    case "fanlevel":
      out.fanLevel = f[1]
      break
    case "cpufreq":
      out.cpufreq = f[1] === "yes"
      break
    case "cpufreqwritable":
      out.cpufreqWritable = f[1] === "yes"
      break
    case "cpucap":
      out.cpuCap = Number(f[1]) || 0
      break
    case "throttle":
      out.throttle = f[1] === "on"
      break
    }
  }
  return out
}

// Busy fraction per CPU, from the jiffies burned between two samples. A
// counter that went backwards means it was reset (suspend/resume, a core
// coming online), so that entry is dropped rather than reported as a spike.
function cpuUsage(prev, cur) {
  var usage = {}
  if (!prev) return usage

  for (var name in cur) {
    var a = prev[name]
    var b = cur[name]
    if (!a || !b) continue

    var dTotal = b.total - a.total
    var dIdle = b.idle - a.idle
    if (dTotal <= 0 || dIdle < 0) continue

    usage[name] = Math.max(0, Math.min(1, (dTotal - dIdle) / dTotal))
  }
  return usage
}

// cpu0, cpu1, ... in numeric order. Object key order is insertion order here,
// but sorting makes the core grid independent of how the sample was built.
function coreNames(usage) {
  var names = []
  for (var name in usage) if (name !== "cpu") names.push(name)
  names.sort(function (x, y) {
    return Number(x.replace("cpu", "")) - Number(y.replace("cpu", ""))
  })
  return names
}

function gib(bytes) {
  return bytes / 1073741824
}

// One decimal below 100, none above, so a row reads "4.6 / 30.1" but
// "436 / 475" instead of a needlessly precise "435.9".
function formatGib(bytes) {
  var v = gib(bytes)
  return v >= 100 ? v.toFixed(0) : v.toFixed(1)
}

function pairGib(used, total) {
  return formatGib(used) + " / " + formatGib(total) + " GiB"
}

function percent(part, whole) {
  return whole > 0 ? Math.round(100 * part / whole) : 0
}

// Shorten a mountpoint for a narrow column: "/" stays, "/home" -> "home".
function mountLabel(mount) {
  if (mount === "/") return "/"
  return mount.replace(/^\//, "")
}

// "fan1" is what the chip calls it; "Fan" reads better when there is only one.
function fanLabel(label, index, total) {
  if (total === 1) return "Fan"
  if (/^fan[0-9]+$/i.test(label)) return "Fan " + (index + 1)
  return label
}

// A fan reporting zero is stopped, not broken — most laptops idle with the fan
// off, so say so rather than showing a bare "0 rpm".
function fanSpeed(rpm) {
  return rpm > 0 ? rpm + " rpm" : "Stopped"
}

function fanLevelLabel(level) {
  if (!level) return ""
  if (level === "auto") return "Automatic"
  if (level === "full-speed" || level === "disengaged") return "Full speed"
  return "Level " + level
}

// Gigahertz, from the kernel's kilohertz, to one decimal.
function ghz(khz) {
  return ((Number(khz) || 0) / 1000000).toFixed(1) + " GHz"
}

// What the throttle switch does, in one line, so the panel explains it in place.
function throttleDescription(on, capKhz) {
  if (on)
    return "Every core is capped at " + ghz(capKhz) + ". Saves power under sustained load; heavy work takes longer."
  return "Caps every core at " + ghz(capKhz) + " to save power under sustained load. Remembered across reboots."
}
