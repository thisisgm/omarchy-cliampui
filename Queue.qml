import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Live playlist. cliamp's status only reports a count; the rows come from
// {"cmd":"queue.list"}. Clicking a row jumps with queue.play, which 1.63.2
// does have on the socket even though MPRIS HasTrackList is false.
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

  readonly property bool editorFocused: saveField.activeFocus || addField.activeFocus
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property var tracks: service ? service.queueTracks : []
  readonly property var playlists: service ? service.savedPlaylists : []
  readonly property int trackCount: tracks.length
  readonly property int rowCount: trackCount + playlists.length
  readonly property int listMaxHeight: Style.space(240)
  readonly property int currentIndex: service ? Number(service.queueIndex) : -1

  readonly property var rows: {
    var out = []
    var list = root.tracks
    for (var i = 0; i < list.length; i++) {
      var t = list[i]
      out.push({
        kind: "track",
        index: i,
        label: Model.queueLabel(t),
        tag: "",
        removable: true
      })
    }
    var saved = root.playlists
    for (var j = 0; j < saved.length; j++) {
      var p = saved[j]
      out.push({
        kind: "playlist",
        index: j,
        label: p.name,
        tag: "PLAYLIST",
        removable: true
      })
    }
    return out
  }

  function focusSave() { saveField.forceActiveFocus() }
  function focusAdd() { addField.forceActiveFocus() }

  function activateRow(row) {
    if (!row || !root.service) return
    if (row.kind === "playlist") root.service.loadPlaylist(row.label)
    else root.service.playQueueIndex(row.index)
  }

  function removeRow(row) {
    if (!row || !root.service) return
    if (row.kind === "playlist") root.service.deletePlaylist(row.label)
    else root.service.removeQueueIndex(row.index)
  }

  onCursorIndexChanged: if (cursorIndex >= 0) queueList.positionViewAtIndex(cursorIndex, ListView.Contain)

  spacing: Style.space(8)

  PanelSeparator {
    width: parent.width
    foreground: root.foreground
  }

  Item {
    width: parent.width
    implicitHeight: Math.max(queueHeader.implicitHeight, queueCount.implicitHeight)

    PanelSectionHeader {
      id: queueHeader
      text: "QUEUE"
      foreground: root.foreground
      fontFamily: root.fontFamily
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: queueCount
      textFormat: Text.PlainText
      text: root.trackCount > 0
        ? root.trackCount + (root.trackCount === 1 ? " TRACK" : " TRACKS")
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
        text: {
          if (root.expanded) return "Now playing"
          if (root.trackCount <= 0) return "Nothing queued"
          var current = root.currentIndex >= 0 && root.currentIndex < root.tracks.length
            ? root.tracks[root.currentIndex]
            : root.tracks[0]
          return Model.queueLabel(current)
        }
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        textFormat: Text.PlainText
        text: "q"
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

    ListView {
      id: queueList
      width: parent.width
      height: Math.min(contentHeight, root.listMaxHeight)
      clip: true
      spacing: Style.space(2)
      model: root.rows
      keyNavigationEnabled: false
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
      visible: root.rowCount > 0

      onCountChanged: if (root.cursorIndex >= 0) positionViewAtIndex(root.cursorIndex, ListView.Contain)

      delegate: CursorSurface {
        required property var modelData
        required property int index

        width: queueList.width
        foreground: root.foreground
        hasCursor: index === root.cursorIndex
        implicitHeight: rowLabel.implicitHeight + Style.spacing.rowPaddingX
        readonly property bool isCurrent: modelData.kind === "track" && modelData.index === root.currentIndex
        readonly property string tagText: isCurrent ? "NOW" : String(modelData.tag || "")

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.activateRow(modelData)
        }

        RowLayout {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(10)
          anchors.rightMargin: Style.space(6)
          spacing: Style.space(8)

          Text {
            id: rowLabel
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: modelData.label
            color: isCurrent ? root.foreground : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Text {
            textFormat: Text.PlainText
            text: tagText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1.2
            visible: text.length > 0
          }

          PanelActionButton {
            iconText: "×"
            tooltipText: modelData.kind === "playlist" ? "Delete playlist" : "Remove from queue"
            foreground: root.foreground
            hoverColor: Color.urgent
            fontFamily: root.fontFamily
            visible: modelData.removable
            onClicked: root.removeRow(modelData)
          }
        }
      }
    }

    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: "Nothing queued"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      horizontalAlignment: Text.AlignHCenter
      visible: root.trackCount === 0
    }

    TextField {
      id: saveField
      width: parent.width
      placeholderText: "Save queue as…"
      foreground: root.foreground
      font.family: root.fontFamily
      Keys.onEscapePressed: root.focus = true
      onAccepted: {
        if (root.service) root.service.saveQueue(text)
        text = ""
        root.focus = true
      }
    }

    TextField {
      id: addField
      width: parent.width
      placeholderText: "Add a path or stream URL"
      foreground: root.foreground
      font.family: root.fontFamily
      Keys.onEscapePressed: root.focus = true
      onAccepted: {
        if (root.service) root.service.addUrl(text)
        text = ""
        root.focus = true
      }
    }

    CursorSurface {
      width: parent.width
      foreground: root.foreground
      implicitHeight: clearLabel.implicitHeight + Style.spacing.rowPaddingX
      visible: root.trackCount > 0

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          if (clearArmed.running) {
            clearArmed.stop()
            if (root.service) root.service.clearQueue()
            return
          }
          clearArmed.restart()
        }
      }

      RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        spacing: Style.space(8)

        Text {
          id: clearLabel
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: clearArmed.running ? "Confirm clear" : "Clear queue"
          color: clearArmed.running ? Color.urgent : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
      }

      Timer {
        id: clearArmed
        interval: 2500
        repeat: false
      }
    }
  }
}
