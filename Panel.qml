import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "github.thisisgm.cliampui"
  ipcTarget: "cliampui"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property bool hideWhenStopped: setting("hideWhenStopped", true) === true
  readonly property color barIconColor: cliamp.isPlaying
    ? root.barForeground
    : Qt.darker(root.barForeground, 1.55)

  // Leaves the bar entirely when there is nothing to say, rather than sitting empty.
  visible: cliamp.running || !hideWhenStopped
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Service {
    id: cliamp
    settings: root.settings
    panelOpen: root.opened
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function playpause(): string { cliamp.playPause(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        CliampIcon {
          anchors.centerIn: parent
          iconSize: Style.space(12)
          color: root.barIconColor
        }
      }
    }
    onPressed: function (buttonCode) {
      if (buttonCode === Qt.RightButton) cliamp.playPause()
      else root.toggle()
    }
  }
}
