import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
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
  readonly property string artist: running ? String(player.trackArtist || "") : ""
  readonly property string album: running ? String(player.trackAlbum || "") : ""
  readonly property string artUrl: running ? safeArtUrl(player.trackArtUrl) : ""
  readonly property real lengthSec: running && player.lengthSupported ? Number(player.length || 0) : 0
  readonly property bool canSeek: running && player.canSeek === true && !isStream

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

  onPanelOpenChanged: if (panelOpen) syncPosition()
}
