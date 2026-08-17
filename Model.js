// Pure helpers for the Cliamp panel. No QML imports, so this file is testable with Deno.

var MAX_ERROR_CHARS = 140
var SECONDS_PER_MINUTE = 60
var MINUTES_PER_HOUR = 60
// Rates within this many Hz are the same rate, covering integer rounding in the graph.
var RATE_MATCH_TOLERANCE_HZ = 1

function defaultStatus() {
  return {
    ok: false,
    state: "stopped",
    title: "",
    path: "",
    isStream: false,
    volumeDb: 0,
    total: 0,
    index: -1,
    shuffle: false,
    repeat: "Off",
    visualizer: "",
    lastError: ""
  }
}

// Sample input, from a running instance:
// {"ok":true,"state":"playing","track":{"title":"probe441","path":"/tmp/probe441.flac"},
//  "position":16.87,"duration":600,"volume":-6.04,"total":1,"shuffle":false,"repeat":"Off",...}
// A radio entry adds "stream":true inside track. When no socket exists cliamp exits 1
// and prints a plain sentence instead of JSON.
function parseStatus(raw) {
  var out = defaultStatus()
  var text = String(raw || "").trim()
  if (text.length === 0) {
    out.lastError = "cliamp returned nothing"
    return out
  }

  var data = null
  try {
    data = JSON.parse(text)
  } catch (e) {
    out.lastError = elideError(text)
    return out
  }
  if (!data || typeof data !== "object") {
    out.lastError = elideError(text)
    return out
  }

  out.ok = data.ok === true
  if (!out.ok) {
    out.lastError = elideError(String(data.error || text))
    return out
  }

  out.state = String(data.state || "stopped")
  out.volumeDb = numberOr(data.volume, 0)
  out.total = numberOr(data.total, 0)
  out.index = numberOr(data.index, -1)
  out.shuffle = data.shuffle === true
  out.repeat = String(data.repeat || "Off")
  out.visualizer = String(data.visualizer || "")

  var track = data.track
  if (track && typeof track === "object") {
    out.title = String(track.title || "")
    out.path = String(track.path || "")
    out.isStream = track.stream === true
  }
  return out
}

function numberOr(value, fallback) {
  var n = Number(value)
  return isFinite(n) ? n : fallback
}

// Sample input: PipeWire node properties carrying node.rate as a period, "1/44100".
function rateFromNodeProps(props) {
  if (!props) return 0
  var raw = String(props["node.rate"] || "")
  var parts = raw.split("/")
  if (parts.length !== 2) return 0
  var rate = parseInt(parts[1], 10)
  return isFinite(rate) && rate > 0 ? rate : 0
}

// Sample input, one line of `pactl list short sinks`, tab separated:
// 55\talsa_output.pci-0000_00_1f.3.analog-stereo\tPipeWire\ts32le 2ch 44100Hz\tRUNNING
function sinkRateFromPactl(raw) {
  var line = String(raw || "")
  var fields = line.split("\t")
  if (fields.length < 4) return 0
  var pieces = fields[3].split(" ")
  for (var i = 0; i < pieces.length; i++) {
    var piece = pieces[i]
    if (piece.slice(-2) !== "Hz") continue
    var rate = parseInt(piece.slice(0, -2), 10)
    if (isFinite(rate) && rate > 0) return rate
  }
  return 0
}

function formatRate(hz) {
  var rounded = Math.round(hz / 1000 * 10) / 10
  return String(rounded) + " kHz"
}

// The three conditions from the spec. "bit-perfect" is only ever said when all hold.
function verdict(v) {
  var input = v || {}
  var codec = String(input.codec || "")
  var streamRate = numberOr(input.streamRate, 0)
  var sinkRate = numberOr(input.sinkRate, 0)

  if (input.transcoded === true) {
    return { ok: false, text: (codec ? codec + " · " : "") + "transcoded by server" }
  }
  if (streamRate <= 0 || sinkRate <= 0) {
    return { ok: false, text: "" }
  }

  var prefix = (codec ? codec + " " : "") + formatRate(streamRate)
  if (Math.abs(streamRate - sinkRate) > RATE_MATCH_TOLERANCE_HZ) {
    var text = prefix + " · resampled to " + formatRate(sinkRate)
    // A rate was forced and the sink took a different one, which is the 88.2 to 96
    // case measured on this box. Only then is the DAC the thing to blame, so the
    // requested rate is what distinguishes it from an ordinary unforced mismatch.
    var requested = numberOr(input.requestedRate, 0)
    if (requested > 0 && Math.abs(requested - sinkRate) > RATE_MATCH_TOLERANCE_HZ) {
      text += ", DAC has no " + formatRate(requested).replace(" kHz", "")
    }
    return { ok: false, text: text }
  }
  if (input.unityGain !== true) {
    return { ok: false, text: prefix + " · volume applied, not bit-perfect" }
  }
  return { ok: true, text: prefix + " · bit-perfect" }
}

// Quickshell reports MPRIS position and length as doubles in seconds, not microseconds.
function formatTime(seconds) {
  var value = Number(seconds)
  if (!isFinite(value) || value < 0) value = 0
  var total = Math.floor(value)
  var secs = total % SECONDS_PER_MINUTE
  var minutes = Math.floor(total / SECONDS_PER_MINUTE) % MINUTES_PER_HOUR
  var hours = Math.floor(total / (SECONDS_PER_MINUTE * MINUTES_PER_HOUR))
  var ss = secs < 10 ? "0" + secs : String(secs)
  if (hours > 0) {
    var mm = minutes < 10 ? "0" + minutes : String(minutes)
    return hours + ":" + mm + ":" + ss
  }
  return minutes + ":" + ss
}

function elideError(raw) {
  var text = String(raw || "").replace(/\s+/g, " ").trim()
  if (text.length <= MAX_ERROR_CHARS) return text
  return text.slice(0, MAX_ERROR_CHARS)
}
