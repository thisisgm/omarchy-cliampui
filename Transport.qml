import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Column {
  id: root

  property QtObject bar: null
  property var service: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property bool live: !!(service && service.running)
  readonly property bool shuffling: !!(service && service.shuffle)
  readonly property bool repeating: !!(service && service.repeat !== "Off")

  spacing: Style.space(8)

  Row {
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: Style.space(16)

    TransportButton {
      glyph: "⇄"
      size: Style.space(22)
      enabled: root.live
      color: root.shuffling ? root.foreground : root.dim
      onActivated: root.service.toggleShuffle()
    }

    TransportButton {
      shape: "prev"
      size: Style.space(22)
      enabled: root.live
      color: root.dim
      onActivated: root.service.previous()
    }

    TransportButton {
      shape: root.service && root.service.showPlaying ? "pause" : "play"
      size: Style.space(34)
      enabled: root.live
      filled: true
      fillColor: Color.accent
      // The glyph sits on the accent disc, so it takes the background colour to read.
      color: Color.background
      onActivated: root.service.playPause()
    }

    TransportButton {
      shape: "next"
      size: Style.space(22)
      enabled: root.live
      color: root.dim
      onActivated: root.service.next()
    }

    TransportButton {
      glyph: root.service && root.service.repeat === "One" ? "↻¹" : "↻"
      size: Style.space(22)
      enabled: root.live
      color: root.repeating ? root.foreground : root.dim
      onActivated: root.service.cycleRepeat()
    }
  }

  Text {
    textFormat: Text.PlainText
    anchors.horizontalCenter: parent.horizontalCenter
    // MPRIS reports HasTrackList false and the IPC has no queue read, so a count is
    // the most this panel can honestly say about what is coming next.
    text: root.service && root.service.total > 0 ? root.service.total + " in queue" : ""
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    visible: text.length > 0
  }

  // Built as the stock audio panel builds its output volume: a section header with the
  // value right aligned, then the slider on a full width row in an outlined surface.
  // Percent, not dB, because this is the PipeWire stream gain and not cliamp's own.
  Item {
    width: parent.width
    implicitHeight: Math.max(volumeHeader.implicitHeight, volumeValue.implicitHeight)
    visible: !!(root.service && root.service.hasStreamVolume)

    PanelSectionHeader {
      id: volumeHeader
      text: "VOLUME"
      foreground: root.foreground
      fontFamily: root.fontFamily
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: volumeValue
      textFormat: Text.PlainText
      text: {
        if (!root.service) return ""
        if (volumeSlider.dragging) return Math.round(volumeSlider.liveValue) + "%"
        if (root.service.streamMuted) return "MUTED"
        return Math.round(root.service.streamVolume * 100) + "%"
      }
      color: Qt.darker(root.foreground, 1.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  CursorSurface {
    width: parent.width
    height: volumeSlider.implicitHeight + Style.spacing.controlGap
    foreground: root.foreground
    outline: true
    visible: !!(root.service && root.service.hasStreamVolume)

    PanelSlider {
      id: volumeSlider
      bar: root.bar
      anchors.fill: parent
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      minimum: 0
      maximum: 100
      step: 1
      value: root.service ? root.service.streamVolume * 100 : 0
      enabled: root.live

      onMoved: function (v) { if (root.service) root.service.setStreamVolume(v / 100) }
      // Right click returns the stream to unity and clears mute, which is the state
      // the verdict counts as untouched. cliamp's own gain is expected to stay at 0 dB.
      onRightClicked: if (root.service) root.service.setStreamVolume(1)
    }
  }
}
