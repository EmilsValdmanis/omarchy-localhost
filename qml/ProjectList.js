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
