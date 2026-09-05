var COMMON_DEV_PORTS = {
  3000: true, 3001: true, 4000: true, 4173: true, 4200: true,
  4321: true, 5000: true, 5173: true, 5174: true, 8000: true,
  8001: true, 8080: true, 8787: true
}

function isCommonDevPort(port) {
  return COMMON_DEV_PORTS[Number(port)] === true
}

function matchesServerFilter(server, filterId) {
  var normalized = normalizeServer(server)
  var selectedFilter = String(filterId || "all")
  if (selectedFilter === "dev") return isCommonDevPort(normalized.port)
  if (selectedFilter === "lan") return normalized.lanAvailable
  if (selectedFilter === "docker") return normalized.source === "docker"
  return true
}

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

function splitEndpoint(endpoint) {
  var value = String(endpoint || "").trim()
  var address = ""
  var rawPort = ""
  if (value.charAt(0) === "[" && value.indexOf("]:") !== -1) {
    var close = value.lastIndexOf("]:")
    address = value.slice(1, close)
    rawPort = value.slice(close + 2)
  } else {
    var colon = value.lastIndexOf(":")
    if (colon === -1) return null
    address = value.slice(0, colon)
    rawPort = value.slice(colon + 1)
  }
  address = address.split("%")[0]
  var port = Number(rawPort)
  if (!Number.isInteger(port) || port < 1 || port > 65535) return null
  return { address: address, port: port }
}

function parseSs(raw) {
  var grouped = {}
  var lines = String(raw || "").split(/\r?\n/)
  for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
    var line = lines[lineIndex].trim()
    if (!line) continue
    var fields = line.split(/\s+/)
    if (fields.length < 5) continue
    var endpoint = splitEndpoint(fields[3])
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
        executable: String(row.executable || ""),
        startTime: startTime,
        argv: Array.isArray(row.argv) ? row.argv.map(String) : commandTokens(command),
        project: row.project && typeof row.project === "object" ? row.project : {}
      }
    }
    return { ok: true, error: "", processes: processes, projects: payload.projects || {} }
  } catch (exception) {
    return { ok: false, error: "Could not parse process metadata", processes: {} }
  }
}

function normalizeServer(server) {
  var source = server || {}
  return {
    serverId: String(source.serverId || source.id || ""),
    name: String(source.name || "Development server"),
    framework: String(source.framework || "Dev server"),
    frameworkId: String(source.frameworkId || "server"),
    pid: Number(source.pid || 0),
    startTime: Number(source.startTime || 0),
    source: String(source.source || "process"),
    containerId: String(source.containerId || ""),
    port: Number(source.port || 0),
    cwd: String(source.cwd || ""),
    localUrl: String(source.localUrl || ""),
    lanUrl: String(source.lanUrl || ""),
    lanAvailable: source.lanAvailable === true,
    hint: String(source.hint || ""),
    projectRoot: String(source.projectRoot || source.cwd || source.serverId || source.id || "Other servers"),
    projectPath: String(source.projectPath || "")
  }
}

function serversEqual(left, right) {
  return left.serverId === right.serverId
    && left.name === right.name
    && left.framework === right.framework
    && left.frameworkId === right.frameworkId
    && Number(left.pid) === Number(right.pid)
    && Number(left.startTime) === Number(right.startTime)
    && left.source === right.source
    && left.containerId === right.containerId
    && Number(left.port) === Number(right.port)
    && left.cwd === right.cwd
    && left.localUrl === right.localUrl
    && left.lanUrl === right.lanUrl
    && left.lanAvailable === right.lanAvailable
    && left.hint === right.hint
    && left.projectRoot === right.projectRoot
    && left.projectPath === right.projectPath
}

