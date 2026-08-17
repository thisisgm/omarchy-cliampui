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

  spacing: Style.space(6)

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
      shape: root.service && root.service.isPlaying ? "pause" : "play"
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
    anchors.horizontalCenter: parent.horizontalCenter
    // MPRIS reports HasTrackList false and the IPC has no queue read, so a count is
    // the most this panel can honestly say about what is coming next.
    text: root.service && root.service.total > 0 ? root.service.total + " in queue" : ""
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    visible: text.length > 0
  }

  // Built exactly as the stock audio panel builds its output volume: a section header
  // with the value right aligned on the same line, then the slider on its own full
  // width row inside an outlined CursorSurface.
  Item {
    width: parent.width
    implicitHeight: Math.max(volumeHeader.implicitHeight, volumeValue.implicitHeight)

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
      // liveValue while dragging, the bound value otherwise, as stock does it. dB is
      // kept rather than a percentage because 0 dB is the unity point the signal
      // verdict turns on, and a percentage would hide it.
      text: {
        if (!root.service) return ""
        var db = Math.round(volumeSlider.dragging ? volumeSlider.liveValue : root.service.volumeDb)
        return (db > 0 ? "+" : "") + db + " dB"
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

    PanelSlider {
      id: volumeSlider
      bar: root.bar
      anchors.fill: parent
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      minimum: root.service ? root.service.volumeMinDb : -30
      maximum: root.service ? root.service.volumeMaxDb : 6
      step: 1
      value: root.service ? root.service.volumeDb : 0
      enabled: root.live

      onMoved: function (v) { if (root.service) root.service.setVolume(v) }
      // Right click returns to unity, the only gain that keeps a route bit-perfect.
      onRightClicked: if (root.service) root.service.setVolume(0)
    }
  }
}
