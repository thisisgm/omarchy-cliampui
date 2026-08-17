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

  Item { width: 1; height: Style.space(2) }

  RowLayout {
    width: parent.width
    spacing: Style.space(8)

    Text {
      text: "VOLUME"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.2
    }

    PanelSlider {
      Layout.fillWidth: true
      bar: root.bar
      enabled: root.live
      minimum: root.service ? root.service.volumeMinDb : -30
      maximum: root.service ? root.service.volumeMaxDb : 6
      step: 1
      value: root.service ? root.service.volumeDb : 0
      onMoved: function (v) { if (root.service) root.service.setVolume(v) }
      // Right click returns to unity, the only gain that keeps a route bit-perfect.
      onRightClicked: if (root.service) root.service.setVolume(0)
    }

    Text {
      text: root.service ? (root.service.volumeDb > 0 ? "+" : "") + Math.round(root.service.volumeDb) + " dB" : ""
      color: root.service && root.service.unityGain ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
