.import "Paths.js" as Paths
.import "Compose.js" as Compose
.import "Diagnostics.js" as Diagnostics
.import "Frameworks.js" as Frameworks
.import "Network.js" as Network
.import "Ports.js" as Ports

// Active HTTP probes are noisy when they hit databases and other services:
// some of them log the HTTP request as a malformed protocol handshake. Match
// the container-side port so a remapped service (for example 15432->5432) is
// still excluded, while browser-facing ports from the same container remain.

var NON_HTTP_CONTAINER_PORTS = {
  21: true, 22: true, 25: true, 53: true, 110: true, 143: true,
  389: true, 465: true, 587: true, 636: true, 993: true, 995: true,
  1433: true, 1521: true, 1883: true, 3306: true, 4222: true,
  5432: true, 5672: true, 6379: true, 9092: true, 11211: true,
  26257: true, 27017: true
}

var EXCLUDED_PROCESSES = {
  "cloudflared": true,
  "containerd": true,
  "cupsd": true,
  "discord": true,
  "dnsmasq": true,
  "docker-proxy": true,
  "opendeck": true,
  "postgres": true,
  "redis-server": true,
  "mysqld": true,
  "mariadbd": true,
  "mongod": true,
  "memcached": true,
  "qemu-system-x86_64": true,
  "sshd": true,
  "systemd-resolved": true
}

var DEV_COMMAND_PATTERN = /(?:^|[ /])(?:astro|bun|cargo|deno|django|docusaurus|expo|fastapi|flask|func|gatsby|go|http\.server|mix|next|node|nuxt|parcel|php|pnpm|rails|react-email|remix|storybook|svelte|uvicorn|vite|webpack|yarn)(?:$|[ /])/i

var RUNTIME_HELPER_PATTERN = /(?:^|\s)--type=(?:gpu-process|renderer|utility|zygote)(?:\s|$)/i

function parseSs(raw) {
  var grouped = {}
  var lines = String(raw || "").split(/\r?\n/)
  for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
    var line = lines[lineIndex].trim()
    if (!line) continue
    var fields = line.split(/\s+/)
    if (fields.length < 5) continue
    var endpoint = Network.splitEndpoint(fields[3])
    if (!endpoint) continue

    var processField = fields.slice(5).join(" ")
    var pidMatches = []
    var pidPattern = /pid=(\d+)/g
    var pidMatch
    while ((pidMatch = pidPattern.exec(processField)) !== null)
      pidMatches.push(Number(pidMatch[1]))

    var names = []
    var namePattern = /\("([^"]+)"/g
    var nameMatch
    while ((nameMatch = namePattern.exec(processField)) !== null)
      names.push(nameMatch[1])

    for (var pidIndex = 0; pidIndex < pidMatches.length; pidIndex++) {
      var pid = pidMatches[pidIndex]
      var key = pid + ":" + endpoint.port
      if (!grouped[key]) {
        grouped[key] = {
          pid: pid,
          port: endpoint.port,
          process: names[pidIndex] || names[0] || "",
          addresses: []
        }
      }
      if (grouped[key].addresses.indexOf(endpoint.address) === -1)
        grouped[key].addresses.push(endpoint.address)
    }
  }

  var listeners = []
  for (var key in grouped) listeners.push(grouped[key])
  listeners.sort(function(a, b) { return a.port - b.port || a.pid - b.pid })
  return listeners
}

