import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// The library, browsed straight off the Subsonic server with the token cliamp already
// published. Choosing an album replaces the queue in place, so the daemon never stops
// and the terminal player is never needed to change what is playing.
Column {
  id: root

  property var service: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property bool expanded: false
  property int cursorIndex: -1

  signal toggleRequested()

  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property var albums: service ? service.albums : []
  readonly property bool cliampRunning: !!(service && service.running)

  // A search can return a hundred albums, which is taller than the whole panel. Capping
  // the list keeps the hero and transport on screen while browsing.
  readonly property int listMaxHeight: Style.space(240)

  spacing: Style.space(8)

  PanelSeparator {
    width: parent.width
    foreground: root.foreground
  }

  Item {
    width: parent.width
    implicitHeight: Math.max(libraryHeader.implicitHeight, countLabel.implicitHeight)

    PanelSectionHeader {
      id: libraryHeader
      text: "LIBRARY"
      foreground: root.foreground
      fontFamily: root.fontFamily
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: countLabel
      text: root.albums.length > 0
        ? root.albums.length + (root.albums.length === 1 ? " ALBUM" : " ALBUMS")
        : ""
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

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        id: summaryLabel
        Layout.fillWidth: true
        text: root.expanded ? "Browse" : "Browse albums"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        text: "l"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        text: root.expanded ? "⌄" : "›"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }
  }

  Column {
    width: parent.width
    spacing: Style.space(6)
    visible: root.expanded

    // search3 matches album and artist names, so one field browses by either.
    TextField {
      id: search
      width: parent.width
      placeholderText: "Search albums and artists"
      foreground: root.foreground
      font.family: root.fontFamily

      onTextChanged: searchDebounce.restart()
    }

    Timer {
      id: searchDebounce
      interval: 260
      repeat: false
      onTriggered: if (root.service) root.service.searchAlbums(search.text)
    }

    // The list scrolls inside its own bounds, so the wheel over it moves albums rather
    // than the whole panel. ListView is used over a Repeater because currentIndex plus
    // positionViewAtIndex is what keeps the j/k cursor on screen in a list this long.
    ListView {
      id: albumList
      width: parent.width
      height: Math.min(contentHeight, root.listMaxHeight)
      clip: true
      spacing: Style.space(2)
      model: root.albums
      currentIndex: root.cursorIndex
      keyNavigationEnabled: false
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

      delegate: CursorSurface {
        required property var modelData
        required property int index

        width: albumList.width
        foreground: root.foreground
        hasCursor: ListView.isCurrentItem
        implicitHeight: albumLabel.implicitHeight + Style.spacing.rowPaddingX

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.service.playAlbum(modelData.id)
        }

        RowLayout {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(10)
          anchors.rightMargin: Style.space(10)
          spacing: Style.space(8)

          Text {
            id: albumLabel
            Layout.fillWidth: true
            text: (modelData.artist ? modelData.artist + " · " : "") + modelData.name
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Text {
            text: String(modelData.songCount || "")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }

    Text {
      width: parent.width
      text: "Nothing matched"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      horizontalAlignment: Text.AlignHCenter
      visible: root.albums.length === 0
    }
  }

  // Only offered when nothing holds the socket. cliamp allows one instance per user, so
  // launching it while the daemon runs would start a second, IPC-less copy that this
  // panel cannot see. Browsing above removes the reason to open it at all.
  CursorSurface {
    width: parent.width
    foreground: root.foreground
    visible: !root.cliampRunning
    implicitHeight: startLabel.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.service.openPlayer()
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        id: startLabel
        Layout.fillWidth: true
        text: "Start cliamp"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        text: "f  ›"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
