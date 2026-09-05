// PingScope — shared helpers: site list normalization, ping output parsing,
// formatting, and status thresholds. Lives in a .js model (the house pattern
// across Omarchy plugins) so the bar face and the panel share one
// implementation.

// The widget measures at most four hosts. Enforced here as well as in the
// panel UI, so a hand-edited shell.json with extra entries still clamps.
function maxSites() { return 4 }

function defaultSites() { return ["google.com", "github.com", "cloudflare.com", "reddit.com"] }

// The bar's shared tooltip renders Text.AutoText, so neutralize markup at
// that boundary before configuration-derived hosts reach it.
function escapeMarkup(value) {
  return String(value === undefined || value === null ? "" : value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")
}

// Reduce user input to the bare hostname ping expects:
// "https://Example.com/page" -> "example.com".
function cleanHost(raw) {
  var text = String(raw === undefined || raw === null ? "" : raw).trim()
  if (text === "") return ""
  text = text.replace(/^[a-zA-Z][a-zA-Z0-9+.\-]*:\/\//, "")
  text = text.split("/")[0]
  text = text.split("@").pop()
  text = text.split(":")[0]
  text = text.split("?")[0]
  return text.toLowerCase()
}

// QML `var` property arrays sometimes arrive in JS module functions as
// JSValue lists that fail `Array.isArray` (the shell's MultiSelect documents
// the same gotcha). Accept anything array-like instead and hand back a real
// JS array.
function arrayFrom(value) {
  if (value === null || value === undefined) return []
  if (typeof value === "string") return value.split(/[\s,]+/)
  if (Array.isArray(value)) return value
  if (typeof value.length === "number") {
    var out = []
    for (var i = 0; i < value.length; i++) out.push(value[i])
    return out
  }
  return []
}

// Normalize the `sites` setting into at most MAX_SITES unique, clean
// hostnames. Accepts an array (the normal shape, written by the panel) or a
// comma/space separated string (convenient for hand-editing shell.json).
function normalizeSites(raw) {
  var source = arrayFrom(raw)
  var sites = []
  for (var i = 0; i < source.length && sites.length < maxSites(); i++) {
    var host = cleanHost(source[i])
    if (host === "" || sites.indexOf(host) !== -1) continue
    sites.push(host)
  }
  return sites
}

// Parse iputils `ping -c1 -W2` stdout into latency in ms, or -1 when the
// probe failed (timeout, DNS error, unreachable) or the output is
// unreadable. The summary line
//   "rtt min/avg/max/mdev = 28.1/28.1/28.1/0.0 ms"
// is preferred; the per-packet "time=28.1 ms" is the fallback for ping
// builds (busybox) that only print it.
function parsePing(raw) {
  var text = String(raw || "")
  var summary = text.match(/=\s*([\d.]+)\/([\d.]+)\/([\d.]+)\/([\d.]+)\s*ms/)
  if (summary) {
    var average = Number(summary[2])
    if (isFinite(average) && average >= 0) return average
  }
  var single = text.match(/time[=<]\s*([\d.]+)\s*ms/)
  if (single) {
    var value = Number(single[1])
    if (isFinite(value) && value >= 0) return value
  }
  return -1
}

// "24ms" / "1.2s" / "\u2014". Always a string so QML text bindings stay clean.
function formatMs(latencyMs) {
  var value = Number(latencyMs)
  if (!isFinite(value) || value < 0) return "\u2014"
  if (value >= 1000) return (value / 1000).toFixed(1) + "s"
  return Math.round(value) + "ms"
}

// good | warning | bad | down | idle.
//   idle  — no sample yet (fresh host, first probe in flight)
//   down  — probed and failed (timeout / DNS / unreachable)
function statusFor(latencyMs, hasSample, greenMaxMs, redMinMs) {
  if (!hasSample) return "idle"
  var value = Number(latencyMs)
  if (!isFinite(value) || value < 0) return "down"
  var displayedValue = Math.round(value)
  if (displayedValue >= redMinMs) return "bad"
  if (displayedValue > greenMaxMs) return "warning"
  return "good"
}
