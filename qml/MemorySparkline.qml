import QtQuick
import qs.Commons

Canvas {
  id: root
  objectName: "memorySparkline"
  property var samples: []
  property color lineColor: Color.accent

  implicitWidth: Style.space(48)
  implicitHeight: Style.space(20)
  antialiasing: true
  onSamplesChanged: requestPaint()
  onLineColorChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  onPaint: {
    var context = getContext("2d")
    context.clearRect(0, 0, width, height)
    if (!samples || !samples.length || width < 4 || height < 4) return

    var low = Math.min.apply(null, samples)
    var high = Math.max.apply(null, samples)
    var span = high - low
    var inset = 3
    context.beginPath()
    for (var index = 0; index < samples.length; index++) {
      var x = inset + index * (width - inset * 2) / Math.max(1, samples.length - 1)
      var y = span ? height - inset - (samples[index] - low) / span * (height - inset * 2)
        : height / 2
      if (index === 0) context.moveTo(x, y)
      else context.lineTo(x, y)
    }
    context.strokeStyle = String(lineColor)
    context.lineWidth = 1.5
    context.stroke()

    var lastY = span ? height - inset - (samples[samples.length - 1] - low) / span
      * (height - inset * 2) : height / 2
    context.beginPath()
    context.arc(width - inset, lastY, 2, 0, Math.PI * 2)
    context.fillStyle = String(lineColor)
    context.fill()
  }
}
