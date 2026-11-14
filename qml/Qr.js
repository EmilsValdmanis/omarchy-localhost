function parseQrAscii(raw) {
  var lines = String(raw || "").replace(/\r/g, "").split("\n")
  while (lines.length && lines[lines.length - 1] === "") lines.pop()
  if (!lines.length) return { size: 0, rows: [] }

  var rows = []
  for (var rowIndex = 0; rowIndex < lines.length; rowIndex++) {
    var line = lines[rowIndex]
    var row = ""
    for (var column = 0; column < line.length; column += 2)
      row += line.slice(column, column + 2).indexOf("#") !== -1 ? "1" : "0"
    rows.push(row)
  }
  var size = rows.length
  for (var index = 0; index < rows.length; index++)
    if (rows[index].length !== size || !/^[01]+$/.test(rows[index])) return { size: 0, rows: [] }
  return { size: size, rows: rows }
}
