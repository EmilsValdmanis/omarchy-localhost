// Docker lists containers newest first. A recreated replica can temporarily
// coexist with its stopped predecessor under the same Compose replica number.
function recordReplica(inventory, cwd, project, service, slot, state, status) {
  var key = JSON.stringify([cwd, project, service])
  if (!inventory.has(key)) inventory.set(key, new Map())
  var replicas = inventory.get(key)
  if (!replicas.has(slot)) replicas.set(slot, { state: state, status: status })
}

function replicaStatus(replica, condition) {
  if (replica.state === "exited" && condition === "service_completed_successfully"
      && /^Exited \(0\)(?: |$)/.test(replica.status)) return "completed"
  if (replica.state !== "running") return replica.state
  var health = replica.status.match(/\((?:health: )?(healthy|unhealthy|starting)\)$/)
  return health ? health[1] : "running"
}

function serviceStates(inventory, container) {
  var states = new Set()
  // Keep the hovered service first, with its declared dependencies below it.
  for (var dependency of [container.service].concat(container.dependsOn.split(",").sort())) {
    var parts = dependency.split(":")
    var name = parts[0]
    if (!name) continue
    var replicas = inventory.get(JSON.stringify([container.cwd, container.project, name]))
    if (!replicas) {
      states.add(name + " unknown")
      continue
    }
    for (var slot of Array.from(replicas.keys()).sort()) {
      var label = name + (replicas.size > 1 ? " [" + slot + "]" : "")
      states.add(label + " " + replicaStatus(replicas.get(slot), parts[1]))
    }
  }
  return Array.from(states).join("\n")
}

// Split at the last space to preserve replica labels such as "worker [2]".
function tooltipRows(details, serviceName) {
  var rows = []
  for (var line of details.split("\n")) {
    if (!line) continue
    var split = line.lastIndexOf(" ")
    var name = line.slice(0, split)
    rows.push({ name: name, status: line.slice(split + 1), isOwner: name.split(" ")[0] === serviceName })
  }
  return rows
}

function hasProblem(details) {
  return /(?:^| )(unhealthy|exited|restarting|paused|dead)(?:$|\n| · )/.test(details)
}
