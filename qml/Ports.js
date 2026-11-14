var MAX_RANGE_SPAN = 4096

var COMMON_DEV_PORTS = {
  3000: true, 3001: true, 4000: true, 4173: true, 4200: true,
  4321: true, 5000: true, 5173: true, 5174: true, 8000: true,
  8001: true, 8080: true, 8787: true
}

function isCommonDevPort(port) {
  return COMMON_DEV_PORTS[Number(port)] === true
}

function parsePortSet(specification) {
  var ports = {}
  var sections = String(specification || "").split(",")
  for (var index = 0; index < sections.length; index++) {
    var token = sections[index].trim()
    if (!token) continue
    var match = token.match(/^(\d+)(?:\s*[-:]\s*(\d+))?$/)
    if (!match) continue
    var first = Number(match[1])
    var last = match[2] ? Number(match[2]) : first
    if (first > last) { var swap = first; first = last; last = swap }
    if (first < 1 || last > 65535 || last - first > MAX_RANGE_SPAN) continue
    for (var port = first; port <= last; port++) ports[port] = true
  }
  return ports
}

function formatPortSet(ports) {
  var values = Object.keys(ports).filter(function(port) { return ports[port] }).map(Number).sort(function(a, b) { return a - b })
  var sections = []
  for (var i = 0; i < values.length; i++) {
    var first = values[i]
    var last = first
    while (i + 1 < values.length && values[i + 1] === last + 1 && last - first < MAX_RANGE_SPAN) last = values[++i]
    sections.push(first === last ? String(first) : first + "-" + last)
  }
  return sections.join(",")
}

function portPreferenceSettings(settings, port, include) {
  port = Number(port)
  if (!Number.isInteger(port) || port < 1 || port > 65535) return null
  var next = Object.assign({}, settings || {})
  var ignored = parsePortSet(next.ignoredPorts)
  var included = parsePortSet(next.alwaysIncludePorts)
  if (include) { delete ignored[port]; included[port] = true }
  else { ignored[port] = true; delete included[port] }
  next.ignoredPorts = formatPortSet(ignored)
  next.alwaysIncludePorts = formatPortSet(included)
  return next
}
