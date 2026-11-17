function colorOffset(key) {
  var hash = 2166136261
  var value = String(key || "")
  for (var i = 0; i < value.length; i++) hash = Math.imul(hash ^ value.charCodeAt(i), 16777619) >>> 0
  return (hash % 360) / 360
}

function key(row) {
  return row.source === "docker"
    ? (row.containerId ? "docker:" + row.containerId : "server:" + row.serverId)
    : (row.pid > 0 && row.startTime > 0
      ? "process:" + row.pid + ":" + row.startTime : "server:" + row.serverId)
}

function belongsTo(key, source) {
  return key.indexOf(source + ":") === 0
}

function savedServices(value) {
  var rules = Object.create(null)
  for (var key of Object.keys(value || {})) {
    var rule = value[key]
    if (/^(native|compose):/.test(key) && rule && typeof rule.name === "string" && rule.name)
      rules[key] = { name: rule.name, cwd: String(rule.cwd || "") }
  }
  return rules
}
