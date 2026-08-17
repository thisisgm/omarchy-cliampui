import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Lyrics as cliamp already resolves them, served on the socket the panel is holding
// open. Nothing is fetched here, so a track with none simply has no section.
Column {
  id: root

  property var service: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property bool expanded: false

  signal toggleRequested()

  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property var lines: service ? service.lyrics : []
  readonly property int activeIndex: service ? service.activeLyricIndex : -1

  // Tall enough to read a verse, short enough to leave the hero and transport on screen.
  readonly property int listMaxHeight: Style.space(200)

  // A track with no lyrics says nothing at all rather than offering an empty section.
  visible: lines.length > 0

  spacing: Style.space(8)

  PanelSeparator {
    width: parent.width
    foreground: root.foreground
  }

  Item {
    width: parent.width
    implicitHeight: Math.max(lyricsHeader.implicitHeight, countLabel.implicitHeight)

    PanelSectionHeader {
      id: lyricsHeader
      text: "LYRICS"
      foreground: root.foreground
      fontFamily: root.fontFamily
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: countLabel
      text: root.lines.length + " LINES"
      color: Qt.darker(root.foreground, 1.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.2
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  CursorSurface {
    width: parent.width
    foreground: root.foreground
    implicitHeight: summaryLabel.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.toggleRequested()
    }

    Row {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        id: summaryLabel
        width: parent.width - keyHint.width - chevron.width - Style.space(16)
        // Collapsed, the section is still worth having: the line being sung right now
        // is the one thing a bar widget can show without taking any more room.
        text: {
          if (root.expanded) return "Lyrics"
          if (root.activeIndex < 0) return "Lyrics"
          return String(root.lines[root.activeIndex].text || "")
        }
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        id: keyHint
        text: "y"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        id: chevron
        text: root.expanded ? "⌄" : "›"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }
  }

  // Follows playback rather than a cursor, so the list is not interactive: the active
  // line is kept in view and everything else scrolls past it.
  ListView {
    id: lyricList
    width: parent.width
    height: Math.min(contentHeight, root.listMaxHeight)
    visible: root.expanded
    clip: true
    spacing: Style.space(2)
    model: root.lines
    currentIndex: root.activeIndex
    keyNavigationEnabled: false
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Center)

    delegate: Text {
      required property var modelData
      required property int index

      width: lyricList.width - Style.space(20)
      x: Style.space(10)
      text: String(modelData.text || "")
      color: index === root.activeIndex ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: index === root.activeIndex
      wrapMode: Text.WordWrap
    }
  }
}
