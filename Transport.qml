import QtQuick
import qs.Commons
import qs.Ui

Column {
  id: root

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
    spacing: Style.space(14)

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
      size: Style.space(30)
      enabled: root.live
      color: root.foreground
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
}
