// Headers and visible servers share one cursor order. Server indices still
// address the complete filtered model, so folding never changes result totals.
function entriesFor(servers, groups, grouped, collapsed) {
  var entries = []
  var previousRoot = ""
  for (var index = 0; index < servers.length; index++) {
    var server = servers[index]
    var projectRoot = server.projectRoot
    var folded = grouped && collapsed[projectRoot] === true
    if (grouped && projectRoot !== previousRoot) {
      var group = groups[projectRoot]
      entries.push({
        entryId: "project:" + projectRoot, projectRoot: projectRoot,
        projectHeader: true, name: group.name, count: group.count,
        collapsed: folded, serverIndex: -1, serverId: ""
      })
    }
    if (!folded) entries.push({
      entryId: "server:" + server.serverId, projectRoot: projectRoot,
      projectHeader: false, name: "", count: 0, collapsed: false,
      serverIndex: index, serverId: server.serverId
    })
    previousRoot = projectRoot
  }
  return entries
}

function entriesEqual(left, right) {
  return left.entryId === right.entryId && left.projectRoot === right.projectRoot
    && left.projectHeader === right.projectHeader && left.name === right.name
    && left.count === right.count && left.collapsed === right.collapsed
    && left.serverIndex === right.serverIndex && left.serverId === right.serverId
}

// Keep surviving delegates and the native scroll origin through scans/folds.
function syncEntries(model, entries) {
  var incoming = Object.create(null)
  for (var i = 0; i < entries.length; i++) incoming[entries[i].entryId] = true
  var changed = false
  for (var old = model.count - 1; old >= 0; old--) {
    if (!incoming[model.get(old).entryId]) {
      model.remove(old)
      changed = true
    }
  }
  for (var target = 0; target < entries.length; target++) {
    var next = entries[target]
    if (target >= model.count || model.get(target).entryId !== next.entryId) {
      var current = target + 1
      while (current < model.count && model.get(current).entryId !== next.entryId) current++
      if (current < model.count) model.move(current, target, 1)
      else model.insert(target, next)
      changed = true
    }
    if (!entriesEqual(model.get(target), next)) {
      model.set(target, next)
      changed = true
    }
  }
  return changed
}
