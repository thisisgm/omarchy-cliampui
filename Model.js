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
    durationSec: 0,
    artist: "",
    album: "",
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

  out.durationSec = numberOr(data.duration, 0)

  var track = data.track
  if (track && typeof track === "object") {
    out.title = String(track.title || "")
    out.path = String(track.path || "")
    out.artist = String(track.artist || "")
    out.album = String(track.album || "")
    out.isStream = track.stream === true
    if (out.durationSec <= 0) out.durationSec = numberOr(track.duration_secs, 0)
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

// Sample input, one line per sink from `omarchy-audio-sink-availability`:
// alsa_output.pci-0000_00_1f.3.analog-stereo\t1
// Same contract the stock audio panel parses, so an unplugged output is filtered
// out of the device list here exactly as it is there.
function parseSinkAvailability(raw) {
  var next = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    var parts = line.split("\t")
    if (parts.length >= 2) next[parts[0]] = parts[1] !== "0"
  }
  return next
}

// Sample input, the path cliamp reports for a Navidrome track:
// https://host/rest/stream?c=cliamp&f=json&format=raw&id=XXX&s=SALT&t=TOKEN&u=USER&v=1.0.0
// The same salted token already authorises cover art, so the panel can show artwork
// without ever being told a password. cliamp publishes no art of its own.
function coverArtUrlFromStreamPath(path, size) {
  var text = String(path || "")
  var cut = text.indexOf("?")
  if (cut < 0) return ""
  var base = text.slice(0, cut)
  if (base.indexOf("https://") !== 0) return ""
  var marker = "/rest/stream"
  if (base.slice(-marker.length) !== marker) return ""

  var keep = ["id", "u", "t", "s", "c", "v"]
  var parts = text.slice(cut + 1).split("&")
  var out = []
  for (var i = 0; i < parts.length; i++) {
    var eq = parts[i].indexOf("=")
    if (eq < 0) continue
    var key = parts[i].slice(0, eq)
    for (var j = 0; j < keep.length; j++) {
      if (key === keep[j]) { out.push(parts[i]); break }
    }
  }
  if (out.length === 0) return ""
  out.push("size=" + (size > 0 ? size : 300))
  return base.slice(0, base.length - marker.length) + "/rest/getCoverArt?" + out.join("&")
}

// cliamp asks Navidrome for format=raw, so its absence on a Subsonic stream means
// the server re-encoded the file before sending it.
function transcodedFromPath(path) {
  var text = String(path || "")
  if (text.indexOf("/rest/stream") < 0) return false
  return text.indexOf("format=raw") < 0
}

// Sample input, PipeWire props on a bluez sink:
// api.bluez5.codec = "sbc_xq", api.bluez5.profile = "a2dp-sink"
// Returns a display name only for a lossy A2DP link, and "" for anything wired.
function bluetoothCodecLabel(props) {
  if (!props) return ""
  var codec = String(props["api.bluez5.codec"] || "")
  if (codec.length === 0) return ""
  var names = {
    sbc: "SBC",
    sbc_xq: "SBC-XQ",
    aac: "AAC",
    aptx: "aptX",
    aptx_hd: "aptX HD",
    ldac: "LDAC",
    opus_05: "Opus"
  }
  return names[codec] || codec.toUpperCase()
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

  // A2DP re-encodes with SBC or AAC, both lossy, so a Bluetooth sink can never be
  // bit-perfect at any sample rate. Saying only "resampled" here would let someone
  // match rates and believe they had got there.
  var link = String(input.lossyLink || "")
  if (link.length > 0) {
    var lead = streamRate > 0 ? formatRate(streamRate) + " · " : ""
    return { ok: false, text: lead + link + " over Bluetooth, lossy link" }
  }
  if (streamRate <= 0 || sinkRate <= 0) {
    return { ok: false, text: "" }
  }

  var prefix = (codec ? codec + " " : "") + formatRate(streamRate)
  if (Math.abs(streamRate - sinkRate) > RATE_MATCH_TOLERANCE_HZ) {
    var text = prefix + " · resampled to " + formatRate(sinkRate)
    // A rate was forced and the sink took a different one: the 88.2 to 96 case on the
    // internal DAC, or AirPods on SBC-XQ which hold the link at 48 kHz. Only then is
    // the output the thing to blame, which the requested rate is what distinguishes
    // from an ordinary unforced mismatch.
    var requested = numberOr(input.requestedRate, 0)
    if (requested > 0 && Math.abs(requested - sinkRate) > RATE_MATCH_TOLERANCE_HZ) {
      text += ", output has no " + formatRate(requested).replace(" kHz", "")
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
