// Run with: deno run --allow-read tests/model.test.js
// Model.js has no exports, so it is evaluated here rather than imported.

const source = Deno.readTextFileSync(new URL("../Model.js", import.meta.url))
const Model = new Function(
  source + "; return { defaultStatus, parseStatus, rateFromNodeProps, sinkRateFromPactl, verdict, formatTime, elideError, MAX_ERROR_CHARS }"
)()

let failures = 0

function check(name, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) {
    failures++
    console.log("FAIL " + name + "\n  expected " + JSON.stringify(expected) + "\n  got      " + JSON.stringify(actual))
  }
}

// Byte for byte what a running TUI printed on the box, radio queue included.
const radio = '{"ok":true,"state":"stopped","track":{"title":"Lofi Stream","path":"http://radio.cliamp.stream/lofi/stream","stream":true},"volume":-30,"total":11,"visualizer":"Bars","shuffle":false,"repeat":"Off","mono":false,"speed":1,"eq_preset":"Custom","eq_bands":[0,0,0,0,0,0,0,0,0,0]}'

const r = Model.parseStatus(radio)
check("radio parses", r.ok, true)
check("radio title", r.title, "Lofi Stream")
check("radio is a stream", r.isStream, true)
check("radio volume in dB", r.volumeDb, -30)
check("radio queue depth", r.total, 11)
check("radio repeat", r.repeat, "Off")

// Byte for byte from a daemon playing a local file, which carries position and duration.
const local = '{"ok":true,"state":"playing","track":{"title":"probe441","path":"/tmp/probe441.flac"},"position":16.873469387,"duration":600,"volume":-6.041199826559248,"total":1,"shuffle":false,"repeat":"Off","mono":false,"speed":1,"eq_preset":"Custom","eq_bands":[0,0,0,0,0,0,0,0,0,0]}'

const l = Model.parseStatus(local)
check("local parses", l.ok, true)
check("local title", l.title, "probe441")
check("local is not a stream", l.isStream, false)
check("local keeps the fractional dB", l.volumeDb, -6.041199826559248)
check("local state", l.state, "playing")

// A daemon with nothing loaded omits track entirely and reports index -1.
const empty = Model.parseStatus('{"ok":true,"state":"stopped","volume":-30,"index":-1,"shuffle":false,"repeat":"Off","mono":false,"speed":1}')
check("empty parses", empty.ok, true)
check("empty title", empty.title, "")
check("empty is not a stream", empty.isStream, false)
check("empty total defaults to zero", empty.total, 0)

// cliamp exits 1 and prints this when no socket exists.
const down = Model.parseStatus("cliamp is not running (no socket at /home/user/.config/cliamp/cliamp.sock)")
check("down is not ok", down.ok, false)
check("down still returns the full shape", Object.keys(down).sort(), Object.keys(Model.defaultStatus()).sort())
check("down records why", down.lastError.length > 0, true)

check("empty input is not ok", Model.parseStatus("").ok, false)
check("null input does not throw", Model.parseStatus(null).ok, false)

// PipeWire publishes the stream rate as a period, so 1/44100 means 44100 Hz.
check("node.rate parses", Model.rateFromNodeProps({ "node.rate": "1/44100" }), 44100)
check("node.rate 96k", Model.rateFromNodeProps({ "node.rate": "1/96000" }), 96000)
check("missing node.rate is zero", Model.rateFromNodeProps({}), 0)
check("malformed node.rate is zero", Model.rateFromNodeProps({ "node.rate": "44100" }), 0)
check("null props is zero", Model.rateFromNodeProps(null), 0)

// pactl list short sinks, tab separated: id, name, driver, format, state
check("pactl rate parses", Model.sinkRateFromPactl("55\talsa_output.pci-0000_00_1f.3.analog-stereo\tPipeWire\ts32le 2ch 44100Hz\tRUNNING"), 44100)
check("pactl rate 48k", Model.sinkRateFromPactl("55\tx\tPipeWire\ts32le 2ch 48000Hz\tIDLE"), 48000)
check("pactl garbage is zero", Model.sinkRateFromPactl("nonsense"), 0)
check("pactl empty is zero", Model.sinkRateFromPactl(""), 0)

check("bit-perfect when everything lines up",
  Model.verdict({ streamRate: 44100, sinkRate: 44100, unityGain: true, transcoded: false, codec: "FLAC" }),
  { ok: true, text: "FLAC 44.1 kHz · bit-perfect" })

check("resampled names both rates",
  Model.verdict({ streamRate: 44100, sinkRate: 48000, unityGain: true, transcoded: false, codec: "FLAC" }),
  { ok: false, text: "FLAC 44.1 kHz · resampled to 48 kHz" })

// The measured trap: a force was requested, this DAC has no 88.2, PipeWire silently
// lands on 96, and only the requested rate reveals that the DAC is what refused.
check("nearest-rate substitution is named",
  Model.verdict({ streamRate: 88200, sinkRate: 96000, unityGain: true, transcoded: false, codec: "FLAC", requestedRate: 88200 }),
  { ok: false, text: "FLAC 88.2 kHz · resampled to 96 kHz, DAC has no 88.2" })

// Same rates, but nothing was forced, so the DAC is not the thing to blame.
check("an unforced mismatch does not blame the DAC",
  Model.verdict({ streamRate: 88200, sinkRate: 96000, unityGain: true, transcoded: false, codec: "FLAC", requestedRate: 0 }),
  { ok: false, text: "FLAC 88.2 kHz · resampled to 96 kHz" })

// A force that the sink honoured is not a substitution either.
check("an honoured force reports bit-perfect",
  Model.verdict({ streamRate: 44100, sinkRate: 44100, unityGain: true, transcoded: false, codec: "FLAC", requestedRate: 44100 }),
  { ok: true, text: "FLAC 44.1 kHz · bit-perfect" })

check("gain breaks it even when rates match",
  Model.verdict({ streamRate: 44100, sinkRate: 44100, unityGain: false, transcoded: false, codec: "FLAC" }),
  { ok: false, text: "FLAC 44.1 kHz · volume applied, not bit-perfect" })

check("a transcoded stream can never be bit-perfect",
  Model.verdict({ streamRate: 44100, sinkRate: 44100, unityGain: true, transcoded: true, codec: "MP3" }),
  { ok: false, text: "MP3 · transcoded by server" })

check("unknown rates say nothing",
  Model.verdict({ streamRate: 0, sinkRate: 0, unityGain: true, transcoded: false, codec: "" }),
  { ok: false, text: "" })

check("zero time", Model.formatTime(0), "0:00")
check("one minute 47", Model.formatTime(107000000), "1:47")
check("over an hour", Model.formatTime(3723000000), "1:02:03")
check("negative is clamped", Model.formatTime(-5), "0:00")
check("non-numeric is zero", Model.formatTime("x"), "0:00")

check("error whitespace collapses", Model.elideError("a\n\n  b"), "a b")
check("long error is cut", Model.elideError("x".repeat(300)).length, Model.MAX_ERROR_CHARS)
check("empty error stays empty", Model.elideError(""), "")

console.log(failures === 0 ? "all model tests passed" : failures + " failing")
if (failures > 0) Deno.exit(1)
