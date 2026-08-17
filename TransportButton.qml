import QtQuick
import QtQuick.Shapes

// The transport marks are drawn rather than typed. U+23EE, U+23ED and U+23F8 carry
// emoji presentation, so a font stack renders them as colour glyphs that ignore the
// theme entirely. Shuffle and repeat stay as text because their codepoints do not.
Item {
  id: root

  property string shape: ""
  property string glyph: ""
  property int size: 22
  property color color: "white"
  property bool enabled: true

  signal activated()

  readonly property real mark: size * 0.5
  readonly property real barWidth: Math.max(2, size * 0.11)
  readonly property real opacityNow: !enabled ? 0.35 : (mouse.containsMouse ? 1.0 : 0.85)

  implicitWidth: size
  implicitHeight: size

  Text {
    anchors.centerIn: parent
    visible: root.shape === ""
    text: root.glyph
    color: root.color
    font.pixelSize: root.size * 0.62
    opacity: root.opacityNow
    Behavior on opacity { NumberAnimation { duration: 90 } }
  }

  Row {
    anchors.centerIn: parent
    spacing: root.barWidth
    visible: root.shape === "pause"
    opacity: root.opacityNow

    Rectangle { width: root.barWidth; height: root.mark; radius: 1; color: root.color }
    Rectangle { width: root.barWidth; height: root.mark; radius: 1; color: root.color }
  }

  Item {
    anchors.centerIn: parent
    width: root.mark
    height: root.mark
    visible: root.shape === "play"
    opacity: root.opacityNow

    Triangle { size: root.mark; ink: root.color; pointsRight: true }
  }

  Row {
    anchors.centerIn: parent
    spacing: 0
    visible: root.shape === "prev"
    opacity: root.opacityNow

    Rectangle {
      width: root.barWidth
      height: root.mark
      radius: 1
      color: root.color
      anchors.verticalCenter: parent.verticalCenter
    }
    Triangle { size: root.mark; ink: root.color; pointsRight: false }
  }

  Row {
    anchors.centerIn: parent
    spacing: 0
    visible: root.shape === "next"
    opacity: root.opacityNow

    Triangle { size: root.mark; ink: root.color; pointsRight: true }
    Rectangle {
      width: root.barWidth
      height: root.mark
      radius: 1
      color: root.color
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    enabled: root.enabled
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }

  component Triangle: Shape {
    id: tri
    property real size: 10
    property color ink: "white"
    property bool pointsRight: true

    width: size
    height: size
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      fillColor: tri.ink
      strokeWidth: 0
      strokeColor: "transparent"
      startX: tri.pointsRight ? 0 : tri.size
      startY: 0
      PathLine { x: tri.pointsRight ? tri.size : 0; y: tri.size / 2 }
      PathLine { x: tri.pointsRight ? 0 : tri.size; y: tri.size }
      PathLine { x: tri.pointsRight ? 0 : tri.size; y: 0 }
    }
  }
}
