import QtQuick
import qs.Commons

// Drawn rather than shipped as an SVG: at bar size a three bar meter rasterises badly.
Item {
  id: root

  property real iconSize: 16
  property color color: Color.foreground

  implicitWidth: iconSize
  implicitHeight: iconSize

  // Bar heights as a fraction of the icon, so the mark reads as a level meter.
  readonly property var barFractions: [0.45, 0.95, 0.65]
  readonly property real barWidth: iconSize * 0.18
  readonly property real barGap: iconSize * 0.16

  Row {
    anchors.centerIn: parent
    spacing: root.barGap

    Repeater {
      model: root.barFractions

      Rectangle {
        width: root.barWidth
        height: root.iconSize * modelData
        radius: width / 2
        color: root.color
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }
}
