import QtQuick

// A single texture, repainted only when the matrix or integer module size changes.
Canvas {
  id: root
  property var rows: []
  property int moduleSize: 1

  implicitWidth: rows.length * moduleSize
  implicitHeight: implicitWidth
  antialiasing: false
  smooth: false
  onRowsChanged: requestPaint()
  onModuleSizeChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.fillStyle = "white"
    ctx.fillRect(0, 0, width, height)
    ctx.fillStyle = "black"
    for (var y = 0; y < rows.length; y++) {
      var line = rows[y]
      for (var x = 0; x < line.length; x++) {
        if (line.charAt(x) !== "1") continue
        var start = x
        while (x + 1 < line.length && line.charAt(x + 1) === "1") x++
        ctx.fillRect(start * moduleSize, y * moduleSize,
          (x - start + 1) * moduleSize, moduleSize)
      }
    }
  }
}