// Synchronize a QML ListModel without resetting delegates or their scroll origin.
// Stable scans take a single linear pass; only structural changes move rows.
function syncServerModel(model, servers) {
  var incoming = Object.create(null)
  var rows = []
  for (var i = 0; i < servers.length; i++) {
    var row = normalizeServer(servers[i])
    if (!row.serverId || incoming[row.serverId]) continue
    incoming[row.serverId] = true
    rows.push(row)
  }
  var changed = false
  for (var old = model.count - 1; old >= 0; old--) {
    if (!incoming[model.get(old).serverId]) {
      model.remove(old)
      changed = true
    }
  }
  for (var target = 0; target < rows.length; target++) {
    var next = rows[target]
    if (target >= model.count || model.get(target).serverId !== next.serverId) {
      var current = target + 1
      while (current < model.count && model.get(current).serverId !== next.serverId) current++
      if (current < model.count) model.move(current, target, 1)
      else model.insert(target, next)
      changed = true
    }
    if (!serversEqual(model.get(target), next)) {
      model.set(target, next)
      changed = true
    }
  }
  return changed
}

function matchesSearch(server, query, filterId) {
  if (!matchesServerFilter(server, filterId)) return false
  if (!query) return true
  return [server.name, server.framework, server.frameworkId, server.port,
    server.cwd, server.projectRoot, server.projectPath, server.localUrl, server.lanUrl, server.source, server.containerId]
    .join(" ").toLowerCase().indexOf(query) !== -1
}

function probePlan(contexts, cache, now) {
  var schemes = {}
  var pending = []
  for (var i = 0; i < contexts.length; i++) {
    var context = contexts[i]
    var id = contextId(context)
    var cached = cache[id]
    if (!cached || Number(cached.expiresAt || 0) <= now) pending.push(context)
    else if (cached.scheme) schemes[id] = cached.scheme
  }
  return { schemes: schemes, pending: pending }
}

function compareServers(left, right, grouped) {
  if (grouped) {
    var group = basename(left.projectRoot).localeCompare(basename(right.projectRoot))
      || left.projectRoot.localeCompare(right.projectRoot)
    if (group) return group
  }
  return left.port - right.port || left.name.localeCompare(right.name) || left.serverId.localeCompare(right.serverId)
}

function projectGroups(servers) {
  var groups = Object.create(null)
  for (var i = 0; i < servers.length; i++) {
    var server = servers[i]
    var key = server.projectRoot
    if (!groups[key]) groups[key] = { name: basename(key).replace(/^compose:/, ""), count: 0 }
    groups[key].count++
  }
  return groups
}

function actionEnabled(index, server) {
  return !!server && (index !== 2 || server.lanAvailable)
    && ((index !== 3 && index !== 4) || server.cwd !== "")
}

function parseActionPayload(raw, fallback) {
  try {
    var payload = JSON.parse(String(raw || ""))
    if (payload && payload.ok === true)
      return { ok: true, message: String(payload.message || fallback || "Action completed") }
    return { ok: false, message: String((payload && payload.error) || fallback || "Action failed") }
  } catch (exception) {
    return { ok: false, message: String(fallback || "Action failed") }
  }
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
    if (first < 1 || last > 65535 || last - first > 4096) continue
    for (var port = first; port <= last; port++) ports[port] = true
  }
  return ports
}

function parseLanRoute(raw) {
  var empty = { ip: "", interfaceName: "", subnet: "" }
  try {
    var routes = JSON.parse(String(raw || "[]"))
    var preferred = null
    for (var index = 0; index < routes.length; index++) {
      var route = routes[index]
      var candidate = String(route.prefsrc || route.src || "")
      var interfaceName = String(route.dev || "")
      if (!candidate || candidate.indexOf("127.") === 0 || interfaceName === "lo") continue
      if (String(route.dst || "") === "default") {
        preferred = route
        break
      }
      if (!preferred) preferred = route
    }
    if (!preferred) return empty

    var ip = String(preferred.prefsrc || preferred.src || "")
    var device = String(preferred.dev || "")
    var subnet = ""
    for (var routeIndex = 0; routeIndex < routes.length; routeIndex++) {
      var connected = routes[routeIndex]
      var destination = String(connected.dst || "")
      if (String(connected.dev || "") !== device || destination.indexOf("/") === -1) continue
      if (cidrContainsAddress(destination, ip)) {
        subnet = destination
        break
      }
    }
    return { ip: ip, interfaceName: device, subnet: subnet }
  } catch (exception) {}
  return empty
}

