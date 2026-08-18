import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "github.thisisgm.cliampui"
  ipcTarget: "cliampui"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool hideWhenStopped: setting("hideWhenStopped", true) === true
  readonly property color barIconColor: cliamp.isPlaying
    ? root.barForeground
    : Qt.darker(root.barForeground, 1.55)

  readonly property real seekStepSec: 5

  property bool sheetOpen: false
  property bool libraryOpen: false
  property int phraseIndex: 0
  // Cursor rows only exist while the output sheet is open, so the arrows never land
  // on a control that is not currently on screen.
  property int cursorIndex: 0

  readonly property int phraseIntervalMs: 2800

  // Ten, matching the stock panels.
  readonly property var activePhrases: [
    "Bits arriving intact",
    "Straight off your own shelf",
    "No middleman on this signal",
    "Clock locked to source",
    "Spinning up the platter",
    "Needle in the groove",
    "Nothing resampled here",
    "Self-hosted and loud",
    "Signal path is short",
    "Whipping the terminal"
  ]
  readonly property string heroPhraseText: activePhrases[phraseIndex % activePhrases.length]

  // Leaves the bar entirely when there is nothing to say, rather than sitting empty.
  visible: cliamp.running || !hideWhenStopped
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function moveCursor(delta) {
    var count = libraryOpen ? cliamp.results.length : cliamp.sinks.length
    if (count === 0) return
    cursorIndex = (cursorIndex + delta + count) % count
  }

  function activateCursor() {
    var list = libraryOpen ? cliamp.results : cliamp.sinks
    if (cursorIndex < 0 || cursorIndex >= list.length) return
    if (libraryOpen) cliamp.playResult(list[cursorIndex])
    else cliamp.setDevice(String(list[cursorIndex].name || ""))
  }

  Service {
    id: cliamp
    settings: root.settings
    panelOpen: root.opened
  }

  Timer {
    id: phraseTimer
    interval: root.phraseIntervalMs
    repeat: true
    running: root.opened && !cliamp.hasTrack
    onTriggered: root.phraseIndex = (root.phraseIndex + 1) % root.activePhrases.length
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function playpause(): string { cliamp.playPause(); return "ok" }
    function signal(): string { return cliamp.signalVerdict.text }
    function output(): string {
      root.sheetOpen = !root.sheetOpen
      root.libraryOpen = false
      root.cursorIndex = 0
      return root.sheetOpen ? "open" : "closed"
    }
    function library(): string {
      root.libraryOpen = !root.libraryOpen
      root.sheetOpen = false
      root.cursorIndex = 0
      return root.libraryOpen ? "open" : "closed"
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        CliampIcon {
          anchors.centerIn: parent
          iconSize: Style.space(12)
          color: root.barIconColor
        }
      }
    }
    onPressed: function (buttonCode) {
      if (buttonCode === Qt.RightButton) cliamp.playPause()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function (dx, dy) {
        if ((root.sheetOpen || root.libraryOpen) && dy !== 0) { root.moveCursor(dy); return }
        if (dx !== 0) cliamp.seekBy(dx > 0 ? root.seekStepSec : -root.seekStepSec)
      }
      onActivateRequested: {
        if (root.sheetOpen || root.libraryOpen) root.activateCursor()
        else cliamp.playPause()
      }
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onTextKey: function (t) {
        var key = String(t).toLowerCase()
        if (key === "o") { root.sheetOpen = !root.sheetOpen; root.libraryOpen = false; root.cursorIndex = 0 }
        else if (key === "l") { root.libraryOpen = !root.libraryOpen; root.sheetOpen = false; root.cursorIndex = 0 }
        else if (key === "f") cliamp.openPlayer()
        else if (!cliamp.running) return
        else if (key === "n") cliamp.next()
        else if (key === "b") cliamp.previous()
        else if (key === "s") cliamp.toggleShuffle()
        else if (key === "r") cliamp.cycleRepeat()
        else if (key === "p") cliamp.followSourceRate ? cliamp.releaseRate() : cliamp.matchRate()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        // Indicator only: an interactive bar lays a hit strip over content the
        // keyboard already reaches, and the library list scrolls itself.
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; interactive: false }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          NowPlaying {
            width: parent.width
            service: cliamp
            phrase: root.heroPhraseText
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Transport {
            width: parent.width
            bar: root.bar
            service: cliamp
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Library {
            width: parent.width
            service: cliamp
            foreground: root.foreground
            fontFamily: root.fontFamily
            expanded: root.libraryOpen
            cursorIndex: root.libraryOpen ? root.cursorIndex : -1
            onToggleRequested: { root.libraryOpen = !root.libraryOpen; root.sheetOpen = false; root.cursorIndex = 0 }
          }

          OutputSheet {
            width: parent.width
            service: cliamp
            foreground: root.foreground
            fontFamily: root.fontFamily
            expanded: root.sheetOpen
            cursorIndex: root.sheetOpen ? root.cursorIndex : -1
            onToggleRequested: { root.sheetOpen = !root.sheetOpen; root.libraryOpen = false; root.cursorIndex = 0 }
          }
        }
      }
    }
  }

  onOpenedChanged: {
    if (!opened) { sheetOpen = false; libraryOpen = false; return }
    if (panelFlick) panelFlick.contentY = 0
    cursorIndex = 0
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }
}
