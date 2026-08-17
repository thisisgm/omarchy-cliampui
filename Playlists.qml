import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// The only route to a Navidrome library without a terminal. cliamp's browser is TUI
// only, but a playlist saved from it keeps resolved stream URLs, so a headless daemon
// can play one. cliamp maintains "Recently Played" on its own, so there is always one.
Column {
  id: root

  property var service: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property bool expanded: false
  property int cursorIndex: -1

  signal toggleRequested()

  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property var items: service ? service.playlists : []

  spacing: Style.space(8)

  PanelSeparator {
    width: parent.width
    foreground: root.foreground
  }

  PanelSectionHeader {
    text: "LIBRARY"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  // Always present, because changing track means opening the player and a keybind
  // alone is not something anyone finds.
  CursorSurface {
    width: parent.width
    foreground: root.foreground
    implicitHeight: openLabel.implicitHeight + Style.spacing.rowPaddingX

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
        id: openLabel
        Layout.fillWidth: true
        text: "Open player"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        text: "f"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        text: "›"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }
  }

  CursorSurface {
    width: parent.width
    foreground: root.foreground
    visible: root.items.length > 0
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
        text: root.items.length + (root.items.length === 1 ? " playlist" : " playlists")
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
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
    spacing: Style.space(2)
    visible: root.expanded

    Repeater {
      model: root.items

      CursorSurface {
        width: root.width
        foreground: root.foreground
        hasCursor: index === root.cursorIndex
        implicitHeight: nameLabel.implicitHeight + Style.spacing.rowPaddingX

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.service.loadPlaylist(modelData.name)
        }

        RowLayout {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(10)
          anchors.rightMargin: Style.space(10)
          spacing: Style.space(8)

          Text {
            id: nameLabel
            Layout.fillWidth: true
            text: String(modelData.name || "")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Text {
            text: String(modelData.count || 0)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