function parseLanIp(raw) {
  return parseLanRoute(raw).ip
}

function ipv4Number(address) {
  var parts = String(address || "").split(".")
  if (parts.length !== 4) return -1
  var value = 0
  for (var index = 0; index < parts.length; index++) {
    var part = Number(parts[index])
    if (!Number.isInteger(part) || part < 0 || part > 255) return -1
    value = value * 256 + part
  }
  return value
}

function cidrBounds(cidr) {
  var parts = String(cidr || "").split("/")
  var address = ipv4Number(parts[0])
  var prefix = parts.length === 1 ? 32 : Number(parts[1])
  if (address < 0 || !Number.isInteger(prefix) || prefix < 0 || prefix > 32) return null
  var size = Math.pow(2, 32 - prefix)
  var first = Math.floor(address / size) * size
  return { first: first, last: first + size - 1 }
}

function cidrContainsAddress(cidr, address) {
  var bounds = cidrBounds(cidr)
  var value = ipv4Number(address)
  return !!bounds && value >= bounds.first && value <= bounds.last
}

function cidrContainsSubnet(outer, inner) {
  var outerBounds = cidrBounds(outer)
  var innerBounds = cidrBounds(inner)
  return !!outerBounds && !!innerBounds
    && innerBounds.first >= outerBounds.first
    && innerBounds.last <= outerBounds.last
}

function portSpecAllows(spec, port) {
  var target = Number(port)
  var sections = String(spec || "").split(",")
  for (var index = 0; index < sections.length; index++) {
    var range = sections[index].split(/[:-]/)
    var first = Number(range[0])
    var last = range.length > 1 ? Number(range[1]) : first
    if (Number.isInteger(first) && Number.isInteger(last) && target >= first && target <= last)
      return true
  }
  return false
}

function ufwAllowsPort(raw, interfaceName, subnet, port) {
  var lines = String(raw || "").split(/\r?\n/)
  for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
    var line = lines[lineIndex].trim()
    if (line.indexOf("-A ufw-user-input ") !== 0) continue
    var fields = line.split(/\s+/)
    var options = {}
    for (var fieldIndex = 2; fieldIndex < fields.length; fieldIndex++) {
      var field = fields[fieldIndex]
      if (field.charAt(0) !== "-") continue
      var next = fields[fieldIndex + 1]
      if (next && next.charAt(0) !== "-") {
        options[field] = next
        fieldIndex++
      } else {
        options[field] = true
      }
    }

    if (options["-j"] !== "ACCEPT") continue
    if (options["-p"] && options["-p"] !== "tcp") continue
    if (options["-i"] && options["-i"] !== interfaceName) continue
    if (options["-s"] && !cidrContainsSubnet(options["-s"], subnet)) continue
    if (!portSpecAllows(options["--dport"] || options["--dports"], port)) continue
    return true
  }
  return false
}

function decodeHex(value) {
  var result = ""
  var input = String(value || "")
  if (!/^(?:[0-9a-fA-F]{2})+$/.test(input)) return ""
  for (var index = 0; index < input.length; index += 2)
    result += String.fromCharCode(parseInt(input.slice(index, index + 2), 16))
  return result
}

function parseManagedUfwRules(raw, managedComment) {
  var expected = String(managedComment || "omarchy-localhost")
  var rules = []
  var seen = {}
  var lines = String(raw || "").split(/\r?\n/)
  for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
    var line = lines[lineIndex].trim()
    if (line.indexOf("### tuple ### ") !== 0) continue
    var fields = line.slice(14).trim().split(/\s+/)
    if (fields.length < 7 || fields[0] !== "allow" || fields[1] !== "tcp") continue

    var comment = ""
    for (var fieldIndex = 0; fieldIndex < fields.length; fieldIndex++) {
      if (fields[fieldIndex].indexOf("comment=") === 0)
        comment = decodeHex(fields[fieldIndex].slice(8))
    }
    if (comment !== expected) continue

    var port = Number(fields[2])
    if (!Number.isInteger(port) || port < 1 || port > 65535) continue
    var subnet = String(fields[5] || "")
    var interfaceName = ""
    for (var tokenIndex = 0; tokenIndex < fields.length; tokenIndex++) {
      if (fields[tokenIndex].indexOf("in_") === 0)
        interfaceName = fields[tokenIndex].slice(3)
    }
    var id = interfaceName + ":" + subnet + ":" + port
    if (seen[id]) continue
    seen[id] = true
    rules.push({ id: id, port: port, interfaceName: interfaceName, subnet: subnet })
  }
  rules.sort(function(a, b) { return a.port - b.port || a.id.localeCompare(b.id) })
  return rules
}

