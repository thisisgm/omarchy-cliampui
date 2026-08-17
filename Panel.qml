import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "github.thisisgm.cliampui"
  ipcTarget: "cliampui"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
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
          color: root.barForeground
        }
      }
    }
    onPressed: function (buttonCode) { root.toggle() }
  }
}
