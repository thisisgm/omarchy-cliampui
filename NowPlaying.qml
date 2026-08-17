import QtQuick
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Composed as a media hero rather than with PanelHero, which is built for status
// widgets and pins the artwork to a label-sized icon. Omarchy's tokens, colours and
// cursor surfaces still carry the styling.
Column {
  id: root

  property var service: null
  property string phrase: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property color sunken: Qt.darker(foreground, 4.2)
  readonly property int artSize: Style.space(112)
  readonly property int meterBars: 16
  readonly property real meterHeight: Style.space(14)
  readonly property bool hasTrack: !!(service && service.hasTrack)
  readonly property bool seekable: !!(service && service.canSeek)

  readonly property string metaLine: {
    if (!service) return ""
    var artist = String(service.artist || "")
    var album = String(service.album || "")
    if (artist.length > 0 && album.length > 0) return artist + " · " + album
    return artist.length > 0 ? artist : album
  }

  spacing: Style.space(12)

  Row {
    width: parent.width
    spacing: Style.space(14)

    Rectangle {
      width: root.artSize
      height: root.artSize
      radius: Style.space(8)
      color: root.sunken
      clip: true

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
        opacity: status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
      }

      CliampIcon {
        anchors.centerIn: parent
        iconSize: root.artSize * 0.34
        color: root.dim
        visible: art.status !== Image.Ready
      }
    }

    Column {
      width: parent.width - root.artSize - Style.space(14)
      spacing: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter

      Text {
        width: parent.width
        text: root.hasTrack ? root.service.title : "Cliamp"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
        elide: Text.ElideRight
      }

      // Styled exactly as PanelHero styles its meta line, so the hero reads as stock
      // even though the artwork is too large for PanelHero's icon slot.
      Text {
        width: parent.width
        text: (root.hasTrack ? root.metaLine : root.phrase).toUpperCase()
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.2
        elide: Text.ElideRight
      }

      // cliamp's own 10 band spectrum over IPC, drawn Winamp 2 style as stacked LED
      // segments with a falling peak cap. Fixed height, because a bare Row sizes to its
      // tallest child and every frame would then shove the whole panel up and down.
      Item {
        id: analyzer
        width: parent.width
        height: root.meterHeight
        visible: root.hasTrack

        readonly property var bands: root.service ? root.service.bands : []
        readonly property int segments: 7
        readonly property real segmentGap: 1

        Row {
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          height: parent.height
          spacing: 3

          Repeater {
            model: 10

            Item {
              id: bar
              width: 6
              height: analyzer.height

              readonly property real level: index < analyzer.bands.length ? analyzer.bands[index] : 0
              property real peak: 0

              // The cap hangs at the highest recent level and falls back under gravity,
              // which is what makes a Winamp analyzer read as one.
              onLevelChanged: if (level > peak) peak = level

              Timer {
                interval: 90
                repeat: true
                running: analyzer.visible
                onTriggered: bar.peak = Math.max(bar.level, bar.peak - 0.06)
              }

              Column {
                anchors.bottom: parent.bottom
                width: parent.width
                spacing: analyzer.segmentGap

                Repeater {
                  model: analyzer.segments

                  Rectangle {
                    width: bar.width
                    height: (analyzer.height - (analyzer.segments - 1) * analyzer.segmentGap) / analyzer.segments
                    radius: 1
                    // Segments light from the bottom up, so the column reads as a level.
                    readonly property real threshold: (analyzer.segments - index) / analyzer.segments
                    color: Color.accent
                    opacity: bar.level >= threshold ? 0.95 : 0.12
                    Behavior on opacity { NumberAnimation { duration: 70 } }
                  }
                }
              }

              Rectangle {
                width: bar.width
                height: 2
                radius: 1
                color: root.foreground
                opacity: bar.peak > 0.02 ? 0.9 : 0
                y: Math.max(0, analyzer.height - 2 - bar.peak * (analyzer.height - 2))
                Behavior on y { NumberAnimation { duration: 80 } }
              }
            }
          }
        }
      }
    }
  }

  Column {
    width: parent.width
    spacing: Style.space(6)
    visible: root.seekable

    Item {
      width: parent.width
      height: Style.space(4)

      Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.sunken
      }

      Rectangle {
        id: progress
        height: parent.height
        radius: height / 2
        color: Color.accent
        width: {
          if (!root.service || root.service.lengthSec <= 0) return 0
          return parent.width * Math.max(0, Math.min(1, root.service.positionSec / root.service.lengthSec))
        }
      }

      Rectangle {
        width: Style.space(10)
        height: width
        radius: width / 2
        color: Color.accent
        x: Math.max(0, Math.min(parent.width - width, progress.width - width / 2))
        anchors.verticalCenter: parent.verticalCenter
        opacity: scrubArea.containsMouse ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
      }

      MouseArea {
        id: scrubArea
        anchors.fill: parent
        anchors.topMargin: -Style.space(8)
        anchors.bottomMargin: -Style.space(8)
        hoverEnabled: true
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
  }

  PwObjectTracker { objects: root.service && root.service.peakNode ? [root.service.peakNode] : [] }

  PwNodePeakMonitor {
    id: peakMonitor
    node: root.service ? root.service.peakNode : null
    // Gated on playback so an idle panel does no level work, matching the stock audio panel.
    enabled: !!(root.service && root.service.isPlaying && root.service.peakNode)
  }
}
