import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// The library: every provider cliamp has configured, browsed through its v2 API, or on
// an older cliamp the Subsonic server reached with the token cliamp already published. Choosing an album replaces the queue in place, so the daemon never stops
// and the terminal player is never needed to change what is playing.
Column {
  id: root

  property var service: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property bool expanded: false
  property int cursorIndex: -1

  signal toggleRequested()
  signal moveRequested(int delta)
  signal activateRequested()

  // PanelKeyCatcher runs at Keys.BeforeItem, so the panel must stand down while this
  // field has the keyboard or every letter typed also fires a panel action.
  readonly property bool searchFocused: search.activeFocus

  onExpandedChanged: expanded ? search.forceActiveFocus() : root.forceActiveFocus()

  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property var results: service ? service.results : []
  readonly property int resultCount: service ? service.resultCount : 0
  readonly property bool cliampRunning: !!(service && service.running)

  // A search can return a hundred rows, which is taller than the whole panel. Capping
  // the list keeps the hero and transport on screen while browsing.
  readonly property int listMaxHeight: Style.space(240)

  // Keeps the cursor row on screen without ListView owning the cursor.
  onCursorIndexChanged: if (cursorIndex >= 0) albumList.positionViewAtIndex(cursorIndex, ListView.Contain)

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
      textFormat: Text.PlainText
      // Counts what can be played, so opening or closing a folder leaves it alone.
      text: root.resultCount > 0
        ? root.resultCount + (root.resultCount === 1 ? " RESULT" : " RESULTS")
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
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: root.expanded ? "Browse" : "Browse the library"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        textFormat: Text.PlainText
        text: "/"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        textFormat: Text.PlainText
        text: root.expanded ? "⌄" : "›"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }
  }

  Column {
    width: parent.width
    spacing: Style.space(8)
    visible: root.expanded

    // Each provider's own search, plus playlists and albums matched locally by name and
    // artist, so one field reaches everything that can be played.
    TextField {
      id: search
      width: parent.width
      placeholderText: "Search songs, albums and playlists"
      foreground: root.foreground
      font.family: root.fontFamily

      // The catcher is standing down, so these are the panel keys worth keeping here.
      Keys.onEscapePressed: root.focus = true
      Keys.onUpPressed: root.moveRequested(-1)
      Keys.onDownPressed: root.moveRequested(1)
      Keys.onReturnPressed: root.activateRequested()
      Keys.onEnterPressed: root.activateRequested()

      onTextChanged: searchDebounce.restart()
    }

    Timer {
      id: searchDebounce
      interval: 260
      repeat: false
      onTriggered: if (root.service) root.service.search(search.text)
    }

    // The list scrolls inside its own bounds, so the wheel over it moves rows rather
    // than the whole panel. ListView is used over a Repeater for positionViewAtIndex,
    // which is what keeps the j/k cursor on screen in a list this long.
    ListView {
      id: albumList
      width: parent.width
      height: Math.min(contentHeight, root.listMaxHeight)
      clip: true
      spacing: Style.space(2)
      model: root.results
      keyNavigationEnabled: false
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      // currentIndex is deliberately not bound to the panel's cursor. ListView writes
      // that property itself on every model swap, which breaks a QML binding for good
      // and would strand the highlight on row 0 while the panel still held its cursor.
      onCountChanged: if (root.cursorIndex >= 0) positionViewAtIndex(root.cursorIndex, ListView.Contain)

      delegate: CursorSurface {
        required property var modelData
        required property int index

        // A source folder: activating it opens or closes the rows beneath it.
        readonly property bool isSource: modelData.kind === "source"

        width: albumList.width
        foreground: root.foreground
        hasCursor: index === root.cursorIndex
        implicitHeight: albumLabel.implicitHeight + Style.spacing.rowPaddingX

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.service.playResult(modelData)
        }

        RowLayout {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          // Rows inside a folder sit in from it, so the folder reads as their parent.
          anchors.leftMargin: Style.space(modelData.inGroup ? 22 : 10)
          anchors.rightMargin: Style.space(10)
          spacing: Style.space(8)

          Text {
            id: albumLabel
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: isSource
              ? modelData.name
              : (modelData.artist ? modelData.artist + " · " : "") + modelData.name
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: isSource
            elide: Text.ElideRight
          }

          // The kind is the load-bearing detail once one list mixes three of them. Inside a
          // folder the source is already said above, so only the kind remains.
          Text {
            textFormat: Text.PlainText
            text: isSource
              ? String(modelData.songCount)
              : ((modelData.providerName && !modelData.inGroup ? modelData.providerName + " · " : "")
                + String(modelData.kind || "")).toUpperCase()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1.2
          }

          // Only a folder that can fold shows which way it is; a search heading cannot.
          Text {
            textFormat: Text.PlainText
            visible: isSource && modelData.collapsible === true
            text: modelData.expanded ? "⌄" : "›"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
        }
      }
    }

    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: "Nothing matched"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      horizontalAlignment: Text.AlignHCenter
      visible: root.results.length === 0
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
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: "Start cliamp"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        textFormat: Text.PlainText
        text: "f  ›"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
