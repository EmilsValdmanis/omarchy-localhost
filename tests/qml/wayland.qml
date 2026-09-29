import QtQuick
import Quickshell
import qs.Commons
import "Plugin" as Plugin

// Hidden entry-point smoke test: no panels are opened on the user's desktop.
ShellRoot {
  id: shell
  QtObject {
    id: themeBar
    property color barForeground: "#1f1f28"
    property color foreground: barForeground
    property color background: "#dcd7ba"
    property color urgent: "#c34043"
    property string fontFamily: "monospace"
    property int barSize: 28
    property bool vertical: false
    property bool foregroundAnimationEnabled: false
    property string position: "top"
  }
  Plugin.Widget {
    id: widget
    bar: themeBar
    settings: ({ includeDocker: false, showWhenEmpty: true })
  }
  Plugin.QrOverlay { id: overlay }

  function findItem(parent, name) {
    if (!parent) return null
    if (parent.objectName === name) return parent
    var children = parent.children || []
    for (var index = 0; index < children.length; index++) {
      var found = findItem(children[index], name)
      if (found) return found
    }
    return parent.item ? findItem(parent.item, name) : null
  }

  function findText(parent, value) {
    if (!parent) return null
    if (parent.text === value && parent.color !== undefined) return parent
    var children = parent.children || []
    for (var index = 0; index < children.length; index++) {
      var found = findText(children[index], value)
      if (found) return found
    }
    return parent.item ? findText(parent.item, value) : null
  }

  function sameColor(left, right) {
    return Math.abs(left.r - right.r) < 0.001
      && Math.abs(left.g - right.g) < 0.001
      && Math.abs(left.b - right.b) < 0.001
  }

  Timer {
    interval: 700
    running: true
    onTriggered: {
      var button = shell.findItem(widget, "localhostBarButton")
      var service = shell.findItem(widget, "localhostRadarService")
      var passed = button !== null && service !== null
      if (passed) {
        service.servers.clear()
        for (var index = 0; index < 12; index++)
          service.servers.append({ serverId: "theme-test-" + index })
        var expected = widget.glyph + " 12"
        var label = shell.findText(button, expected)
        passed = widget.serverCount === 12 && button.text === expected && label !== null

        // Kanagawa's pale accent can blend into a light wallpaper. The shared
        // label follows Omarchy's resolved dark or light bar foreground.
        Color.accent = "#dcd7ba"
        themeBar.barForeground = "#1f1f28"
        passed = passed && shell.sameColor(label.color, themeBar.barForeground)
        themeBar.barForeground = "#dcd7ba"
        passed = passed && shell.sameColor(label.color, themeBar.barForeground)

        widget.settings = ({ includeDocker: false, showWhenEmpty: true, showCountBadge: false })
        passed = passed && button.text === widget.glyph
        widget.settings = ({ includeDocker: false, showWhenEmpty: true, showCountBadge: true })
        themeBar.vertical = true
        var verticalGlyph = shell.findText(button, widget.glyph)
        var verticalCount = shell.findText(button, "12")
        passed = passed && button.text === "" && verticalGlyph !== null
          && verticalCount !== null
          && button.fixedHeight === 2 * Style.bar.iconSlot
          && shell.sameColor(verticalGlyph.color, themeBar.barForeground)
          && shell.sameColor(verticalCount.color, themeBar.barForeground)
      }
      console.log("LOCALHOST_BAR_LABEL", passed ? "PASS" : "FAIL")
      console.log("LOCALHOST_WAYLAND_SMOKE", widget.moduleName, overlay.opened)
      Qt.quit()
    }
  }
}