function parseProcessPayload(raw, currentUid) {
  try {
    var payload = JSON.parse(String(raw || ""))
    if (!payload || payload.ok !== true || !Array.isArray(payload.processes))
      return { ok: false, error: String((payload && payload.error) || "Could not read process metadata"), processes: {} }

    var processes = {}
    for (var index = 0; index < payload.processes.length; index++) {
      var row = payload.processes[index] || {}
      var pid = Number(row.pid)
      var uid = Number(row.uid)
      var startTime = Number(row.startTime)
      if (!Number.isInteger(pid) || pid <= 1 || uid !== Number(currentUid)
          || !Number.isInteger(startTime) || startTime <= 0) continue
      var command = String(row.command || "")
      var cwd = String(row.cwd || "")
      if (!command || !cwd) continue
      processes[String(pid)] = {
        pid: pid,
        uid: uid,
        command: command,
        cwd: cwd,
        cwdDeleted: row.cwdDeleted === true,
        executable: String(row.executable || ""),
        startTime: startTime,
        restartAvailable: row.restartAvailable === true,
        restartReason: String(row.restartReason || ""),
        serviceKey: String(row.serviceKey || ""),
        serviceEntry: String(row.serviceEntry || ""),
        argv: Array.isArray(row.argv) ? row.argv.map(String) : Frameworks.commandTokens(command),
        project: row.project && typeof row.project === "object" ? row.project : {}
      }
    }
    return { ok: true, error: "", processes: processes, projects: payload.projects || {} }
  } catch (exception) {
    return { ok: false, error: "Could not parse process metadata", processes: {} }
  }
}

function probePlan(contexts, cache, now, bypassCache) {
  var schemes = {}
  var pending = []
  for (var i = 0; i < contexts.length; i++) {
    var context = contexts[i]
    var id = contextId(context)
    var cached = cache[probeCacheKey(context)]
    if (bypassCache || !cached || Number(cached.expiresAt || 0) <= now) pending.push(context)
    else if (cached.scheme) schemes[id] = cached.scheme
  }
  return { schemes: schemes, pending: pending }
}

function declaredPorts(command) {
  var ports = []
  var tokens = Frameworks.commandTokens(command)
  for (var i = 0; i < tokens.length; i++) {
    var token = tokens[i]
    var match = token.match(/^(?:-p|--port|--listen-port|--server\.port|--bind|--listen|-b|-S)(?:=(.*))?$/)
    var value = match ? (match[1] === undefined ? tokens[++i] : match[1]) : ""
    if (/^-p\d+$/.test(token)) value = token.slice(2)
    if (token === "http.server" || token === "runserver") value = tokens[i + 1]
    var endpoint = String(value || "").match(/(?:^|:)(\d+)$/)
    if (endpoint) addPort(ports, endpoint[1])
  }
  return ports
}

function addPort(ports, rawPort) {
  var port = Number(rawPort)
  if (Number.isInteger(port) && port > 0 && port <= 65535 && ports.indexOf(port) === -1)
    ports.push(port)
}

function inspectorPorts(command) {
  var ports = []
  var tokens = Frameworks.commandTokens(command)
  for (var i = 0; i < tokens.length; i++) {
    var match = tokens[i].match(/^--inspect(?:-brk|-wait|-port)?(?:=(.*))?$/)
    if (!match) continue
    var value = match[1] === undefined ? "9229" : match[1]
    var endpoint = value.match(/(?:^|:)(\d+)$/)
    addPort(ports, endpoint ? endpoint[1] : 9229)
  }
  return ports
}

function listenerPortsByPid(listeners) {
  var ports = {}
  for (var i = 0; i < listeners.length; i++) {
    var listener = listeners[i]
    if (!ports[listener.pid]) ports[listener.pid] = []
    ports[listener.pid].push(listener.port)
  }
  return ports
}

function frameworkHelperReason(listener, process, framework, siblingPorts) {
  var ports = siblingPorts || []
  if (ports.length < 2) return ""
  var declared = declaredPorts(process.command)
  if (declared.indexOf(listener.port) !== -1) return ""
  var dependencies = process.project && Array.isArray(process.project.dependencies) ? process.project.dependencies : []
  if (listener.port === 4206 && dependencies.indexOf("@tanstack/devtools-vite") !== -1
      && ports.some(function(port) {
        return port !== listener.port && (declared.length ? declared.indexOf(port) !== -1 : Ports.isCommonDevPort(port))
      })) return Diagnostics.REASONS.devtools
  // Functions hosts expose an additional loopback endpoint for their workers.
  // Require the same host's configured (or default) app port to be listening.
  var appPorts = declared.length ? declared : [7071]
  if (framework.id === "azure" && appPorts.indexOf(listener.port) === -1
      && listener.addresses && listener.addresses.length && listener.addresses.every(Network.isLoopback)
      && ports.some(function(port) { return appPorts.indexOf(port) !== -1 }))
    return Diagnostics.REASONS.worker
  return ""
}

