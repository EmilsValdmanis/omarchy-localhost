import QtQuick
import Quickshell
import "Plugin" as Plugin

// Hidden entry-point smoke test: no panels are opened on the user's desktop.
ShellRoot {
  Plugin.Widget { id: widget; settings: ({ includeDocker: false, showWhenEmpty: true }) }
  Plugin.QrOverlay { id: overlay }
  Timer {
    interval: 700
    running: true
    onTriggered: {
      console.log("LOCALHOST_WAYLAND_SMOKE", widget.moduleName, overlay.opened)
      Qt.quit()
    }
  }
}
