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
  // The primary action sits in a filled disc, the way current players mark it.
  property bool filled: false
  property color fillColor: "transparent"

  signal activated()

  readonly property real mark: size * (filled ? 0.40 : 0.5)
  readonly property real barWidth: Math.max(2, size * (filled ? 0.10 : 0.11))
  readonly property real opacityNow: !enabled ? 0.35 : (mouse.containsMouse ? 1.0 : 0.85)

  implicitWidth: size
  implicitHeight: size

  Rectangle {
    anchors.centerIn: parent
    width: root.size
    height: root.size
    radius: width / 2
    color: root.fillColor
    visible: root.filled
    opacity: !root.enabled ? 0.35 : (mouse.containsMouse ? 1.0 : 0.92)
    scale: mouse.pressed ? 0.94 : 1.0
    Behavior on scale { NumberAnimation { duration: 90 } }
    Behavior on opacity { NumberAnimation { duration: 90 } }
  }

  Text {
    textFormat: Text.PlainText
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

  Triangle {
    id: playMark
    anchors.centerIn: parent
    // A triangle carries its ink a third of the way from its base, so centering the
    // bounding box reads left heavy. This puts the painted centroid on the disc centre.
    anchors.horizontalCenterOffset: playMark.centroidOffset
    size: root.mark
    ink: root.color
    pointsRight: true
    visible: root.shape === "play"
    opacity: root.opacityNow
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
    // Slightly narrower than tall, which is how a play mark is normally drawn.
    readonly property real span: size * 0.88
    readonly property real centroidOffset: span / 6

    width: span
    height: size
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      fillColor: tri.ink
      strokeWidth: 0
      strokeColor: "transparent"
      startX: tri.pointsRight ? 0 : tri.span
      startY: 0
      PathLine { x: tri.pointsRight ? tri.span : 0; y: tri.size / 2 }
      PathLine { x: tri.pointsRight ? 0 : tri.span; y: tri.size }
      PathLine { x: tri.pointsRight ? 0 : tri.span; y: 0 }
    }
  }
}
