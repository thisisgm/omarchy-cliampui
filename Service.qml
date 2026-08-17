import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})
  // The panel writes this so nothing polls while the popup is shut.
  property bool panelOpen: false

  property var status: Model.defaultStatus()
  property string lastError: ""

  readonly property string cliampPath: String(setting("cliampPath", "") || "cliamp")
  readonly property int statusIntervalMs: intSetting("statusIntervalSec", 2, 1, 10) * 1000

  // Bound by cliamp's own bus name, never to whichever player happens to be active,
  // because Chromium and others register MPRIS too and would otherwise drive this panel.
  readonly property var player: findCliampPlayer()

  readonly property bool running: player !== null
  readonly property bool hasTrack: running && (title.length > 0 || artist.length > 0)
  readonly property bool isPlaying: running && player.isPlaying === true
  readonly property string title: running ? String(player.trackTitle || "") : ""
  readonly property string artist: running ? String(player.trackArtist || status.artist || "") : ""
  readonly property string album: running ? String(player.trackAlbum || status.album || "") : ""

  // cliamp publishes no mpris:artUrl for anything, local or remote, so the cover is
  // derived from the Subsonic stream URL it does publish. The MPRIS value is still
  // preferred in case a future release starts sending one.
  readonly property string artUrl: {
    if (!running) return ""
    var fromMpris = safeArtUrl(player.trackArtUrl)
    if (fromMpris.length > 0) return fromMpris
    return safeArtUrl(Model.coverArtUrlFromStreamPath(status.path, artSizePx))
  }
  property int artSizePx: 300

  readonly property real lengthSec: {
    if (running && player.lengthSupported && Number(player.length || 0) > 0) return Number(player.length)
    return Number(status.durationSec || 0)
  }

  // Navidrome tracks carry stream:true exactly as radio does, so a known duration is
  // what separates something seekable from a live stream that never ends.
  readonly property bool canSeek: running && lengthSec > 0

  readonly property bool shuffle: status.shuffle === true
  readonly property string repeat: String(status.repeat || "Off")
  readonly property int total: Number(status.total || 0)
  readonly property real volumeDb: Number(status.volumeDb || 0)
  readonly property bool isStream: status.isStream === true

  // Ticked locally between MPRIS updates, because polling Position over D-Bus four
  // times a second is traffic for something the panel can count on its own.
  property real positionSec: 0

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  // Re-clamped on read so a hand-edited shell.json cannot poison the timer.
  function intSetting(name, fallback, min, max) {
    var value = parseInt(setting(name, fallback), 10)
    if (!isFinite(value)) value = fallback
    return Math.max(min, Math.min(max, value))
  }

  function findCliampPlayer() {
    var list = Mpris.players ? Mpris.players.values : []
    for (var i = 0; i < list.length; i++) {
      var p = list[i]
      if (!p) continue
      if (String(p.dbusName || "").indexOf("org.mpris.MediaPlayer2.cliamp") === 0) return p
    }
    return null
  }

  // Album art can be any string a tag supplies, so only these two schemes reach an Image.
  function safeArtUrl(raw) {
    var url = String(raw || "")
    if (url.indexOf("file://") === 0) return url
    if (url.indexOf("https://") === 0) return url
    return ""
  }

  function playPause() { if (running) player.togglePlaying() }
  function next() { if (running) player.next() }
  function previous() { if (running) player.previous() }

  // cliamp's MPRIS exposes a relative Seek and no SetPosition, so an absolute move
  // is expressed as a delta from where the panel believes the position to be.
  function seekTo(targetSec) {
    if (!canSeek) return
    var target = Math.max(0, Math.min(lengthSec, Number(targetSec) || 0))
    player.seek(target - positionSec)
    positionSec = target
  }

  function seekBy(deltaSec) { seekTo(positionSec + Number(deltaSec || 0)) }

  function refreshStatus() {
    if (statusProcess.running) return
    statusProcess.command = [cliampPath, "status", "--json"]
    statusProcess.running = true
  }

  function syncPosition() {
    positionSec = running && player.positionSupported ? Number(player.position || 0) : 0
    if (panelOpen) refreshStatus()
  }

  Process {
    id: statusProcess
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseStatus(text)
        root.status = parsed
        root.lastError = parsed.ok ? "" : parsed.lastError
      }
    }
  }

  Timer {
    id: statusTimer
    interval: root.statusIntervalMs
    repeat: true
    running: root.panelOpen && root.running
    triggeredOnStart: true
    onTriggered: root.refreshStatus()
  }

  Timer {
    id: positionTimer
    interval: 250
    repeat: true
    running: root.panelOpen && root.isPlaying
    onTriggered: root.positionSec = Math.min(root.lengthSec, root.positionSec + interval / 1000)
  }

  Connections {
    target: root.player
    ignoreUnknownSignals: true
    function onTrackChanged() { root.syncPosition() }
    function onPlaybackStateChanged() { root.syncPosition() }
    function onSeek() { root.syncPosition() }
  }

  onPanelOpenChanged: {
    if (!panelOpen) return
    syncPosition()
    readSinkRate()
    readSinkAvailability()
    readPlaylists()
  }

  // ---- PipeWire routing and the signal verdict ----

  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []

  property var sinkAvailability: ({})

  // Filtered through the stock helper the first-party audio panel uses, so an output
  // with nothing plugged into it is never offered as somewhere to send music.
  readonly property var sinks: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (!n || !n.isSink || n.isStream) continue
      var known = sinkAvailability[String(n.name || "")]
      if (known === false) continue
      list.push(n)
    }
    return list
  }

  function readSinkAvailability() {
    if (availabilityProcess.running) return
    availabilityProcess.running = true
  }

  Process {
    id: availabilityProcess
    command: ["omarchy-audio-sink-availability"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.sinkAvailability = Model.parseSinkAvailability(text)
    }
  }

  // cliamp reaches PipeWire through the ALSA compatibility layer, so its stream
  // announces itself as "PipeWire ALSA [cliamp]" rather than as a native client.
  readonly property var streamNode: {
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (!n || !n.isStream || !n.properties) continue
      if (String(n.properties["application.name"] || "").indexOf("cliamp") >= 0) return n
    }
    return null
  }

  readonly property var peakNode: streamNode

  // Read from the global link list rather than a PwNodeLinkTracker, which reports no
  // groups at all for this stream. Taken live rather than cached, so a sink that
  // disappears cannot leave a dead device name sitting in the panel.
  readonly property var currentSink: {
    if (!streamNode) return null
    var groups = Pipewire.linkGroups ? (Pipewire.linkGroups.values || []) : []
    for (var i = 0; i < groups.length; i++) {
      var g = groups[i]
      if (!g || !g.source || !g.target) continue
      if (g.source.id !== streamNode.id) continue
      // cliamp is also linked to quickshell itself for the peak meter, and that
      // tap is not a sink, so the isSink test is what keeps the route honest.
      if (g.target.isSink) return g.target
    }
    return null
  }


  readonly property string currentSinkLabel: currentSink
    ? String(currentSink.description || currentSink.nickname || currentSink.name || "")
    : ""

  readonly property int streamRate: streamNode ? Model.rateFromNodeProps(streamNode.properties) : 0
  property int sinkRate: 0

  readonly property string codec: codecFromPath(status.path)
  // A Subsonic URL is judged by whether cliamp asked for format=raw. A local file is
  // judged by its container, since nothing re-encoded it on the way in.
  readonly property bool transcoded: status.path.indexOf("/rest/stream") >= 0
    ? Model.transcodedFromPath(status.path)
    : (codec === "MP3" || codec === "OGG" || codec === "OPUS")
  // Any attenuation alters samples, so only an exact 0 dB counts. Setting volume over
  // MPRIS lands on -0.02 dB, which really is not unity and must not pass.
  readonly property bool unityGain: Math.abs(volumeDb) < 0.001
  readonly property bool eqFlat: status.eqFlat !== false

  // Empty for anything wired, so the lossy-link branch only fires on real Bluetooth.
  readonly property string lossyLink: currentSink
    ? Model.bluetoothCodecLabel(currentSink.properties)
    : ""

  readonly property var signalVerdict: Model.verdict({
    streamRate: streamRate,
    sinkRate: sinkRate,
    unityGain: unityGain,
    eqFlat: eqFlat,
    transcoded: transcoded,
    codec: codec,
    requestedRate: forcedRate,
    sourceRate: sourceRate,
    lossyLink: lossyLink
  })

  function codecFromPath(path) {
    var text = String(path || "")
    var cut = text.indexOf("?")
    if (cut >= 0) text = text.slice(0, cut)
    var dot = text.lastIndexOf(".")
    if (dot < 0) return ""
    var ext = text.slice(dot + 1).toUpperCase()
    if (ext === "MP3" || ext === "FLAC" || ext === "WAV" || ext === "ALAC"
      || ext === "OGG" || ext === "OPUS") return ext
    return ""
  }

  PwObjectTracker { objects: root.sinks }
  PwObjectTracker { objects: root.streamNode ? [root.streamNode] : [] }

  // The verdict is only ever derived from what the sink actually adopted, never from
  // the rate that was requested, because an unsupported rate silently lands on the
  // nearest one the DAC does support. No PipeWire property reports this.
  function readSinkRate() {
    if (sinkRateProcess.running) return
    sinkRateProcess.command = ["pactl", "list", "short", "sinks"]
    sinkRateProcess.running = true
  }

  Process {
    id: sinkRateProcess
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var wanted = root.currentSink ? String(root.currentSink.name || "") : ""
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          if (wanted.length > 0 && lines[i].indexOf(wanted) < 0) continue
          var rate = Model.sinkRateFromPactl(lines[i])
          if (rate > 0) { root.sinkRate = rate; return }
        }
        root.sinkRate = 0
      }
    }
  }

  // The graph takes a moment to settle after a forced rate, so the readback waits.
  Timer {
    id: rateSettleTimer
    interval: 2000
    repeat: false
    onTriggered: root.readSinkRate()
  }

  // ---- rate following ----

  readonly property bool followSourceRate: setting("followSourceRate", true) === true
  property int forcedRate: 0

  function matchRate() {
    if (streamRate <= 0 || rateProcess.running) return
    if (forcedRate === streamRate) return
    rateProcess.command = ["pw-metadata", "-n", "settings", "0", "clock.force-rate", String(streamRate)]
    rateProcess.running = true
    forcedRate = streamRate
    rateSettleTimer.restart()
  }

  function releaseRate() {
    if (forcedRate === 0 || rateProcess.running) return
    rateProcess.command = ["pw-metadata", "-n", "settings", "0", "clock.force-rate", "0"]
    rateProcess.running = true
    forcedRate = 0
    rateSettleTimer.restart()
  }

  Process { id: rateProcess; command: [] }

  // Following is deliberately scoped to actual playback: a forced rate reaches every
  // application on the box, so it is released the moment the music stops.
  onIsPlayingChanged: {
    if (!followSourceRate) return
    if (isPlaying) matchRate()
    else releaseRate()
  }

  // A sink change means the old rate reading describes a device no longer in the path,
  // and the switch can happen outside this panel, so the readback is not tied to a click.
  onCurrentSinkChanged: {
    if (followSourceRate && isPlaying) matchRate()
    rateSettleTimer.restart()
  }

  onStreamRateChanged: {
    if (followSourceRate && isPlaying) matchRate()
    else rateSettleTimer.restart()
  }

  Component.onDestruction: releaseRate()

  // ---- actions ----

  property var playlists: []

  function readPlaylists() {
    if (playlistProcess.running) return
    playlistProcess.command = [cliampPath, "playlist", "list"]
    playlistProcess.running = true
  }

  Process {
    id: playlistProcess
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.playlists = Model.parsePlaylists(text)
    }
  }

  // Loading a saved playlist is the only way a headless daemon can reach a Navidrome
  // library: the playlist keeps resolved stream URLs, and the browser is TUI only.
  function loadPlaylist(name) {
    if (actionProcess.running || !name) return
    actionProcess.command = [cliampPath, "load", String(name)]
    actionProcess.running = true
    playAfterLoad.restart()
  }

  Timer {
    id: playAfterLoad
    interval: 700
    repeat: false
    onTriggered: if (root.running) root.player.play()
  }

  function setDevice(name) {
    if (actionProcess.running || !name) return
    actionProcess.command = [cliampPath, "device", String(name)]
    actionProcess.running = true
  }

  function toggleShuffle() {
    if (actionProcess.running) return
    actionProcess.command = [cliampPath, "shuffle"]
    actionProcess.running = true
  }

  function cycleRepeat() {
    if (actionProcess.running) return
    actionProcess.command = [cliampPath, "repeat"]
    actionProcess.running = true
  }

  // cliamp cannot attach to a running instance, so the helper stops the daemon for
  // the life of the terminal session and starts it again afterwards. Without that,
  // opening the player spawns a second copy that the panel cannot see.
  property int sourceRate: 0

  readonly property bool followNativeRate: setting("followNativeRate", true) === true
  readonly property string nativeRateHelper: String(Qt.resolvedUrl("cliamp-daemon-rate-apply")).replace("file://", "")
  // The rate already asked for, so an output the hardware or cliamp refuses is not
  // requested again in a loop on every status poll.
  property int attemptedNativeRate: 0
  readonly property string sourceRateHelper: String(Qt.resolvedUrl("cliamp-source-rate")).replace("file://", "")

  // Resolved per track, because cliamp exposes no source rate of its own.
  function readSourceRate() {
    if (sourceRateProcess.running) return
    var path = String(status.path || "")
    if (path.length === 0) { sourceRate = 0; return }
    sourceRateProcess.command = [sourceRateHelper, path]
    sourceRateProcess.running = true
  }

  Process {
    id: sourceRateProcess
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var value = parseInt(String(text || "").trim(), 10)
        root.sourceRate = isFinite(value) && value > 0 ? value : 0
      }
    }
  }

  onStatusChanged: if (panelOpen) readSourceRate()

  // Relaunching cliamp is the only way to change its output rate, so this is gated
  // hard: only while the daemon itself is what is running, only when the file really
  // differs, and never twice for the same rate.
  onSourceRateChanged: considerNativeRate()

  function considerNativeRate() {
    if (!followNativeRate) return
    if (nativeRateProcess.running) return
    if (sourceRate <= 0 || streamRate <= 0) return
    if (Math.abs(sourceRate - streamRate) <= 1) { attemptedNativeRate = 0; return }
    if (attemptedNativeRate === sourceRate) return
    attemptedNativeRate = sourceRate
    nativeRateProcess.command = [nativeRateHelper, String(sourceRate)]
    nativeRateProcess.running = true
  }

  Process {
    id: nativeRateProcess
    command: []
    onExited: settleTimer.restart()
  }

  readonly property string sessionHelper: String(Qt.resolvedUrl("cliamp-session")).replace("file://", "")

  function openPlayer() {
    Quickshell.execDetached(["uwsm-app", "--", "foot", "--title=cliamp", sessionHelper])
  }

  Process {
    id: actionProcess
    command: []
    // A cliamp verb takes a moment to land, so the panel re-reads rather than guessing.
    onExited: settleTimer.restart()
  }

  Timer {
    id: settleTimer
    interval: 400
    repeat: false
    onTriggered: {
      root.refreshStatus()
      root.readSinkRate()
    }
  }
}
