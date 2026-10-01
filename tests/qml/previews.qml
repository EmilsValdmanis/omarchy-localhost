import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Ui
import "Plugin/qml" as PluginUi
import "Plugin/qml/RadarModel.js" as RadarModel

ShellRoot {
  FloatingWindow {
    visible: true
    implicitWidth: 1600
    implicitHeight: 900
    color: Color.background

    TestCase {
      id: tests
      visible: true
      anchors.fill: parent
      name: "Previews"
      when: true
      property string output: Quickshell.env("LOCALHOST_PREVIEW_DIR")

      ListModel { id: servers }
      PluginUi.QrService { id: qr }

      component Copy: Text {
        textFormat: Text.PlainText
        color: Color.foreground
        font.family: "iA Writer Quattro S"
        font.italic: false
        font.weight: Font.Normal
        font.pixelSize: 24
      }

      Rectangle {
        id: poster
        width: 1600
        height: 900
        color: "#181d20"

        Image {
          id: wallpaper
          anchors.fill: parent
          source: Quickshell.env("LOCALHOST_PREVIEW_WALLPAPER")
          fillMode: Image.PreserveAspectCrop
          asynchronous: false
        }
        Rectangle {
          anchors.fill: parent
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "#b8181d20" }
            GradientStop { position: 1; color: "#70181d20" }
          }
        }

        FontMetrics { id: titleMetrics; font: title.font }
        Copy {
          id: title
          x: 108
          // Align the visible lettering, not the font's ascent box, with the panel.
          y: card.y - baselineOffset - titleMetrics.tightBoundingRect(text).y
          text: "Localhost"
          font.pixelSize: 84
          font.weight: Font.Bold
          font.letterSpacing: -3
        }
        Copy {
          x: 112; y: 220
          text: "for Omarchy"
          color: Color.accent
          font.pixelSize: 22
        }
        Copy {
          x: 112; y: 278
          text: "Your dev servers, in one place."
          color: "#c1c9bd"
          font.pixelSize: 25
        }

        Column {
          id: features
          x: 112; y: 337
          spacing: 8
          Repeater {
            model: [
              "Automatic framework & port detection",
              "Collapsible project & monorepo groups",
              "Docker & Compose discovery",
              "Compact RAM summary & server trends",
              "Open locally, share over LAN",
              "Quick search & keyboard navigation"
            ]
            Row {
              required property string modelData
              spacing: 17
              Copy { text: "•"; color: Color.accent; font.pixelSize: 21 }
              Copy { text: modelData; font.pixelSize: 21 }
            }
          }
        }

        Rectangle {
          id: qrCard
          x: 112
          y: Math.max(Math.round(card.y + card.height * card.scale - height),
            features.y + features.height + 42)
          width: 506; height: 209
          color: "#21272c"
          border.color: "#343f44"
          PluginUi.QrCode {
            id: qrCode
            x: 22 + Math.floor((165 - width) / 2)
            y: 22 + Math.floor((165 - height) / 2)
            rows: qr.qrRows
            moduleSize: qr.qrSize > 0 ? Math.max(1, Math.floor(165 / qr.qrSize)) : 1
          }
          Copy {
            x: 211; y: 53
            text: "Share to phone"
            font.pixelSize: 22
          }
          Copy {
            x: 211; y: 95
            text: "192.168.1.42:3000"
            font.family: "JetBrainsMono Nerd Font"
            color: Color.accent
            font.pixelSize: 15
          }
          Copy {
            x: 211; y: 136
            text: "Same Wi-Fi. One scan."
            color: "#9da9a0"
            font.pixelSize: 16
          }
        }

        BorderSurface {
          id: card
          x: 840; y: 62
          width: panel.implicitWidth + Style.spacing.popupPadding * 2
          height: panel.implicitHeight + Style.spacing.popupPadding * 2
          scale: 1.12
          transformOrigin: Item.TopLeft
          color: Color.popups.background
          radius: Style.cornerRadius
          borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, 2)
          PluginUi.ServerPanel {
            id: panel
            anchors.fill: parent
            anchors.margins: Style.spacing.popupPadding
            servers: servers
            systemMemory: ({ totalBytes: 16 * 1073741824, availableBytes: 2.7 * 1073741824 })
            lanIp: "192.168.1.42"
            scanSummary: "6 browser-ready servers"
          }
        }
      }

      function initTestCase() {
        // A fixed palette makes screenshots reproducible without changing the desktop theme.
        Color.foreground = "#d3c6aa"
        Color.background = "#2d353b"
        Color.accent = "#7fbbb3"
        Color.urgent = "#e67e80"
        Color.shellValues = ({ "popups.background": "#21272c", "popups.border": "#475258" })
        Style.fontBaseSize = 12
        Style.spacingScale = 1
        Style.fontFamily = "JetBrainsMono Nerd Font"
        Style.cornerRadius = 0
        Style.styleOverrides = ({})
        var demo = [
          ["@atlas/web", "Next.js", "next", 3000, "atlas", "apps/web", true],
          ["@atlas/docs", "Astro", "astro", 4321, "atlas", "apps/docs", true],
          ["@atlas/api", "FastAPI", "fastapi", 8000, "atlas", "services/api", true],
          ["@storefront/admin", "React", "react", 5173, "storefront", "apps/admin", false],
          ["@storefront/ui", "Storybook", "storybook", 6006, "storefront", "packages/ui", false],
          ["@storefront/api", "Hono", "hono", 8787, "storefront", "apps/api", true]
        ]
        var trends = [
          [0.80, 0.83, 0.81, 0.88, 0.91, 0.97, 0.95, 1],
          [1.15, 1.13, 1.11, 1.07, 1.08, 1.04, 1.02, 1],
          [0.98, 1.01, 0.99, 1.02, 1.01, 1.00, 1.01, 1],
          [0.76, 0.83, 0.80, 0.89, 0.94, 0.92, 0.98, 1],
          [0.96, 0.98, 1.01, 1.00, 0.98, 1.02, 1.01, 1],
          [1.10, 1.07, 1.08, 1.04, 1.03, 1.02, 1.01, 1]
        ]
        for (var i = 0; i < demo.length; i++) {
          var row = demo[i]
          servers.append(RadarModel.normalizeServer({
            serverId: "demo-" + i, name: row[0], framework: row[1], frameworkId: row[2],
            port: row[3], projectRoot: "/work/" + row[4], projectPath: row[5],
            memoryBytes: [445, 186, 92, 612, 205, 150][i] * 1048576,
            memoryHistory: trends[i].map(function(factor) {
              return Math.round([445, 186, 92, 612, 205, 150][i] * factor * 1048576)
            }),
            cwd: "/work/" + row[4] + "/" + row[5], lanAvailable: row[6],
            localUrl: "http://localhost:" + row[3], lanUrl: "http://192.168.1.42:" + row[3]
          }))
        }
        panel.rebuildFilteredModel()
        panel.revision++
        // A preview-only easter egg for anyone who scans the marketplace image.
        qr.open(JSON.stringify({ name: "Atlas / web", framework: "Next.js", url: "https://youtu.be/oHg5SJYRHA0" }))
        mouseMove(tests, 1590, 890)
        wait(300)
      }

      function test_preview() {
        tryCompare(wallpaper, "status", Image.Ready)
        compare(panel.resultCount, 6)
        compare(panel.projectCount, 2)
        tryVerify(function() { return qr.showingQr }, 5000)
        verify(card.x + card.width * card.scale <= poster.width - 60)
        verify(card.y + card.height * card.scale < 800)
        verify(qrCode.y + qrCode.height <= 210)
        if (features.y + features.height + 20 >= qrCard.y)
          console.error("Feature list overlaps QR card", features.height, qrCard.y)
        verify(features.y + features.height + 20 < qrCard.y)
        compare(title.y + title.baselineOffset + titleMetrics.tightBoundingRect(title.text).y, card.y)
        waitForRendering(poster)
        wait(100)
        var screenshot = grabImage(poster)
        compare(screenshot.width, 1600)
        compare(screenshot.height, 900)
        screenshot.save(output + "/preview.png")
      }

      function cleanupTestCase() { qr.close() }
      onCompletedChanged: if (completed) console.log("LOCALHOST_PREVIEWS " + JSON.stringify({ failed: qtest_results.failCount }))
    }
  }
}
