var COMMON_DEV_PORTS = {
  3000: true, 3001: true, 4000: true, 4173: true, 4200: true,
  4321: true, 5000: true, 5173: true, 5174: true, 8000: true,
  8001: true, 8080: true, 8787: true
}

var EXCLUDED_PROCESSES = {
  "cloudflared": true,
  "containerd": true,
  "cupsd": true,
  "dnsmasq": true,
  "docker-proxy": true,
  "opendeck": true,
  "qemu-system-x86_64": true,
  "sshd": true,
  "systemd-resolved": true
}

var DEV_COMMAND_PATTERN = /(?:^|[ /._-])(?:astro|bun|cargo|deno|django|docusaurus|expo|fastapi|flask|func|gatsby|go|http\.server|mix|next|node|nuxt|parcel|php|pnpm|rails|react-email|remix|storybook|svelte|uvicorn|vite|webpack|yarn)(?:$|[ /._-])/i

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

function parsePs(raw, currentUid) {
  var processes = {}
  var lines = String(raw || "").split(/\r?\n/)
  for (var index = 0; index < lines.length; index++) {
    var match = lines[index].match(/^\s*(\d+)\s+(\d+)\s+(.+)$/)
    if (!match || Number(match[2]) !== Number(currentUid)) continue
    processes[match[1]] = {
      pid: Number(match[1]),
      uid: Number(match[2]),
      command: match[3]
    }
  }
  return processes
}

function parsePwdx(raw) {
  var directories = {}
  var lines = String(raw || "").split(/\r?\n/)
  for (var index = 0; index < lines.length; index++) {
    var match = lines[index].match(/^\s*(\d+):\s*(.+)$/)
    if (match) directories[match[1]] = match[2]
  }
  return directories
}

function parseLanIp(raw) {
  try {
    var routes = JSON.parse(String(raw || "[]"))
    for (var index = 0; index < routes.length; index++) {
      var candidate = String(routes[index].prefsrc || "")
      if (candidate && candidate.indexOf("127.") !== 0) return candidate
    }
  } catch (exception) {}
  return ""
}

function declaredPorts(command) {
  var ports = []
  var value = String(command || "")
  var pattern = /(?:^|\s)(?:-p|--port|--listen-port|--server\.port)(?:=|\s+)(\d+)(?=\s|$)/g
  var match
  while ((match = pattern.exec(value)) !== null) addPort(ports, match[1])

  pattern = /(?:^|\s)-p(\d+)(?=\s|$)/g
  while ((match = pattern.exec(value)) !== null) addPort(ports, match[1])

  var lower = value.toLowerCase()
  if (lower.indexOf("http.server") !== -1 || lower.indexOf("manage.py runserver") !== -1) {
    var words = value.split(/\s+/)
    for (var index = 0; index < words.length; index++) {
      match = words[index].match(/^(?:(?:127\.\d+\.\d+\.\d+|0\.0\.0\.0|localhost|\[::\]):)?(\d+)$/)
      if (match) addPort(ports, match[1])
    }
  }
  return ports
}

function addPort(ports, rawPort) {
  var port = Number(rawPort)
  if (Number.isInteger(port) && port > 0 && port <= 65535 && ports.indexOf(port) === -1)
    ports.push(port)
}

