import QtQuick
import qs.Commons

// Scrolls only when the text does not fit, so a short title sits still rather than
// drifting for no reason. Long album and track names are the norm in a music library,
// and eliding them means the one thing the panel exists to show cannot be read.
Item {
  id: root

  property string text: ""
  property color color: Color.foreground
  property string fontFamily: Style.font.family
  property int pixelSize: Style.font.body
  property bool bold: false
  property real letterSpacing: 0
  property bool active: true

  // Pixels per second, slow enough to read a long album title without chasing it.
  readonly property int scrollSpeed: 24
  readonly property int tailGap: Style.space(28)
  readonly property int holdMs: 1800
  readonly property bool overflowing: label.implicitWidth > width && width > 0

  implicitHeight: label.implicitHeight
  clip: true

  // Titles and artists come from the server, so markup in one must never render as rich text.
  Row {
    id: strip
    spacing: root.tailGap
    x: 0

    Text {
      id: label
      textFormat: Text.PlainText
      text: root.text
      color: root.color
      font.family: root.fontFamily
      font.pixelSize: root.pixelSize
      font.bold: root.bold
      font.letterSpacing: root.letterSpacing
    }

    Text {
      textFormat: Text.PlainText
      text: root.text
      color: root.color
      font.family: root.fontFamily
      font.pixelSize: root.pixelSize
      font.bold: root.bold
      font.letterSpacing: root.letterSpacing
      visible: root.overflowing
    }
  }

  SequentialAnimation {
    id: scroll
    running: root.overflowing && root.active && root.visible
    loops: Animation.Infinite

    PauseAnimation { duration: root.holdMs }
    NumberAnimation {
      target: strip
      property: "x"
      from: 0
      to: -(label.implicitWidth + root.tailGap)
      duration: Math.max(1, (label.implicitWidth + root.tailGap) / root.scrollSpeed * 1000)
    }
    PauseAnimation { duration: 250 }
  }

  // A new track must not inherit the previous title's scroll offset.
  onTextChanged: {
    strip.x = 0
    if (scroll.running) scroll.restart()
  }
}
