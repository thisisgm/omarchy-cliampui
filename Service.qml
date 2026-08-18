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
  // Re-resolved on every player list change. A function call binding does not reliably
  // re-evaluate when the daemon restarts, which strands the panel on a dead object.
  property var player: null

  function refreshPlayer() { player = findCliampPlayer() }

  Connections {
    target: Mpris.players
    ignoreUnknownSignals: true
    function onValuesChanged() { root.refreshPlayer() }
  }

  Component.onCompleted: {
    refreshPlayer()
    rebuildNodes()
  }

  // cliamp's own status is the truth. MPRIS only fills gaps and provides seeking, so a
  // stale or missing player object can no longer freeze the panel.
  readonly property bool running: status.ok === true || player !== null
  readonly property bool hasTrack: running && (title.length > 0 || artist.length > 0)
  readonly property bool isPlaying: status.ok === true
    ? status.state === "playing"
    : (player !== null && player.isPlaying === true)
  readonly property string title: String(status.title || (player ? player.trackTitle : "") || "")
  readonly property string artist: String(status.artist || (player ? player.trackArtist : "") || "")
  readonly property string album: String(status.album || (player ? player.trackAlbum : "") || "")

  // cliamp publishes no mpris:artUrl for anything, local or remote, so the cover is
  // derived from the Subsonic stream URL it does publish. The MPRIS value is still
  // preferred in case a future release starts sending one.
  // Held rather than recomputed to empty. The cover is derived from the stream path, so
  // any moment without a status, between tracks or while the socket changes owner,
  // would otherwise blank the artwork and flash the placeholder.
  property string artUrl: ""
  property int artSizePx: 300

  readonly property string resolvedArtUrl: {
    if (!running) return ""
    var fromMpris = player ? safeArtUrl(player.trackArtUrl) : ""
    if (fromMpris.length > 0) return fromMpris
    return safeArtUrl(Model.coverArtUrlFromStreamPath(status.path, artSizePx))
  }

  // Held only across the gap where cliamp is unreachable, which is the socket dropping
  // on a daemon restart. While it is running an empty value is the honest answer, so
  // radio and local files clear the cover instead of showing the last album played.
  onResolvedArtUrlChanged: if (running) artUrl = resolvedArtUrl

  readonly property real lengthSec: {
    if (status.durationSec > 0) return status.durationSec
    if (player && player.lengthSupported) return Number(player.length || 0)
    return 0
  }

  // Measured on 1.63.2: seeking a Navidrome track stops playback outright, because these
  // arrive as HTTP streams and cliamp cannot reposition one. A duration is still known,
  // so the progress bar is drawn, but it must not be interactive.
  readonly property bool hasProgress: running && lengthSec > 0
  readonly property bool canSeek: hasProgress && !isStream

  readonly property bool shuffle: status.shuffle === true
  readonly property string repeat: String(status.repeat || "Off")
  readonly property int total: Number(status.total || 0)
  readonly property real volumeDb: Number(status.volumeDb || 0)
  readonly property bool isStream: status.isStream === true

  // Ticked locally between MPRIS updates, because polling Position over D-Bus four
  // times a second is traffic for something the panel can count on its own.
  property real positionSec: 0
  property bool _askedAtEnd: false

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

  // Held optimistically so the button flips on press instead of waiting for the poll,
  // then released as soon as cliamp reports the same thing.
  property int pendingPlaying: -1
  readonly property bool showPlaying: pendingPlaying === -1 ? isPlaying : pendingPlaying === 1

  function playPause() {
    pendingPlaying = isPlaying ? 0 : 1
    playHold.restart()
    if (send('{"cmd":"toggle"}')) { settleTimer.restart(); return }
    if (running) player.togglePlaying()
  }

  // Never let an optimistic flip stick if cliamp disagrees.
  Timer {
    id: playHold
    interval: 2500
    repeat: false
    onTriggered: root.pendingPlaying = -1
  }

  function next() {
    if (send('{"cmd":"next"}')) { settleTimer.restart(); return }
    if (running) player.next()
  }

  function previous() {
    if (send('{"cmd":"prev"}')) { settleTimer.restart(); return }
    if (running) player.previous()
  }

  // Measured on 1.63.2: the socket seek takes a delta, not a position, whatever
  // `cliamp seek --help` says. The delta comes off the interpolated position rather than
  // the last polled one, which is up to a whole poll interval stale. MPRIS is the fallback.
  function seekTo(targetSec) {
    if (!canSeek) return
    var target = Math.max(0, Math.min(lengthSec, Number(targetSec) || 0))
    var delta = Math.round(target - positionSec)
    positionSec = target
    if (send('{"cmd":"seek","value":' + delta + '}')) { settleTimer.restart(); return }
    if (player) player.seek(target - Number(player.position || 0))
  }

  function seekBy(deltaSec) { seekTo(positionSec + Number(deltaSec || 0)) }

  // cliamp speaks newline delimited JSON on its own socket, so status needs no
  // subprocess at all. One connection replaces a spawn every couple of seconds.
  readonly property string socketPath: (Quickshell.env("HOME") || "") + "/.config/cliamp/cliamp.sock"

  function refreshStatus() {
    if (!ipc.connected) return
    ipc.write('{"cmd":"status"}\n')
    ipc.flush()
  }

  // Every verb the docs define on the socket goes the same way.
  function send(payload) {
    if (!ipc.connected) return false
    ipc.write(payload + "\n")
    ipc.flush()
    return true
  }

  // cliamp resolves lyrics itself, from embedded tags then LRCLIB then NetEase, and
  // serves them on the same socket. Undocumented, measured: {"cmd":"lyrics"} answers
  // {"ok":true,"lyrics":[{"start":30.23,"text":"..."}]}.
  property var lyrics: []
  property string lyricsTrackPath: ""

  readonly property bool hasLyrics: lyrics.length > 0
  // cliamp reports the position it has decoded to. Over A2DP the ears are about a
  // sixth of a second behind that, which is plainly visible against lyrics, so the
  // line is chosen from the position that has actually reached the sink.
  property int outputLatencyMs: 0
  readonly property int lyricTrimMs: intSetting("lyricTrimMs", 0, -1000, 1000)
  readonly property string latencyHelper: String(Qt.resolvedUrl("cliamp-output-latency")).replace("file://", "")

  function readOutputLatency() {
    if (latencyProcess.running) return
    latencyProcess.command = [latencyHelper]
    latencyProcess.running = true
  }

  Process {
    id: latencyProcess
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.outputLatencyMs = Model.latencyMs(text)
    }
  }

  readonly property int activeLyricIndex: Model.activeLyricIndex(lyrics, positionSec - (outputLatencyMs + lyricTrimMs) / 1000)
  readonly property string activeLyric: activeLyricIndex >= 0
    ? String(lyrics[activeLyricIndex].text || "")
    : ""

  function refreshLyrics() {
    var path = String(status.path || "")
    if (path.length === 0) { lyrics = []; lyricsTrackPath = ""; return }
    if (path === lyricsTrackPath) return
    lyrics = []
    // Marked fetched only once the request is actually out, or one dropped write
    // suppresses every retry for the rest of the track.
    if (send('{"cmd":"lyrics"}')) lyricsTrackPath = path
  }

  function syncPosition() {
    if (status.ok === true) positionSec = Number(status.positionSec || 0)
    else if (player && player.positionSupported) positionSec = Number(player.position || 0)
    if (panelOpen) refreshStatus()
  }

  Socket {
    id: ipc
    path: root.socketPath
    connected: true

    // The socket changes owner whenever the daemon hands over to an interactive
    // session and back. Without an explicit reconnect the panel stays bound to the
    // instance that just exited and silently reports its last state forever, which
    // reads as the widget and the player disagreeing.
    onConnectionStateChanged: if (!connected) reconnectTimer.restart()

    parser: SplitParser {
      splitMarker: "\n"
      onRead: function (line) {
        var raw = String(line || "")
        var kind = Model.messageKind(raw)
        // Every command answers on this socket too, and an acknowledgement carries no
        // track, so parsing one as a status blanked the panel until the next poll.
        // refreshLyrics already empties the list, so a failed lyrics reply needs
        // nothing here.
        if (kind === "lyrics") { root.lyrics = Model.parseLyrics(raw); return }
        if (kind !== "status") return
        var parsed = Model.parseStatus(raw)
        root.status = parsed
        root.lastError = parsed.ok ? "" : parsed.lastError
        // The feed carries position, so the local tick only fills the gaps between polls.
        if (parsed.ok) root.positionSec = Number(parsed.positionSec || 0)
      }
    }
  }

  Timer {
    id: reconnectTimer
    interval: 700
    repeat: true
    running: !ipc.connected
    triggeredOnStart: true
    onTriggered: {
      if (ipc.connected) { running = false; return }
      ipc.connected = true
      root.refreshStatus()
    }
    onRunningChanged: {
      if (running) goneTimer.restart()
      else goneTimer.stop()
    }
  }

  // The socket drops briefly whenever the daemon restarts. Blanking the artwork and
  // title for that window is worse than briefly showing the last known track, so the
  // state is only cleared once cliamp has genuinely stayed away.
  Timer {
    id: goneTimer
    interval: 6000
    repeat: false
    onTriggered: {
      if (ipc.connected) return
      root.status = Model.defaultStatus()
      root.artUrl = ""
    }
  }

  // cliamp's own 10 band spectrum, the same feed its first-party widget draws. visstream
  // holds one IPC connection open and emits a frame per tick, which the docs give as the
  // way to consume it from a UI toolkit. It runs only while the popup is open and
  // playing, so a shut panel costs nothing.
  property var bands: []

  Process {
    id: visProcess
    command: [root.cliampPath, "visstream", "--fps", "20"]
    running: root.panelOpen && root.isPlaying
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function (line) {
        var frame = Model.parseBands(line)
        if (frame.length > 0) root.bands = frame
      }
    }
    onRunningChanged: if (!running) root.bands = []
  }

  Timer {
    id: statusTimer
    interval: root.statusIntervalMs
    repeat: true
    running: root.panelOpen && ipc.connected
    triggeredOnStart: true
    onTriggered: root.refreshStatus()
  }

  Timer {
    id: positionTimer
    interval: 250
    repeat: true
    running: root.panelOpen && root.isPlaying
    onTriggered: {
      var next = root.positionSec + interval / 1000
      // A repeat restarts the track without MPRIS reporting a track change, so the
      // position is asked for at the end rather than clamped and left stale. Asked
      // once, because a duration shorter than the audio would poll four times a
      // second for the rest of the track.
      if (root.lengthSec > 0 && next >= root.lengthSec) {
        if (!root._askedAtEnd) { root._askedAtEnd = true; root.refreshStatus() }
        return
      }
      root._askedAtEnd = false
      root.positionSec = next
    }
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
    readOutputLatency()
    readSinkAvailability()
    readPlaylists()
    readLibrary()
  }

  // ---- PipeWire routing and the signal verdict ----

  // Rebuilt from an explicit signal rather than left as a binding on values: a list
  // mutating in place does not re-evaluate the binding, so a device connected after
  // the panel loaded never appeared. Same hazard as the MPRIS player lookup.
  property var nodes: []

  function rebuildNodes() {
    nodes = Pipewire.nodes ? (Pipewire.nodes.values || []) : []
    readSinkAvailability()
  }

  Connections {
    target: Pipewire.nodes
    ignoreUnknownSignals: true
    function onValuesChanged() { root.rebuildNodes() }
  }

  property var sinkAvailability: ({})

  // Filtered through the stock helper the first-party audio panel uses, so an output
  // with nothing plugged into it is never offered as somewhere to send music.
  readonly property var sinks: {
    // Depends on nodes, which is now replaced wholesale on every change.
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
    && (!hasStreamVolume || (!streamMuted && Math.abs(streamVolume - 1) < 0.001))
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
    onTriggered: { root.readSinkRate(); root.readOutputLatency() }
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
  // One handler only: QML rejects a second onIsPlayingChanged and the whole component
  // then fails to load, which takes the widget out of the bar entirely.
  onIsPlayingChanged: {
    if (pendingPlaying !== -1 && isPlaying === (pendingPlaying === 1)) pendingPlaying = -1
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
  property var results: []
  property string libraryQuery: ""

  // Server rows on their own. Saved playlists are matched locally and merged in front,
  // so a playlist list arriving late does not need a second server round trip.
  property var _libraryRows: []

  readonly property string libraryHelper: String(Qt.resolvedUrl("cliamp-library")).replace("file://", "")

  function _recomputeResults() {
    results = Model.matchPlaylists(playlists, libraryQuery).concat(_libraryRows)
  }

  // The query this helper run was dispatched for, so a keystroke that arrives while
  // one is in flight is not silently dropped and does not leave stale rows on screen.
  property string _dispatchedQuery: ""

  // The library is browsed straight off the Subsonic server using the token cliamp
  // already published, so picking something never has to stop the daemon.
  function readLibrary() { _dispatchLibrary() }

  function search(query) {
    libraryQuery = String(query || "")
    _recomputeResults()
    _dispatchLibrary()
  }

  // One dispatcher, so a refresh cannot quietly replace an active search with the
  // full album list while the playlist rows are still filtered by the query.
  function _dispatchLibrary() {
    if (albumProcess.running) return
    _dispatchedQuery = libraryQuery
    albumProcess.command = libraryQuery.length > 0
      ? [libraryHelper, "search", libraryQuery]
      : [libraryHelper, "albums", "200"]
    albumProcess.running = true
  }

  function playResult(item) {
    if (!item) return
    if (item.kind === "playlist") { loadPlaylist(String(item.name)); return }
    if (albumPlayProcess.running || !item.id) return
    albumPlayProcess.command = [libraryHelper,
      item.kind === "song" ? "play-song" : "play", String(item.id)]
    albumPlayProcess.running = true
  }

  Process {
    id: albumProcess
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root._libraryRows = Model.parseResults(text)
        root._recomputeResults()
      }
    }
    onExited: if (root._dispatchedQuery !== root.libraryQuery) root._dispatchLibrary()
  }

  Process {
    id: albumPlayProcess
    command: []
    onExited: settleTimer.restart()
  }

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
      onStreamFinished: {
        root.playlists = Model.parsePlaylists(text)
        root._recomputeResults()
      }
    }
  }

  // Loading a saved playlist is the only way a headless daemon can reach a Navidrome
  // library: the playlist keeps resolved stream URLs, and the browser is TUI only.
  // Measured: load starts playing on its own, so nothing follows it here. The play that
  // used to be sent 700 ms later was the only delayed action in the plugin.
  function loadPlaylist(name) {
    if (!name) return
    if (send('{"cmd":"load","playlist":' + JSON.stringify(String(name)) + '}')) {
      settleTimer.restart()
      return
    }
    if (actionProcess.running) return
    actionProcess.command = [cliampPath, "load", String(name)]
    actionProcess.running = true
    settleTimer.restart()
  }

  // Volume is cliamp's PipeWire stream volume, moved exactly the way the stock audio
  // panel moves a sink: a property on a tracked node, pushed both ways, so a drag has
  // no subprocess and no poll behind it to fight. cliamp's own gain stays at unity.
  readonly property real streamVolume: streamNode && streamNode.audio ? streamNode.audio.volume : 0
  readonly property bool streamMuted: !!(streamNode && streamNode.audio && streamNode.audio.muted)
  readonly property bool hasStreamVolume: !!(streamNode && streamNode.audio)

  function setStreamVolume(value) {
    if (!streamNode || !streamNode.audio) return
    streamNode.audio.volume = Math.max(0, Math.min(1, Number(value) || 0))
  }

  function toggleMute() {
    if (!streamNode || !streamNode.audio) return
    streamNode.audio.muted = !streamNode.audio.muted
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

  readonly property bool followNativeRate: setting("followNativeRate", false) === true
  readonly property string nativeRateHelper: String(Qt.resolvedUrl("cliamp-daemon-rate-apply")).replace("file://", "")
  // The rate already asked for, so an output the hardware or cliamp refuses is not
  // requested again in a loop on every status poll.
  property int attemptedNativeRate: 0
  readonly property string sourceRateHelper: String(Qt.resolvedUrl("cliamp-source-rate")).replace("file://", "")

  // Resolved per track, because cliamp exposes no source rate of its own.
  property string sourceRateTrackPath: ""

  function readSourceRate() {
    if (sourceRateProcess.running) return
    var path = String(status.path || "")
    if (path.length === 0) { sourceRate = 0; sourceRateTrackPath = ""; return }
    // Status is reassigned on every poll, so without this the helper queried the
    // server every couple of seconds for a rate that only changes with the track.
    if (path === sourceRateTrackPath) return
    sourceRateTrackPath = path
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

  // One handler only. A second onStatusChanged in this object is "Property value set
  // multiple times", which fails the whole Service and removes the widget from the bar.
  onStatusChanged: {
    if (!panelOpen) return
    readSourceRate()
    refreshLyrics()
  }

  // Relaunching cliamp is the only way to change its output rate, so this is gated
  // hard: only while the daemon itself is what is running, only when the file really
  // differs, and never twice for the same rate.
  onSourceRateChanged: considerNativeRate()

  function considerNativeRate() {
    if (!followNativeRate) return
    if (nativeRateProcess.running) return
    if (sourceRate <= 0 || streamRate <= 0) return
    if (Math.abs(sourceRate - streamRate) <= 1) { attemptedNativeRate = 0; return }
    // 88.2 and 176.4 kHz are not accepted output rates, so relaunching would land on
    // the default and gap the audio for nothing.
    if (!Model.isSupportedOutputRate(sourceRate)) return
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

  // No socket handover any more. cliamp allows one instance per user, so this is only
  // ever offered when nothing owns the socket, and the in panel library removes the
  // reason to open a terminal player at all.
  function openPlayer() {
    if (running) return
    Quickshell.execDetached(["uwsm-app", "--", "foot", "--title=cliamp", cliampPath])
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
