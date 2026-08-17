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

  onResolvedArtUrlChanged: if (resolvedArtUrl.length > 0) artUrl = resolvedArtUrl

  readonly property real lengthSec: {
    if (status.durationSec > 0) return status.durationSec
    if (player && player.lengthSupported) return Number(player.length || 0)
    return 0
  }

  // Measured: seeking a Navidrome track skips to the next one rather than moving within
  // it, because these arrive as HTTP streams and cliamp cannot seek them. A duration is
  // still known, so the progress bar is drawn, but it must not be interactive.
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

  // The socket takes an absolute seek. MPRIS only offers a relative one, and computing
  // that delta from a locally interpolated position lands in the wrong place, which is
  // what made scrubbing feel broken. MPRIS stays as the fallback.
  function seekTo(targetSec) {
    if (!canSeek) return
    var target = Math.max(0, Math.min(lengthSec, Number(targetSec) || 0))
    positionSec = target
    if (send('{"cmd":"seek","value":' + Math.round(target) + '}')) { settleTimer.restart(); return }
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
        var parsed = Model.parseStatus(String(line || ""))
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
      if (running) { goneTimer.restart(); healTimer.restart() }
      else { goneTimer.stop(); healTimer.stop() }
    }
  }

  // The socket drops for about a second on every handover. Blanking the artwork and
  // title for that window is worse than briefly showing the last known track, so the
  // state is only cleared once cliamp has genuinely stayed away.
  property int reconnectAttempts: 0

  // A window manager kill can take the interactive cliamp with it and leave the unit
  // stopped, so nothing owns the socket and the music is simply gone. The panel is the
  // long lived thing here, so it is what puts the daemon back.
  Timer {
    id: healTimer
    interval: 4000
    repeat: false
    onTriggered: {
      if (ipc.connected) return
      healProcess.command = ["systemctl", "--user", "start", "cliamp-daemon.service"]
      healProcess.running = true
    }
  }

  Process { id: healProcess; command: [] }

  Timer {
    id: goneTimer
    interval: 6000
    repeat: false
    onTriggered: if (!ipc.connected) root.status = Model.defaultStatus()
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
    readAlbums()
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
  property var albums: []

  readonly property string libraryHelper: String(Qt.resolvedUrl("cliamp-library")).replace("file://", "")

  // The library is browsed straight off the Subsonic server using the token cliamp
  // already published, so picking an album never has to stop the daemon.
  function readAlbums() {
    if (albumProcess.running) return
    albumProcess.command = [libraryHelper, "albums", "200"]
    albumProcess.running = true
  }

  property string albumQuery: ""

  function searchAlbums(query) {
    albumQuery = String(query || "")
    if (albumProcess.running) return
    albumProcess.command = albumQuery.length > 0
      ? [libraryHelper, "search", albumQuery]
      : [libraryHelper, "albums", "200"]
    albumProcess.running = true
  }

  function playAlbum(id) {
    if (albumPlayProcess.running || !id) return
    albumPlayProcess.command = [libraryHelper, "play", String(id)]
    albumPlayProcess.running = true
  }

  Process {
    id: albumProcess
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.albums = Model.parseAlbums(text)
    }
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
      onStreamFinished: root.playlists = Model.parsePlaylists(text)
    }
  }

  // Loading a saved playlist is the only way a headless daemon can reach a Navidrome
  // library: the playlist keeps resolved stream URLs, and the browser is TUI only.
  function loadPlaylist(name) {
    if (!name) return
    if (send('{"cmd":"load","playlist":' + JSON.stringify(String(name)) + '}')) {
      playAfterLoad.restart()
      return
    }
    if (actionProcess.running) return
    actionProcess.command = [cliampPath, "load", String(name)]
    actionProcess.running = true
    playAfterLoad.restart()
  }

  Timer {
    id: playAfterLoad
    interval: 700
    repeat: false
    onTriggered: if (!root.send('{"cmd":"play"}') && root.running) root.player.play()
  }

  // cliamp's own range. 0 dB is the only value that leaves samples untouched, which is
  // why the slider marks it rather than treating it as just another position.
  readonly property real volumeMinDb: -30
  readonly property real volumeMaxDb: 6

  // Volume only arrives on the status poll, so the slider would snap back to a stale
  // value between polls while being dragged. The wanted value is held here and shown
  // until the poll agrees, the same optimistic trick the stock Dropbox panel uses.
  property real pendingVolumeDb: NaN
  readonly property real displayVolumeDb: isNaN(pendingVolumeDb) ? volumeDb : pendingVolumeDb

  function setVolume(db) {
    pendingVolumeDb = Math.max(volumeMinDb, Math.min(volumeMaxDb, Number(db) || 0))
    volumeSendTimer.restart()
  }

  // A drag emits a value per pixel, which would be one IPC write per pixel.
  Timer {
    id: volumeSendTimer
    interval: 60
    repeat: false
    onTriggered: {
      var value = root.pendingVolumeDb
      if (isNaN(value)) return
      if (root.send('{"cmd":"volume","value":' + value + '}')) { settleTimer.restart(); return }
      if (actionProcess.running) return
      actionProcess.command = [root.cliampPath, "volume", String(value)]
      actionProcess.running = true
    }
  }

  // Once cliamp reports the value back, the optimistic hold is released.
  onVolumeDbChanged: {
    if (isNaN(pendingVolumeDb)) return
    if (Math.abs(volumeDb - pendingVolumeDb) < 0.6) pendingVolumeDb = NaN
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
