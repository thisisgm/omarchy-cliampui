// Run with: deno run --allow-read tests/model.test.js
// Model.js has no exports, so it is evaluated here rather than imported.

const source = Deno.readTextFileSync(new URL("../Model.js", import.meta.url))
const Model = new Function(
  source + "; return { defaultStatus, parseStatus, rateFromNodeProps, sinkRateFromPactl, parseSinkAvailability, parsePlaylists, parseAlbums, isSupportedOutputRate, parseBands, coverArtUrlFromStreamPath, transcodedFromPath, bluetoothCodecLabel, verdict, formatTime, elideError, MAX_ERROR_CHARS }"
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

// Byte for byte from a real Navidrome track, tokens replaced. Note stream:true is set
// for library tracks as well as radio, so it cannot be the seekability test.
const nav = '{"ok":true,"state":"playing","track":{"title":"Billie (Loving Arms)","artist":"Fred again..","album":"Actual Life 2","genre":"Electronic","path":"https://music.example.com/rest/stream?c=cliamp&f=json&format=raw&id=rrH30XR3&s=SALT&t=TOKEN&u=USER&v=1.0.0","year":2021,"track_number":13,"duration_secs":217,"index":40,"stream":true},"position":37.49,"duration":217,"index":40,"total":44,"shuffle":false,"repeat":"Off"}'

const n = Model.parseStatus(nav)
check("navidrome parses", n.ok, true)
check("navidrome title", n.title, "Billie (Loving Arms)")
check("navidrome artist", n.artist, "Fred again..")
check("navidrome album", n.album, "Actual Life 2")
check("navidrome duration", n.durationSec, 217)
check("navidrome position", n.positionSec, 37.49)
check("navidrome is flagged a stream", n.isStream, true)
check("navidrome queue depth", n.total, 44)

// A library track has a duration, radio does not, which is the real seekability test.
check("radio has no duration", Model.parseStatus(radio).durationSec, 0)

check("cover art is derived from the stream url",
  Model.coverArtUrlFromStreamPath(n.path, 300),
  "https://music.example.com/rest/getCoverArt?c=cliamp&id=rrH30XR3&s=SALT&t=TOKEN&u=USER&v=1.0.0&size=300")
check("cover art needs a stream url", Model.coverArtUrlFromStreamPath("http://radio.example/stream", 300), "")
check("cover art refuses plaintext", Model.coverArtUrlFromStreamPath("http://music.example.com/rest/stream?id=1&u=a&t=b&s=c", 300), "")
check("cover art of a local file", Model.coverArtUrlFromStreamPath("/tmp/x.flac", 300), "")
check("cover art of nothing", Model.coverArtUrlFromStreamPath("", 300), "")

check("format=raw is not transcoded", Model.transcodedFromPath(n.path), false)
check("a missing format=raw is transcoded",
  Model.transcodedFromPath("https://music.example.com/rest/stream?id=1&format=mp3"), true)
check("a local file is not transcoded", Model.transcodedFromPath("/tmp/x.flac"), false)

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

// omarchy-audio-sink-availability, one sink per line, name then a 0 or 1.
check("availability marks a live sink", Model.parseSinkAvailability("alsa_output.x\t1"), { "alsa_output.x": true })
check("availability marks a dead sink", Model.parseSinkAvailability("hdmi.y\t0"), { "hdmi.y": false })
check("availability handles both", Model.parseSinkAvailability("a\t1\nb\t0"), { a: true, b: false })
check("availability ignores junk", Model.parseSinkAvailability("nonsense\n\n"), {})
check("availability of nothing", Model.parseSinkAvailability(""), {})

// cliamp playlist list, byte for byte from the box.
check("playlists parse", Model.parsePlaylists("  Recently Played  8 tracks"), [{ name: "Recently Played", count: 8 }])
check("a singular track parses", Model.parsePlaylists("  Solo  1 track"), [{ name: "Solo", count: 1 }])
check("several playlists", Model.parsePlaylists("  A  2 tracks\n  B B  10 tracks"), [{ name: "A", count: 2 }, { name: "B B", count: 10 }])
check("a header line is ignored", Model.parsePlaylists("No playlists found."), [])
check("empty playlist output", Model.parsePlaylists(""), [])

// cliamp outputs a fixed rate, so a known source rate is required before the full
// claim is made. Measured: a 48 kHz file leaves cliamp at 44100 with default config.
// cliamp accepts only these output rates, so 88.2 can never be played natively.
check("44.1 is a supported output rate", Model.isSupportedOutputRate(44100), true)
check("96 is supported", Model.isSupportedOutputRate(96000), true)
check("88.2 is not", Model.isSupportedOutputRate(88200), false)
check("zero is not", Model.isSupportedOutputRate(0), false)

// One NDJSON frame from {"cmd":"bands"}, byte for byte from the docs.
check("bands parse", Model.parseBands('{"ok":true,"visualizer":"Bars","bands":[0.93,0.81,0.62]}'), [0.93, 0.81, 0.62])
check("bands clamp above one", Model.parseBands('{"ok":true,"bands":[1.4,-0.2]}'), [1, 0])
check("a failed frame yields nothing", Model.parseBands('{"ok":false,"error":"x"}'), [])
check("garbage yields nothing", Model.parseBands("not json"), [])
check("empty yields nothing", Model.parseBands(""), [])

check("albums parse", Model.parseAlbums('[{"id":"a1","name":"Discovery","artist":"Daft Punk","songCount":14}]'),
  [{ id: "a1", name: "Discovery", artist: "Daft Punk", songCount: 14 }])
check("an album without an id is skipped", Model.parseAlbums('[{"name":"x"}]'), [])
check("garbage albums yield nothing", Model.parseAlbums("nope"), [])
check("empty albums", Model.parseAlbums("[]"), [])

check("bit-perfect needs the source rate to agree",
  Model.verdict({ sourceRate: 44100, streamRate: 44100, sinkRate: 44100, unityGain: true, eqFlat: true, transcoded: false, codec: "FLAC" }),
  { ok: true, text: "FLAC 44.1 kHz · bit-perfect" })

check("an unknown source rate stops short of the claim",
  Model.verdict({ streamRate: 44100, sinkRate: 44100, unityGain: true, eqFlat: true, transcoded: false, codec: "FLAC" }),
  { ok: false, text: "FLAC 44.1 kHz · no resampling after cliamp" })

check("cliamp resampling the file is named",
  Model.verdict({ sourceRate: 48000, streamRate: 44100, sinkRate: 44100, unityGain: true, eqFlat: true, transcoded: false, codec: "FLAC" }),
  { ok: false, text: "48 → 44.1 kHz · cliamp resampled" })

check("resampled names both rates",
  Model.verdict({ streamRate: 44100, sinkRate: 48000, unityGain: true, transcoded: false, codec: "FLAC" }),
  { ok: false, text: "44.1 → 48 kHz · resampled" })

// The measured trap: a force was requested, this DAC has no 88.2, PipeWire silently
// lands on 96, and only the requested rate reveals that the DAC is what refused.
check("nearest-rate substitution is named",
  Model.verdict({ streamRate: 88200, sinkRate: 96000, unityGain: true, transcoded: false, codec: "FLAC", requestedRate: 88200 }),
  { ok: false, text: "88.2 → 96 kHz · output has no 88.2" })

// Same rates, but nothing was forced, so the DAC is not the thing to blame.
check("an unforced mismatch does not blame the DAC",
  Model.verdict({ streamRate: 88200, sinkRate: 96000, unityGain: true, transcoded: false, codec: "FLAC", requestedRate: 0 }),
  { ok: false, text: "88.2 → 96 kHz · resampled" })

check("bluez codec is named", Model.bluetoothCodecLabel({ "api.bluez5.codec": "sbc_xq" }), "SBC-XQ")
check("aac is named", Model.bluetoothCodecLabel({ "api.bluez5.codec": "aac" }), "AAC")
check("an unknown codec still shows", Model.bluetoothCodecLabel({ "api.bluez5.codec": "wibble" }), "WIBBLE")
check("a wired sink has no codec", Model.bluetoothCodecLabel({ "node.name": "alsa_output.x" }), "")
check("no props, no codec", Model.bluetoothCodecLabel(null), "")

// A2DP re-encodes, so matching the rate would still not make it bit-perfect.
check("a bluetooth link is called lossy, not merely resampled",
  Model.verdict({ streamRate: 44100, sinkRate: 48000, unityGain: true, transcoded: false, codec: "", requestedRate: 44100, lossyLink: "SBC-XQ" }),
  { ok: false, text: "44.1 kHz · SBC-XQ · lossy" })

check("even matched rates over bluetooth are not bit-perfect",
  Model.verdict({ streamRate: 48000, sinkRate: 48000, unityGain: true, transcoded: false, codec: "FLAC", requestedRate: 0, lossyLink: "AAC" }),
  { ok: false, text: "48 kHz · AAC · lossy" })

// AirPods on SBC-XQ hold the link at 48 kHz, so a 44.1 track is refused the same way.
check("a wired output that refuses a rate is still named",
  Model.verdict({ streamRate: 44100, sinkRate: 48000, unityGain: true, transcoded: false, codec: "", requestedRate: 44100 }),
  { ok: false, text: "44.1 → 48 kHz · output has no 44.1" })

// A force that the sink honoured is not a substitution either.
check("an honoured force reports bit-perfect",
  Model.verdict({ sourceRate: 44100, streamRate: 44100, sinkRate: 44100, unityGain: true, transcoded: false, codec: "FLAC", requestedRate: 44100 }),
  { ok: true, text: "FLAC 44.1 kHz · bit-perfect" })

// cliamp calls an untouched EQ "Custom", so only the band values can be trusted.
check("an untouched EQ is flat", Model.parseStatus(local).eqFlat, true)
check("a raised band is not flat",
  Model.parseStatus('{"ok":true,"state":"playing","eq_bands":[0,0,3,0,0,0,0,0,0,0]}').eqFlat, false)
check("a missing eq is treated as flat",
  Model.parseStatus('{"ok":true,"state":"playing"}').eqFlat, true)

check("EQ breaks it even when rates and gain are right",
  Model.verdict({ streamRate: 44100, sinkRate: 44100, unityGain: true, eqFlat: false, transcoded: false, codec: "FLAC" }),
  { ok: false, text: "FLAC 44.1 kHz · EQ applied" })

check("gain breaks it even when rates match",
  Model.verdict({ streamRate: 44100, sinkRate: 44100, unityGain: false, transcoded: false, codec: "FLAC" }),
  { ok: false, text: "FLAC 44.1 kHz · volume applied" })

check("a transcoded stream can never be bit-perfect",
  Model.verdict({ streamRate: 44100, sinkRate: 44100, unityGain: true, transcoded: true, codec: "MP3" }),
  { ok: false, text: "MP3 · transcoded by server" })

check("unknown rates say nothing",
  Model.verdict({ streamRate: 0, sinkRate: 0, unityGain: true, transcoded: false, codec: "" }),
  { ok: false, text: "" })

check("zero time", Model.formatTime(0), "0:00")
check("one minute 47", Model.formatTime(107), "1:47")
check("over an hour", Model.formatTime(3723), "1:02:03")
check("negative is clamped", Model.formatTime(-5), "0:00")
check("fractional seconds floor", Model.formatTime(107.9), "1:47")
check("non-numeric is zero", Model.formatTime("x"), "0:00")

check("error whitespace collapses", Model.elideError("a\n\n  b"), "a b")
check("long error is cut", Model.elideError("x".repeat(300)).length, Model.MAX_ERROR_CHARS)
check("empty error stays empty", Model.elideError(""), "")

console.log(failures === 0 ? "all model tests passed" : failures + " failing")
if (failures > 0) Deno.exit(1)