function candidateRejectionReason(listener, process, framework, ignoredPorts, alwaysIncludePorts, siblingPorts) {
  var ignored = ignoredPorts || {}
  var alwaysInclude = alwaysIncludePorts || {}
  if (!process || !process.command) return Diagnostics.REASONS.metadataUnavailable
  if (ignored[listener.port]) return Diagnostics.REASONS.ignored
  if (alwaysInclude[listener.port]) return ""
  if (listener.port < 1024) return Diagnostics.REASONS.privileged
  var processName = String(listener.process || "").toLowerCase()
  if (EXCLUDED_PROCESSES[processName]) return Diagnostics.REASONS.excludedProcess
  if (RUNTIME_HELPER_PATTERN.test(String(process.command || ""))) return Diagnostics.REASONS.runtimeHelper
  if (NON_HTTP_CONTAINER_PORTS[listener.port]) return Diagnostics.REASONS.nonHttp
  if (/(?:^|[ /])(?:nodejsWorker|tsserver|typingsInstaller)\.js(?:[ \'"]|$)/i.test(process.command)) return Diagnostics.REASONS.runtimeHelper
  if (inspectorPorts(process.command).indexOf(listener.port) !== -1) return Diagnostics.REASONS.debugger
  var helperReason = frameworkHelperReason(listener, process, framework, siblingPorts)
  if (helperReason) return helperReason
  if (process.cwdDeleted) return ""
  if (framework.id !== "server") return ""
  if (DEV_COMMAND_PATTERN.test(process.command)) return ""
  if (Ports.COMMON_DEV_PORTS[listener.port] || declaredPorts(process.command).indexOf(listener.port) !== -1) return ""
  return Diagnostics.REASONS.unrecognized
}

function classifyListeners(listeners, processCache, ignoredPorts, alwaysIncludePorts, previousServers) {
  var contexts = []
  var diagnostics = []
  var frameworks = {}
  var portsByPid = listenerPortsByPid(listeners)
  // A deleted directory can no longer supply package metadata or service identity.
  // Keep the last observation only while the same process owns the same cwd.
  for (var entry of previousServers || []) {
    var previous = entry.context.process
    var current = processCache[String(previous.pid)]
    if (current && current.cwdDeleted && current.startTime === previous.startTime && current.cwd === previous.cwd) {
      current.project = previous.project
      current.serviceKey = previous.serviceKey
      current.serviceEntry = previous.serviceEntry
    }
  }
  for (var index = 0; index < listeners.length; index++) {
    var listener = listeners[index]
    var process = processCache[String(listener.pid)]
    var framework = frameworks[listener.pid]
    if (!framework && process) {
      framework = Frameworks.frameworkFor(process.command, process.project, process.argv)
      frameworks[listener.pid] = framework
    }
    var reason = !process || !process.cwd ? Diagnostics.REASONS.metadataUnavailable
      : candidateRejectionReason(listener, process, framework, ignoredPorts, alwaysIncludePorts, portsByPid[listener.pid])
    if (reason) diagnostics.push({ port: listener.port,
      process: String(listener.process || (process && process.command) || "unknown"), reason: reason })
    else contexts.push({ listener: listener, process: process, framework: framework })
  }
  contexts.sort(function(a, b) { return a.listener.port - b.listener.port || a.listener.pid - b.listener.pid })
  return { contexts: contexts, diagnostics: diagnostics }
}

var MAX_DOCKER_PORTS = 1024

var MAX_DOCKER_RANGE_PORTS = 128

function classifyDockerPorts(raw, ignoredPorts, alwaysIncludePorts) {
  var contexts = []
  var ignored = ignoredPorts || {}
  var alwaysInclude = alwaysIncludePorts || {}
  var records = []
  var composeInventory = new Map()
  var mappingsToExpand = []
  var count = 0
  var diagnosticKeys = {}
  var stats = { truncated: false, diagnostics: [] }
  var lines = String(raw || "").split(/\r?\n/)
  for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
    var line = lines[lineIndex].trim()
    if (!line) continue

    var record
    try {
      record = JSON.parse(line)
    } catch (exception) {
      continue
    }
    if (!Array.isArray(record) || record.length < 7) continue

    var containerId = String(record[0] || "")
    var containerName = String(record[1] || "")
    var image = String(record[2] || "")
    var publishedPorts = String(record[3] || "")
    var cwd = String(record[4] || "")
    var service = String(record[5] || "")
    var project = String(record[6] || "")
    var state = String(record[7] || "")
    var oneOff = String(record[10] || "").toLowerCase() === "true"
    if (!containerId) continue
    var composeService = project && service && !oneOff
    if (composeService && state)
      Compose.recordReplica(composeInventory, cwd, project, service, String(record[11] || containerName),
        state, String(record[8] || ""))
    if (!publishedPorts || (state && state !== "running")) continue

    var entry = { containerId: containerId, containerName: containerName, image: image,
      cwd: cwd, service: service, project: project, grouped: {},
      serviceKey: composeService ? "compose:" + JSON.stringify([cwd, project, service]) : "",
      dependsOn: composeService ? String(record[9] || "") : "" }
    records.push(entry)
    var mappings = publishedPorts.split(/,\s*/)
    for (var mappingIndex = 0; mappingIndex < mappings.length; mappingIndex++) {
      var match = mappings[mappingIndex].match(/^(?:(\[[^\]]+\]|.+):)?(\d+)(?:-(\d+))?->(\d+)(?:-(\d+))?(?:\/tcp)?$/)
      if (!match) continue
      var address = String(match[1] || "0.0.0.0").replace(/^\[|\]$/g, "")
      var port = Number(match[2])
      var lastPort = Number(match[3] || match[2])
      var containerPort = Number(match[4])
      var lastContainerPort = Number(match[5] || match[4])
      if (port < 1 || lastPort > 65535 || containerPort < 1 || lastContainerPort > 65535
          || lastPort < port || lastContainerPort < containerPort
          || lastPort - port !== lastContainerPort - containerPort) continue
      mappingsToExpand.push({ entry: entry, address: address, port: port,
        lastPort: lastPort, containerPort: containerPort })
    }
  }

  mappingsToExpand.sort(function(a, b) { return (a.lastPort - a.port) - (b.lastPort - b.port) })
  var explicitPorts = Object.keys(alwaysInclude).filter(function(port) { return alwaysInclude[port] })
    .map(Number).filter(function(port) { return Number.isInteger(port) && port >= 1 && port <= 65535 })
  for (var mappingIndex = 0; mappingIndex < mappingsToExpand.length; mappingIndex++) {
    var mapping = mappingsToExpand[mappingIndex]
    var grouped = mapping.entry.grouped
    var selected = {}
    var selectedCount = 0
    function addMappedPort(hostPort) {
      if (selected[hostPort]) return
      var reason = ignored[hostPort] ? Diagnostics.REASONS.ignored
        : (NON_HTTP_CONTAINER_PORTS[mapping.containerPort + hostPort - mapping.port] && !alwaysInclude[hostPort] ? Diagnostics.REASONS.nonHttp : "")
      if (reason) {
        var diagnosticKey = mapping.entry.containerId + ":" + hostPort
        if (!diagnosticKeys[diagnosticKey]) {
          diagnosticKeys[diagnosticKey] = true
          if (stats.diagnostics.length < MAX_DOCKER_PORTS)
            stats.diagnostics.push({ port: hostPort, process: mapping.entry.containerName || mapping.entry.image || "docker", reason: reason })
          else stats.truncated = true
        }
        return
      }
      selected[hostPort] = true
      if (selectedCount >= MAX_DOCKER_RANGE_PORTS) { stats.truncated = true; return }
      selectedCount++
      if (!grouped[hostPort]) {
        if (count >= MAX_DOCKER_PORTS) { stats.truncated = true; return }
        grouped[hostPort] = []
        count++
      }
      if (grouped[hostPort].indexOf(mapping.address) === -1) grouped[hostPort].push(mapping.address)
    }
    for (var explicitIndex = 0; explicitIndex < explicitPorts.length; explicitIndex++) {
      var explicitPort = explicitPorts[explicitIndex]
      if (explicitPort >= mapping.port && explicitPort <= mapping.lastPort) addMappedPort(explicitPort)
    }
    var hostPort = mapping.port
    for (; hostPort <= mapping.lastPort && selectedCount < MAX_DOCKER_RANGE_PORTS; hostPort++)
      addMappedPort(hostPort)
    for (; hostPort <= mapping.lastPort; hostPort++) {
      if (!selected[hostPort] && !ignored[hostPort]
          && (!NON_HTTP_CONTAINER_PORTS[mapping.containerPort + hostPort - mapping.port] || alwaysInclude[hostPort])) {
        stats.truncated = true
        break
      }
    }
  }

  for (var recordIndex = 0; recordIndex < records.length; recordIndex++) {
    var entry = records[recordIndex]
    var grouped = entry.grouped
    var states = entry.serviceKey ? Compose.serviceStates(composeInventory, entry) : ""
    for (var rawPort in grouped) {
      var hostPort = Number(rawPort)
      var name = entry.project && entry.service ? entry.project + " / " + entry.service
        : (entry.service || entry.project || entry.containerName || Paths.basename(entry.cwd) || entry.image || "Docker service")
      contexts.push({
        id: "docker:" + entry.containerId + ":" + hostPort,
        source: "docker",
        containerId: entry.containerId,
        dependencyStates: states,
        serviceKey: entry.serviceKey,
        projectRoot: entry.cwd || (entry.project ? "compose:" + entry.project : "docker:" + entry.containerId),
        displayName: name,
        listener: {
          pid: 0,
          port: hostPort,
          process: entry.containerName || entry.image || "docker",
          addresses: grouped[rawPort]
        },
        process: {
          pid: 0,
          uid: -1,
          command: [entry.image, entry.project, entry.service, entry.containerName].join(" "),
          cwd: entry.cwd
        },
        framework: { name: "Docker", id: "docker" }
      })
    }
  }
  contexts.sort(function(a, b) { return a.listener.port - b.listener.port })
  return { contexts: contexts, diagnostics: stats.diagnostics, truncated: stats.truncated }
}

function contextId(context) {
  return String(context.id || (context.listener.pid + ":" + Number(context.process.startTime || 0)
    + ":" + context.listener.port))
}

function probeCacheKey(context) {
  return JSON.stringify([contextId(context), Network.probeHost(context.listener.addresses || []), schemeFor(context.process.command),
    context.process.cwdDeleted === true])
}

function schemeFor(command) {
  var lower = String(command || "").toLowerCase()
  var tokens = ["--https", "https://", "ssl-keyfile", "--ssl", "https=true"]
  for (var index = 0; index < tokens.length; index++)
    if (lower.indexOf(tokens[index]) !== -1) return "https"
  return "http"
}

function probeUrl(probe) {
  var listener = probe.context.listener
  var path = probe.target === "*" ? "/" : probe.target
  return probe.scheme + "://" + Network.urlHost(Network.probeHost(listener.addresses)) + ":" + listener.port + path
}

function browserResponse(status) {
  // An HTTP error still identifies a web server, including one that rejects OPTIONS.
  return status >= 100 && status <= 599
}

function serverFromContext(context, scheme, lanRoute, lanInterfaces) {
  var listener = context.listener
  var process = context.process
  var route = lanRoute || {}
  var lanHost = Network.lanHostFor(listener.addresses, route.ip)
  if (lanHost !== route.ip) {
    route = {}
    var interfaces = lanInterfaces || []
    for (var index = 0; index < interfaces.length; index++)
      if (interfaces[index].ip === lanHost) { route = interfaces[index]; break }
  }
  var lanAvailable = !!scheme && lanHost !== ""
  var loopbackBound = listener.addresses.some(Network.isLoopback)
  var wildcardBound = listener.addresses.some(Network.isUnspecified)
  var localHost = loopbackBound || wildcardBound ? "localhost" : (lanHost || "localhost")
  var projectRoot = (process.project && process.project.root) || process.cwd || context.projectRoot || contextId(context)
  return {
    id: contextId(context),
    name: context.displayName || (process.project && process.project.name) || Paths.basename(process.cwd) || listener.process || "Development server",
    framework: context.framework.name,
    frameworkId: context.framework.id,
    pid: Number(listener.pid || 0),
    startTime: Number(process.startTime || 0),
    source: String(context.source || "process"),
    containerId: String(context.containerId || ""),
    dependencyStates: context.dependencyStates || "",
    serviceKey: context.serviceKey || process.serviceKey || "",
    serviceName: context.displayName || (process.serviceEntry
      ? Paths.basename(process.cwd) + " / " + process.serviceEntry : ""),
    port: listener.port,
    cwd: process.cwd,
    cwdDeleted: process.cwdDeleted === true,
    projectRoot: process.cwdDeleted ? "deleted:" + projectRoot : projectRoot,
    projectPath: (process.project && process.project.relativePath) || "",
    gitBranch: (process.project && process.project.gitBranch) || "",
    gitCommonDir: (!process.cwdDeleted && process.project && process.project.gitCommonDir) || "",
    probeTarget: context.probeTarget || "/",
    localUrl: scheme ? scheme + "://" + Network.urlHost(localHost) + ":" + listener.port : "",
    lanUrl: lanAvailable ? scheme + "://" + Network.urlHost(lanHost) + ":" + listener.port : "",
    lanHost: lanHost,
    lanInterface: String(route.interfaceName || ""),
    lanSubnet: String(route.subnet || ""),
    lanAvailable: lanAvailable,
    restartAvailable: context.source === "docker" || process.restartAvailable === true,
    restartReason: String(process.restartReason || ""),
    hint: !scheme ? "The listener is still running but did not answer the HTTP check." : lanAvailable
      ? "Same Wi-Fi network required"
      : (listener.addresses.length && listener.addresses.every(Network.isLoopback)
        ? "Server listens on localhost only. Bind it to 0.0.0.0 or a LAN address to share."
        : "No LAN address is available. Connect to a local network or check the LAN interface setting.")
  }
}

// Try the ordinary homepage first. Only look for another target when a server
// rejects that request. A general server failure or rate limit needs no retry.
var PROBE_TARGETS = ["/", "/health", "*"]

function firstProbe(context, cached, manual) {
  var target = (cached && cached.target) || "/"
  return {
    context: context,
    scheme: (cached && cached.scheme) || schemeFor(context.process.command),
    target: target,
    remaining: cached && cached.exhausted && !manual ? [] : PROBE_TARGETS.filter(function(item) { return item !== target }),
    alternateTarget: target,
    firstResponse: ""
  }
}

function probeResult(probe, status) {
  var responded = browserResponse(status)
  var rejected = [400, 401, 403, 404, 405, 501].indexOf(status) !== -1
  if (responded && !rejected) return { scheme: probe.scheme, target: probe.target }
  var firstResponse = probe.firstResponse || (responded ? probe.target : "")
  if (firstResponse) {
    if (!probe.remaining.length) return { scheme: probe.scheme, target: firstResponse, exhausted: true }
    return { retry: Object.assign({}, probe, { target: probe.remaining[0],
      remaining: probe.remaining.slice(1), firstResponse: firstResponse }) }
  }
  // A stale learned endpoint can go silent while the listener still serves HTTP.
  if (probe.target !== "/") return { retry: Object.assign({}, probe, {
    target: "/", remaining: probe.remaining.filter(function(item) { return item !== "/" }) }) }
  if (probe.alternateTarget) {
    var scheme = probe.scheme === "http" ? "https" : "http"
    var alternate = firstProbe(probe.context, { target: probe.alternateTarget, scheme: scheme })
    alternate.alternateTarget = ""
    return { retry: alternate }
  }
  return { scheme: "" }
}

function probeStatuses(raw) {
  var statuses = []
  for (var line of String(raw || "").split(/\r?\n/)) {
    var match = line.match(/^(\d+)\t(\d{3})$/)
    if (match) statuses[Number(match[1])] = Number(match[2])
  }
  return statuses
}
