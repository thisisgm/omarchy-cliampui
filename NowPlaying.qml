import QtQuick
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui
import "Model.js" as Model

Column {
  id: root

  property var service: null
  property string phrase: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property color sunken: Qt.darker(foreground, 4.0)
  readonly property int meterBars: 14
  readonly property real meterHeight: Style.space(12)
  readonly property bool hasTrack: !!(service && service.hasTrack)
  readonly property bool seekable: !!(service && service.canSeek)

  readonly property string metaLine: {
    if (!service) return ""
    var artist = String(service.artist || "")
    var album = String(service.album || "")
    if (artist.length > 0 && album.length > 0) return artist + " · " + album
    return artist.length > 0 ? artist : album
  }

  spacing: Style.space(10)

  PanelHero {
    id: hero
    width: parent.width
    title: root.hasTrack ? root.service.title : "Cliamp"
    // Artist and album share the meta line. detail renders as a pill sized to its own
    // text, so a long album name there squeezes the title out of the row entirely.
    meta: root.hasTrack ? root.metaLine : root.phrase
    foreground: root.foreground
    fontFamily: root.fontFamily
    iconOpacity: root.hasTrack ? 1.0 : 0.5
    iconSize: Style.space(56)
    iconComponent: Component {
      Item {
        implicitWidth: hero.iconSize
        implicitHeight: hero.iconSize

        Rectangle {
          anchors.fill: parent
          radius: Style.space(4)
          color: root.sunken
          clip: true
          visible: art.status === Image.Ready

          Image {
            id: art
            anchors.fill: parent
            source: root.service ? root.service.artUrl : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            // Capped so a large cover is not decoded at full size for a small square.
            sourceSize.width: root.service ? root.service.artSizePx : 300
            sourceSize.height: root.service ? root.service.artSizePx : 300
          }
        }

        CliampIcon {
          anchors.centerIn: parent
          iconSize: hero.iconSize * 0.6
          color: root.hasTrack ? root.foreground : root.dim
          visible: art.status !== Image.Ready
        }
      }
    }
  }

  Row {
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: 2
    visible: peakMonitor.enabled

    Repeater {
      model: root.meterBars

      Rectangle {
        width: 3
        radius: 1.5
        color: root.foreground
        // Each bar leans on a slightly different slice of the level, so the row moves
        // as a meter rather than as one block rising and falling together.
        height: Math.max(2, root.meterHeight * Math.max(0, Math.min(1, peakMonitor.peak * (1.5 - index * 0.045))))
        anchors.bottom: parent.bottom
        Behavior on height { NumberAnimation { duration: 90 } }
      }
    }
  }

  Item {
    width: parent.width
    height: Style.space(4)
    visible: root.seekable

    Rectangle {
      anchors.fill: parent
      radius: height / 2
      color: root.sunken
    }

    Rectangle {
      height: parent.height
      radius: height / 2
      color: root.foreground
      width: {
        if (!root.service || root.service.lengthSec <= 0) return 0
        return parent.width * Math.max(0, Math.min(1, root.service.positionSec / root.service.lengthSec))
      }
    }

    MouseArea {
      anchors.fill: parent
      anchors.topMargin: -Style.space(7)
      anchors.bottomMargin: -Style.space(7)
      cursorShape: Qt.PointingHandCursor
      onClicked: function (mouse) {
        if (!root.service || root.service.lengthSec <= 0) return
        root.service.seekTo(root.service.lengthSec * (mouse.x / width))
      }
    }
  }

  Item {
    width: parent.width
    height: elapsed.implicitHeight
    visible: root.seekable

    Text {
      id: elapsed
      anchors.left: parent.left
      text: root.service ? Model.formatTime(root.service.positionSec) : "0:00"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Text {
      anchors.right: parent.right
      text: root.service ? Model.formatTime(root.service.lengthSec) : "0:00"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  PwObjectTracker { objects: root.service && root.service.peakNode ? [root.service.peakNode] : [] }

  PwNodePeakMonitor {
    id: peakMonitor
    node: root.service ? root.service.peakNode : null
    // Gated on playback so an idle panel does no level work, matching the stock audio panel.
    enabled: !!(root.service && root.service.isPlaying && root.service.peakNode)
  }
}