function frameworkFor(command) {
  var lower = String(command || "").toLowerCase()
  var frameworks = [
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
    ["nuxt", "Nuxt", "nuxt"],
    ["svelte", "SvelteKit", "svelte"],
    ["astro", "Astro", "astro"],
    ["vite", "Vite", "vite"],
    ["storybook", "Storybook", "storybook"],
    ["nest start", "NestJS", "nestjs"],
    ["nest.js", "NestJS", "nestjs"],
    ["adonis serve", "AdonisJS", "adonis"],
    ["node ace serve", "AdonisJS", "adonis"],
    ["express", "Express", "express"],
    ["bun", "Bun", "bun"],
    ["deno", "Deno", "deno"],
    ["streamlit run", "Streamlit", "streamlit"],
    ["jupyter lab", "Jupyter", "jupyter"],
    ["jupyter notebook", "Jupyter", "jupyter"],
    ["gradio", "Gradio", "gradio"],
    ["uvicorn", "FastAPI / Uvicorn", "fastapi"],
    ["fastapi", "FastAPI", "fastapi"],
    ["flask", "Flask", "flask"],
    ["manage.py runserver", "Django", "django"],
    ["gunicorn", "Python / Gunicorn", "python"],
    ["hypercorn", "Python / Hypercorn", "python"],
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
  for (var index = 0; index < frameworks.length; index++) {
    if (lower.indexOf(frameworks[index][0]) !== -1)
      return { name: frameworks[index][1], id: frameworks[index][2] }
  }
  if (/(?:^|[ /])node(?:$|[ /])/.test(lower) || lower.indexOf("node_modules") !== -1)
    return { name: "Node.js", id: "node" }
  return { name: "Dev server", id: "server" }
}

function isCandidate(listener, process, framework) {
  if (listener.port < 1024) return false
  var processName = String(listener.process || "").toLowerCase()
  if (EXCLUDED_PROCESSES[processName]) return false
  if (framework.id !== "server") return true
  if (DEV_COMMAND_PATTERN.test(process.command)) return true
  return !!COMMON_DEV_PORTS[listener.port]
}

function primaryListeners(listeners, command) {
  if (!listeners.length) return []
  var explicit = declaredPorts(command)
  if (explicit.length) {
    return listeners.filter(function(listener) {
      return explicit.indexOf(listener.port) !== -1
    })
  }
  if (listeners.length === 1) return listeners
  var conventional = listeners.filter(function(listener) {
    return !!COMMON_DEV_PORTS[listener.port]
  })
  var pool = conventional.length ? conventional : listeners
  var primary = pool[0]
  for (var index = 1; index < pool.length; index++) {
    if (pool[index].port < primary.port) primary = pool[index]
  }
  return [primary]
}

function candidateContexts(listeners, processCache) {
  var grouped = {}
  for (var index = 0; index < listeners.length; index++) {
    var listener = listeners[index]
    var process = processCache[String(listener.pid)]
    if (!process || !process.cwd) continue
    var framework = frameworkFor(process.command)
    if (!isCandidate(listener, process, framework)) continue
    var key = String(listener.pid)
    if (!grouped[key]) grouped[key] = []
    grouped[key].push({ listener: listener, process: process, framework: framework })
  }

  var contexts = []
  for (var pid in grouped) {
    var records = grouped[pid]
    var selected = primaryListeners(records.map(function(record) { return record.listener }), records[0].process.command)
    for (var recordIndex = 0; recordIndex < records.length; recordIndex++) {
      var record = records[recordIndex]
      for (var selectedIndex = 0; selectedIndex < selected.length; selectedIndex++) {
        if (record.listener.port === selected[selectedIndex].port) {
          contexts.push(record)
          break
        }
      }
    }
  }
  contexts.sort(function(a, b) { return a.listener.port - b.listener.port })
  return contexts
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

function browserResponse(status, contentType) {
  var mediaType = String(contentType || "").split(";", 1)[0].trim().toLowerCase()
  return (status >= 200 && status < 400)
    || status === 401
    || status === 403
    || mediaType === "text/html"
    || mediaType === "application/xhtml+xml"
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
    id: listener.pid + ":" + listener.port,
    name: basename(process.cwd) || listener.process || "Development server",
    framework: context.framework.name,
    frameworkId: context.framework.id,
    pid: listener.pid,
    port: listener.port,
    cwd: process.cwd,
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
    var contentType = fields.length > 2 ? fields.slice(2).join("\t") : ""
    if (!transfer || !browserResponse(status, contentType)) continue
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