function declaredPorts(command) {
  var ports = []
  var tokens = commandTokens(command)
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

// Command arguments and executable/package names are matched exactly. A folder
// named "next-project" or "chair" must not turn Node into Next.js or Go/Air.
function commandTokens(command) {
  var matches = String(command || "").match(/(?:[^\s"']+|"[^"\n]*"|'[^'\n]*')+/g) || []
  return matches.map(function(token) { return token.replace(/^["']|["']$/g, "") })
}

// A true fourth field lets package dependencies refine a generic runtime label.
var FRAMEWORK_RULES = [
  ["docusaurus", "Docusaurus", "docusaurus"],
  ["react-email", "React Email", "react"],
  ["func start", "Azure Functions", "azure"],
  ["wrangler dev", "Cloudflare Workers", "cloudflare"],
  ["firebase emulators", "Firebase", "firebase"],
  ["supabase start", "Supabase", "supabase"],
  ["prisma studio", "Prisma Studio", "prisma"],
  ["graphql-yoga", "GraphQL Yoga", "graphql"],
  ["apollo-server", "Apollo Server", "graphql"],
  ["vue-cli-service", "Vue", "vue"],
  ["ng serve", "Angular", "angular"],
  ["solid-start", "SolidStart", "solid"],
  ["qwik", "Qwik", "qwik"],
  ["remix", "Remix", "remix"],
  ["gatsby", "Gatsby", "gatsby"],
  ["ember serve", "Ember", "ember"],
  ["eleventy", "Eleventy", "eleventy"],
  ["electron", "Electron", "electron"],
  ["tauri dev", "Tauri", "tauri"],
  ["expo start", "Expo", "expo"],
  ["webpack serve", "Webpack", "webpack"],
  ["webpack-dev-server", "Webpack", "webpack"],
  ["parcel serve", "Parcel", "parcel"],
  ["hugo server", "Hugo", "hugo"],
  ["jekyll serve", "Jekyll", "jekyll"],
  ["next", "Next.js", "next"],
  ["next-server", "Next.js", "next"],
  ["nuxt", "Nuxt", "nuxt"],
  ["svelte", "Svelte", "svelte"],
  ["astro", "Astro", "astro"],
  ["vite", "Vite", "vite", true],
  ["storybook", "Storybook", "storybook"],
  ["nest start", "NestJS", "nestjs"],
  ["nest.js", "NestJS", "nestjs"],
  ["adonis serve", "AdonisJS", "adonis"],
  ["node ace serve", "AdonisJS", "adonis"],
  ["express", "Express", "express"],
  ["bun", "Bun", "bun", true],
  ["deno", "Deno", "deno", true],
  ["streamlit run", "Streamlit", "streamlit"],
  ["jupyter lab", "Jupyter", "jupyter"],
  ["jupyter notebook", "Jupyter", "jupyter"],
  ["gradio", "Gradio", "gradio"],
  ["uvicorn", "Uvicorn", "python", true],
  ["fastapi", "FastAPI", "fastapi"],
  ["flask", "Flask", "flask"],
  ["manage.py runserver", "Django", "django"],
  ["gunicorn", "Python / Gunicorn", "python", true],
  ["hypercorn", "Python / Hypercorn", "python", true],
  ["rails server", "Rails", "rails"],
  ["rails s", "Rails", "rails"],
  ["sinatra", "Sinatra", "sinatra"],
  ["php artisan serve", "Laravel", "laravel"],
  ["symfony server", "Symfony", "symfony"],
  ["wp-env start", "WordPress", "wordpress"],
  ["php -s", "PHP", "php"],
  ["mix phx.server", "Phoenix", "phoenix"],
  ["mix run", "Elixir", "elixir"],
  ["http.server", "Python HTTP", "python"],
  ["trunk serve", "Rust / Trunk", "rust"],
  ["leptos", "Leptos", "rust"],
  ["cargo run", "Rust", "rust"],
  ["go run", "Go", "go"],
  ["air", "Go / Air", "go"],
  ["spring-boot", "Spring Boot", "spring"],
  ["bootrun", "Spring Boot", "spring"],
  ["quarkus:dev", "Quarkus", "quarkus"],
  ["quarkus dev", "Quarkus", "quarkus"],
  ["dotnet watch", ".NET", "dotnet"],
  ["dotnet run", ".NET", "dotnet"],
  ["grafana server", "Grafana", "grafana"],
  ["prometheus", "Prometheus", "prometheus"]
]

var PROJECT_FRAMEWORKS = [
  ["@sveltejs/kit", "SvelteKit", "svelte"], ["@astrojs/core", "Astro", "astro"],
  ["astro", "Astro", "astro"], ["next", "Next.js", "next"], ["nuxt", "Nuxt", "nuxt"],
  ["@nestjs/core", "NestJS", "nestjs"], ["@remix-run/react", "Remix", "remix"],
  ["@solidjs/start", "SolidStart", "solid"], ["@builder.io/qwik", "Qwik", "qwik"],
  ["@angular/core", "Angular", "angular"], ["hono", "Hono", "hono"],
  ["fastify", "Fastify", "fastify"], ["express", "Express", "express"],
  ["svelte", "Svelte", "svelte"], ["solid-js", "SolidJS", "solid"],
  ["react", "React", "react"], ["vue", "Vue", "vue"], ["vite", "Vite", "vite"],
  ["fastapi", "FastAPI", "fastapi"], ["django", "Django", "django"], ["flask", "Flask", "flask"]
]

function frameworkFor(command, project, argv) {
  var args = argv && argv.length ? argv : commandTokens(command)
  var tokens = args.map(function(arg, index) {
    // Next rewrites argv[0] through process.title, including its version suffix.
    if (index === 0 && /^next-server \(v[^\s)]+\)$/.test(arg)) return "next-server"
    var previous = String(args[index - 1] || "")
    if (/^--?[^=]+$/.test(previous) && ["-m", "--", "--watch"].indexOf(previous) === -1) return ""
    return (arg.charAt(0) === "-" ? arg : basename(arg)).toLowerCase().replace(/\.(?:m?js|cjs)$/, "")
  })
  var result = null
  var generic = true
  for (var i = 0; i < FRAMEWORK_RULES.length && !result; i++) {
    var rule = FRAMEWORK_RULES[i]
    var parts = rule[0].replace(/\.js$/, "").split(" ")
    for (var j = 0; j <= tokens.length - parts.length; j++) {
      if (parts.every(function(part, offset) { return tokens[j + offset] === part })) {
        result = { name: rule[1], id: rule[2] }
        generic = rule[3] === true
        break
      }
    }
  }
  if (generic) {
    var dependencies = project && Array.isArray(project.dependencies) ? project.dependencies : []
    var python = tokens.some(function(token) { return /^(?:python[\d.]*|uvicorn|gunicorn|hypercorn|flask|django)$/.test(token) })
    var javascript = tokens.some(function(token) { return /^(?:node|nodejs|bun|deno|vite|tsx|ts-node|npm|pnpm|yarn)$/.test(token) })
    for (var k = 0; k < PROJECT_FRAMEWORKS.length; k++) {
      var candidate = PROJECT_FRAMEWORKS[k]
      var pythonFramework = ["fastapi", "django", "flask"].indexOf(candidate[2]) !== -1
      if ((pythonFramework ? !python : !javascript) || dependencies.indexOf(candidate[0]) === -1) continue
      if (result && result.id === "vite" && ["next", "nuxt", "nestjs", "express", "fastify", "hono"].indexOf(candidate[2]) !== -1) continue
      return { name: candidate[1], id: candidate[2] }
    }
  }
  if (result) return result
  if (tokens.indexOf("node") !== -1 || tokens.indexOf("nodejs") !== -1 || tokens.indexOf("tsx") !== -1)
    return { name: "Node.js", id: "node" }
  return { name: "Dev server", id: "server" }
}

function inspectorPorts(command) {
  var ports = []
  var tokens = commandTokens(command)
  for (var i = 0; i < tokens.length; i++) {
    var match = tokens[i].match(/^--inspect(?:-brk|-wait|-port)?(?:=(.*))?$/)
    if (!match) continue
    var value = match[1] === undefined ? "9229" : match[1]
    var endpoint = value.match(/(?:^|:)(\d+)$/)
    addPort(ports, endpoint ? endpoint[1] : 9229)
  }
  return ports
}

function candidateRejectionReason(listener, process, framework, ignoredPorts, alwaysIncludePorts) {
  var ignored = ignoredPorts || {}
  var alwaysInclude = alwaysIncludePorts || {}
  if (!process || !process.command) return "process metadata unavailable"
  if (ignored[listener.port]) return "ignored by settings"
  if (alwaysInclude[listener.port]) return ""
  if (listener.port < 1024) return "privileged/system port"
  var processName = String(listener.process || "").toLowerCase()
  if (EXCLUDED_PROCESSES[processName]) return "excluded desktop or system process"
  if (RUNTIME_HELPER_PATTERN.test(String(process.command || ""))) return "runtime helper process"
  if (NON_HTTP_CONTAINER_PORTS[listener.port]) return "non-HTTP service port"
  if (/(?:^|[ /])(?:nodejsWorker|tsserver|typingsInstaller)\.js(?:[ \'"]|$)/i.test(process.command)) return "runtime helper process"
  if (inspectorPorts(process.command).indexOf(listener.port) !== -1) return "debugger port"
  if (framework.id !== "server") return ""
  if (DEV_COMMAND_PATTERN.test(process.command)) return ""
  if (COMMON_DEV_PORTS[listener.port] || declaredPorts(process.command).indexOf(listener.port) !== -1) return ""
  return "command and port are not recognized as a development server"
}

function isCandidate(listener, process, framework, ignoredPorts, alwaysIncludePorts) {
  return candidateRejectionReason(
    listener, process, framework, ignoredPorts, alwaysIncludePorts) === ""
}

function candidateContexts(listeners, processCache, ignoredPorts, alwaysIncludePorts) {
  var contexts = []
  var frameworks = {}
  for (var index = 0; index < listeners.length; index++) {
    var listener = listeners[index]
    var process = processCache[String(listener.pid)]
    if (!process || !process.cwd) continue
    var framework = frameworks[listener.pid]
    if (!framework) {
      framework = frameworkFor(process.command, process.project, process.argv)
      frameworks[listener.pid] = framework
    }
    if (isCandidate(listener, process, framework, ignoredPorts, alwaysIncludePorts))
      contexts.push({ listener: listener, process: process, framework: framework })
  }
  contexts.sort(function(a, b) { return a.listener.port - b.listener.port || a.listener.pid - b.listener.pid })
  return contexts
}

function candidateDiagnostics(listeners, processCache, selectedContexts, ignoredPorts, alwaysIncludePorts) {
  var selected = {}
  var contexts = selectedContexts || []
  for (var selectedIndex = 0; selectedIndex < contexts.length; selectedIndex++) {
    var selectedListener = contexts[selectedIndex].listener
    selected[selectedListener.pid + ":" + selectedListener.port] = true
  }

  var diagnostics = []
  for (var index = 0; index < listeners.length; index++) {
    var listener = listeners[index]
    var process = processCache[String(listener.pid)]
    var framework = process ? frameworkFor(process.command, process.project, process.argv) : { name: "Dev server", id: "server" }
    var reason = !process || !process.cwd
      ? "process metadata unavailable"
      : candidateRejectionReason(
        listener, process, framework, ignoredPorts, alwaysIncludePorts)
    if (!reason && !selected[listener.pid + ":" + listener.port])
      reason = "listener not selected"
    if (!reason) continue
    diagnostics.push({
      port: listener.port,
      process: String(listener.process || (process && process.command) || "unknown"),
      reason: reason
    })
  }
  diagnostics.sort(function(a, b) { return a.port - b.port || a.process.localeCompare(b.process) })
  return diagnostics
}

function dockerPublishedContexts(raw, ignoredPorts, alwaysIncludePorts) {
  var contexts = []
  var ignored = ignoredPorts || {}
  var alwaysInclude = alwaysIncludePorts || {}
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
    if (!containerId || !publishedPorts) continue

    var grouped = {}
    var mappings = publishedPorts.split(/,\s*/)
    for (var mappingIndex = 0; mappingIndex < mappings.length; mappingIndex++) {
      var match = mappings[mappingIndex].match(/^(?:(\[[^\]]+\]|[^:]+):)?(\d+)->(\d+)(?:\/tcp)?$/)
      if (!match) continue
      var address = String(match[1] || "0.0.0.0").replace(/^\[|\]$/g, "")
      var port = Number(match[2])
      var containerPort = Number(match[3])
      if (!Number.isInteger(port) || port < 1 || port > 65535) continue
      if (ignored[port]) continue
      if (NON_HTTP_CONTAINER_PORTS[containerPort] && !alwaysInclude[port]) continue
      if (!grouped[port]) grouped[port] = []
      if (grouped[port].indexOf(address) === -1) grouped[port].push(address)
    }

    for (var rawPort in grouped) {
      var hostPort = Number(rawPort)
      var name = project && service ? project + " / " + service
        : (service || project || containerName || basename(cwd) || image || "Docker service")
      contexts.push({
        id: "docker:" + containerId + ":" + hostPort,
        source: "docker",
        containerId: containerId,
        projectRoot: cwd || (project ? "compose:" + project : "docker:" + containerId),
        displayName: name,
        listener: {
          pid: 0,
          port: hostPort,
          process: containerName || image || "docker",
          addresses: grouped[rawPort]
        },
        process: {
          pid: 0,
          uid: -1,
          command: [image, project, service, containerName].join(" "),
          cwd: cwd
        },
        framework: { name: "Docker", id: "docker" }
      })
    }
  }
  contexts.sort(function(a, b) { return a.listener.port - b.listener.port })
  return contexts
}

function contextId(context) {
  return String(context.id || (context.listener.pid + ":" + Number(context.process.startTime || 0)
    + ":" + context.listener.port))
}

function schemeFor(command) {
  var lower = String(command || "").toLowerCase()
  var tokens = ["--https", "https://", "ssl-keyfile", "--ssl", "https=true"]
  for (var index = 0; index < tokens.length; index++)
    if (lower.indexOf(tokens[index]) !== -1) return "https"
  return "http"
}

function probeHost(addresses) {
  for (var index = 0; index < addresses.length; index++)
    if (String(addresses[index]).indexOf("127.") === 0) return addresses[index]
  if (addresses.indexOf("::1") !== -1) return "::1"
  if (addresses.indexOf("0.0.0.0") !== -1 || addresses.indexOf("*") !== -1) return "127.0.0.1"
  if (addresses.indexOf("::") !== -1) return "::1"
  return addresses.length ? addresses[0] : "localhost"
}

function urlHost(host) {
  var value = String(host || "")
  return value.indexOf(":") !== -1 && value.charAt(0) !== "[" ? "[" + value + "]" : value
}

function probeUrl(context, scheme) {
  return scheme + "://" + urlHost(probeHost(context.listener.addresses)) + ":" + context.listener.port + "/"
}

function browserResponse(status) {
  // Any HTTP status proves there is an HTTP service on the port. APIs commonly
  // return a JSON 404 or 405 at `/`, so requiring a successful HTML page hides
  // healthy backend services.
  return status >= 100 && status <= 599
}

function isLoopback(address) {
  var value = String(address || "")
  return value === "::1" || value.indexOf("127.") === 0
}

function isUnspecified(address) {
  return address === "0.0.0.0" || address === "::" || address === "*"
}

function isLinkLocal(address) {
  var value = String(address || "").toLowerCase()
  return value.indexOf("169.254.") === 0 || value.indexOf("fe80:") === 0
}

function lanHostFor(addresses, defaultLanIp) {
  if (defaultLanIp) {
    if (addresses.indexOf("0.0.0.0") !== -1 || addresses.indexOf("*") !== -1
        || addresses.indexOf("::") !== -1 || addresses.indexOf(defaultLanIp) !== -1)
      return defaultLanIp
  }
  for (var index = 0; index < addresses.length; index++) {
    var candidate = String(addresses[index]).split("%")[0]
    if (!isLoopback(candidate) && !isUnspecified(candidate) && !isLinkLocal(candidate))
      return candidate
  }
  return ""
}

function basename(path) {
  var value = String(path || "").replace(/\/+$/, "")
  var slash = value.lastIndexOf("/")
  return slash === -1 ? value : value.slice(slash + 1)
}

function serverFromContext(context, scheme, lanIp) {
  var listener = context.listener
  var process = context.process
  var lanHost = lanHostFor(listener.addresses, lanIp)
  var lanAvailable = lanHost !== ""
  var loopbackBound = listener.addresses.some(isLoopback)
  var wildcardBound = listener.addresses.some(isUnspecified)
  var localHost = loopbackBound || wildcardBound ? "localhost" : (lanHost || "localhost")
  return {
    id: contextId(context),
    name: context.displayName || (process.project && process.project.name) || basename(process.cwd) || listener.process || "Development server",
    framework: context.framework.name,
    frameworkId: context.framework.id,
    pid: Number(listener.pid || 0),
    startTime: Number(process.startTime || 0),
    source: String(context.source || "process"),
    containerId: String(context.containerId || ""),
    port: listener.port,
    cwd: process.cwd,
    projectRoot: (process.project && process.project.root) || process.cwd || context.projectRoot || contextId(context),
    projectPath: (process.project && process.project.relativePath) || "",
    command: String(process.command || "").slice(0, 240),
    bindAddresses: listener.addresses,
    localUrl: scheme + "://" + urlHost(localHost) + ":" + listener.port,
    lanUrl: lanAvailable ? scheme + "://" + urlHost(lanHost) + ":" + listener.port : "",
    lanHost: lanHost,
    lanAvailable: lanAvailable,
    status: lanAvailable ? "Available on LAN" : "Not available on LAN",
    hint: lanAvailable
      ? "Same Wi-Fi network required"
      : "Server is bound to localhost only. Start it with --host / 0.0.0.0 to test on another device."
  }
}

function parseProbeOutput(raw, transferMap) {
  var accepted = {}
  var lines = String(raw || "").split(/\r?\n/)
  for (var index = 0; index < lines.length; index++) {
    var fields = lines[index].split("\t")
    if (fields.length < 2) continue
    var transfer = transferMap[Number(fields[0])]
    var status = Number(fields[1])
    if (!transfer || !browserResponse(status)) continue
    var previous = accepted[transfer.id]
    if (!previous || transfer.preference < previous.preference)
      accepted[transfer.id] = { scheme: transfer.scheme, preference: transfer.preference }
  }
  return accepted
}

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

var FRAMEWORK_ICONS = {
  hono: "\uf06d", fastify: "\uf0e7",
  next: "", vite: "", svelte: "", astro: "", nuxt: "",
  angular: "", react: "", vue: "", solid: "", qwik: "",
  remix: "", gatsby: "", ember: "", eleventy: "", expo: "",
  electron: "", tauri: "", webpack: "", storybook: "",
  cloudflare: "", azure: "", firebase: "", supabase: "",
  graphql: "", prisma: "", bun: "", deno: "", node: "", docker: "",
  express: "", nestjs: "", adonis: "", python: "",
  django: "", fastapi: "", flask: "", streamlit: "",
  jupyter: "", ruby: "", rails: "", php: "", laravel: "",
  symfony: "", wordpress: "", elixir: "", phoenix: "",
  rust: "", go: "", java: "", spring: "", quarkus: "",
  dotnet: "", grafana: "", prometheus: ""
}

function frameworkIcon(frameworkId) {
  return FRAMEWORK_ICONS[frameworkId] || ""
}
