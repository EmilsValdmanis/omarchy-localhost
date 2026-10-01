import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"
import vm from "node:vm"

const source = readFileSync(new URL("../qml/RadarModel.js", import.meta.url), "utf8")
const radar = vm.createContext({ console })
vm.runInContext(source, radar, { filename: "RadarModel.js" })

function plain(value) {
  return JSON.parse(JSON.stringify(value))
}

function listener(port) {
  return { pid: 410, port, process: "node", addresses: ["127.0.0.1"] }
}

test("groups IPv4 and IPv6 bindings", () => {
  const raw = [
    'LISTEN 0 511 127.0.0.1:5173 0.0.0.0:* users:(("node",pid=410,fd=22))',
    'LISTEN 0 511 [::]:5173 [::]:* users:(("node",pid=410,fd=23))',
  ].join("\n")
  assert.deepEqual(plain(radar.parseSs(raw)), [{
    pid: 410,
    port: 5173,
    process: "node",
    addresses: ["127.0.0.1", "::"],
  }])
})

test("ignores listeners without a visible PID", () => {
  assert.deepEqual(plain(radar.parseSs("LISTEN 0 4096 127.0.0.53%lo:53 0.0.0.0:*")), [])
})

test("parses verified process metadata from the helper", () => {
  const payload = JSON.stringify({
    ok: true,
    systemMemory: { totalBytes: 16 * 1073741824, availableBytes: 4 * 1073741824 },
    processes: [
      { pid: 410, uid: 1000, command: "node app.js", cwd: "/work/app", executable: "/usr/bin/node", startTime: 991, memoryBytes: 104857600 },
      { pid: 411, uid: 0, command: "root-service", cwd: "/root", startTime: 992 },
      { pid: 412, uid: 1000, command: "missing-identity", cwd: "/work", startTime: 0 },
    ],
  })

  assert.deepEqual(plain(radar.parseProcessPayload(payload, 1000)), {
    ok: true,
    error: "",
    projects: {},
    containers: {},
    systemMemory: { totalBytes: 16 * 1073741824, availableBytes: 4 * 1073741824 },
    processes: {
      410: {
        pid: 410,
        uid: 1000,
        command: "node app.js",
        argv: ["node", "app.js"],
        project: {},
        cwd: "/work/app",
        executable: "/usr/bin/node",
        startTime: 991,
        memoryBytes: 104857600,
        restartAvailable: false,
        restartReason: "",
      },
    },
  })
  assert.equal(radar.parseProcessPayload("not-json", 1000).ok, false)
})

test("parses structured action responses", () => {
  assert.deepEqual(plain(radar.parseActionPayload('{"ok":true,"message":"Server stopped"}', "fallback")), {
    ok: true,
    message: "Server stopped",
  })
  assert.deepEqual(plain(radar.parseActionPayload('{"ok":false,"error":"stale PID"}', "fallback")), {
    ok: false,
    message: "stale PID",
  })
})

test("parses bounded port settings", () => {
  assert.deepEqual(plain(radar.parsePortSet("3000, 8000-8002, 9:10, bad, 0, 70000")), {
    9: true,
    10: true,
    3000: true,
    8000: true,
    8001: true,
    8002: true,
  })
})

test("matches the global server filters", () => {
  const commonDev = { port: 5173, source: "process", lanAvailable: false }
  const unusualLan = { port: 4567, source: "process", lanAvailable: true }
  const docker = { port: 9000, source: "docker", lanAvailable: true }

  assert.equal(radar.matchesServerFilter(commonDev, "all"), true)
  assert.equal(radar.matchesServerFilter(commonDev, "dev"), true)
  assert.equal(radar.matchesServerFilter(unusualLan, "dev"), false)
  assert.equal(radar.matchesServerFilter(unusualLan, "lan"), true)
  assert.equal(radar.matchesServerFilter(commonDev, "lan"), false)
  assert.equal(radar.matchesServerFilter(docker, "docker"), true)
  assert.equal(radar.matchesServerFilter(commonDev, "docker"), false)
  assert.equal(radar.matchesServerFilter(commonDev, "unknown"), true)
})

test("extracts declared ports", () => {
  assert.deepEqual(plain(radar.declaredPorts("vite --port 3000 --listen-port=4000 -p5000")), [3000, 4000, 5000])
})

test("keeps multiple listeners and a fallback port despite the requested --port", () => {
  const listeners = [listener(3001), listener(5173), listener(41125)]
  const processes = { 410: { command: "vite --port 3000", cwd: "/work/app" } }
  assert.deepEqual(plain(radar.candidateContexts(listeners, processes)).map(row => row.listener), listeners)
})

test("excludes named worker processes independently of their port flag", () => {
  const processes = { 410: { command: "nodejsWorker.js --host 127.0.0.1 --port 35729", cwd: "/work/app" } }
  assert.deepEqual(plain(radar.candidateContexts([listener(41523)], processes)), [])
})

test("detects common localhost frameworks", () => {
  const cases = [
    ["node node_modules/.bin/next dev", "next"],
    ["node node_modules/.bin/vue-cli-service serve", "vue"],
    ["bun run dev", "bun"],
    ["python -m uvicorn app:app", "python"],
    ["python manage.py runserver 8000", "django"],
    ["php artisan serve", "laravel"],
    ["mix phx.server", "phoenix"],
    ["./gradlew bootRun", "spring"],
    ["dotnet watch run", "dotnet"],
    ["wrangler dev", "cloudflare"],
  ]

  for (const [command, id] of cases)
    assert.equal(radar.frameworkFor(command).id, id, command)
})

test("framework detection ignores incidental directory names and option values", () => {
  for (const command of [
    "node /work/next-project/server.js", "node /work/chair/index.js",
    "node app.js --cert=/tmp/next", "node app.js --directory next",
  ]) assert.equal(radar.frameworkFor(command).id, "node", command)
  assert.equal(radar.frameworkFor("custom daemon --port 4555").id, "server")
})

test("nearest project dependencies refine generic runtimes without overriding explicit frameworks", () => {
  const cases = [
    ["vite", ["@sveltejs/kit", "svelte", "vite"], "SvelteKit"],
    ["vite", ["react", "vite", "next"], "React"],
    ["node dist/main.js", ["@nestjs/core"], "NestJS"],
    ["bun src/index.ts", ["hono"], "Hono"],
    ["next dev", ["react", "express"], "Next.js"],
    ["python -m uvicorn app:app", ["fastapi", "uvicorn"], "FastAPI"],
    ["python -m uvicorn app:app", ["react"], "Uvicorn"],
    ["python -m http.server 8000", ["fastapi"], "Python HTTP"],
  ]
  for (const [command, dependencies, name] of cases)
    assert.equal(radar.frameworkFor(command, { dependencies }).name, name, command)
})

test("recognizes the Next.js process title read as a single argv entry", () => {
  const title = "next-server (v16.0.0)"
  assert.equal(radar.frameworkFor(title, {}, [title]).id, "next")
  assert.equal(radar.frameworkFor("node app.js", {}, ["node", "app.js", "--label", title]).id, "node")
})

test("port hints parse addresses and positional ports, not unrelated numeric options", () => {
  assert.deepEqual(plain(radar.declaredPorts("gunicorn app:app --bind=0.0.0.0:4567 --workers 4")), [4567])
  assert.deepEqual(plain(radar.declaredPorts("php -S [::]:8082")), [8082])
  assert.deepEqual(plain(radar.declaredPorts("python -m http.server 8010 --bind 127.0.0.1")), [8010])
  assert.deepEqual(plain(radar.declaredPorts("custom --port 70000 --timeout 3000")), [])
})

test("debugger and database listeners are excluded unless explicitly included", () => {
  const listeners = [listener(3000), listener(9229), listener(6379)]
  const process = { command: "node --inspect app.js", cwd: "/work/app" }
  assert.deepEqual(plain(radar.candidateContexts(listeners, { 410: process })).map(row => row.listener.port), [3000])
  assert.deepEqual(plain(radar.candidateContexts(listeners, { 410: process }, {}, { 9229: true })).map(row => row.listener.port), [3000, 9229])
  assert.deepEqual(plain(radar.inspectorPorts("node --inspect-brk=127.0.0.1:9230 app.js")), [9230])
  assert.equal(radar.isCandidate(listener(4567), { command: "custom-server --port 4567" }, { id: "server" }), true)
})

test("keeps unknown servers on the letter fallback path", () => {
  assert.deepEqual(plain(radar.frameworkFor("custom-local-server --port 4567")), {
    name: "Dev server",
    id: "server",
  })
})

test("does not classify Discord's local RPC endpoint as a dev server", () => {
  const command = [
    "/home/user/.config/discord/app-1.0.153/Discord",
    "--type=renderer",
    "--enable-node-leakage-in-renderers",
  ].join(" ")
  const discordListener = {
    pid: 36559,
    port: 6463,
    process: "Discord",
    addresses: ["127.0.0.1"],
  }
  const discordProcess = {
    pid: 36559,
    uid: 1000,
    command,
    cwd: "/home/user/.config/discord/app-1.0.153",
  }

  assert.deepEqual(
    plain(radar.candidateContexts([discordListener], { "36559": discordProcess })),
    [],
  )
})

test("ignores packaged runtime helpers without hiding real Node commands", () => {
  const genericListener = listener(6463)
  const framework = { name: "Dev server", id: "server" }

  assert.equal(radar.isCandidate(genericListener, {
    command: "desktop-app --type=renderer --enable-node-leakage-in-renderers",
  }, framework), false)
  assert.equal(radar.isCandidate(genericListener, {
    command: "/usr/bin/node custom-server.js",
  }, framework), true)
})

test("respects ignored ports and explicit include overrides", () => {
  const generic = listener(4567)
  const process = { command: "custom-local-server", cwd: "/work/custom" }
  const framework = { name: "Dev server", id: "server" }

  assert.equal(radar.isCandidate(generic, process, framework), false)
  assert.equal(radar.isCandidate(generic, process, framework, {}, { 4567: true }), true)
  assert.equal(radar.isCandidate(generic, process, framework, { 4567: true }, { 4567: true }), false)
})

test("explains rejected listeners without hiding extra HTTP candidates", () => {
  const listeners = [listener(4567), listener(5173), listener(5199)]
  const processes = {
    410: {
      pid: 410,
      uid: 1000,
      command: "vite --port 5173",
      cwd: "/work/app",
      startTime: 991,
    },
  }
  const selected = radar.candidateContexts(listeners, processes)

  assert.deepEqual(plain(radar.candidateDiagnostics(listeners, processes, selected, { 4567: true }, {})), [
    { port: 4567, process: "node", reason: "ignored by settings" },
  ])
})

test("classifies browser responses", () => {
  assert.equal(radar.browserResponse(200), true)
  assert.equal(radar.browserResponse(307), true)
  assert.equal(radar.browserResponse(401), true)
  assert.equal(radar.browserResponse(404), true)
  assert.equal(radar.browserResponse(400), true)
  assert.equal(radar.browserResponse(599), true)
  assert.equal(radar.browserResponse(0), false)
  assert.equal(radar.browserResponse(600), false)
})

test("normalizes servers from discovery and model rows", () => {
  const fromDiscovery = radar.normalizeServer({
    id: "410:991:5173",
    name: "app",
    framework: "Vite",
    frameworkId: "vite",
    pid: 410,
    startTime: 991,
    port: 5173,
    cwd: "/work/app",
    localUrl: "http://localhost:5173",
    lanUrl: "http://192.168.0.119:5173",
    lanAvailable: true,
  })
  assert.deepEqual(plain(fromDiscovery), {
    serverId: "410:991:5173",
    name: "app",
    framework: "Vite",
    frameworkId: "vite",
    pid: 410,
    startTime: 991,
    source: "process",
    containerId: "",
    port: 5173,
    cwd: "/work/app",
    localUrl: "http://localhost:5173",
    lanUrl: "http://192.168.0.119:5173",
    lanAvailable: true,
    lanHost: "",
    lanInterface: "",
    lanSubnet: "",
    restartAvailable: false,
    restartReason: "Restart command could not be verified",
    hint: "",
    projectRoot: "/work/app",
    projectPath: "",
    memoryBytes: -1,
    memoryHistoryJson: "[]",
  })

  const fromModelRow = radar.normalizeServer({ serverId: "docker:x:8000", port: "8000" })
  assert.equal(fromModelRow.serverId, "docker:x:8000")
  assert.equal(fromModelRow.port, 8000)
  assert.equal(fromModelRow.name, "Development server")

  assert.deepEqual(plain(radar.normalizeServer(null)), {
    serverId: "",
    name: "Development server",
    framework: "Dev server",
    frameworkId: "server",
    pid: 0,
    startTime: 0,
    source: "process",
    containerId: "",
    port: 0,
    cwd: "",
    localUrl: "",
    lanUrl: "",
    lanAvailable: false,
    lanHost: "",
    lanInterface: "",
    lanSubnet: "",
    restartAvailable: false,
    restartReason: "Restart command could not be verified",
    hint: "",
    projectRoot: "Other servers",
    projectPath: "",
    memoryBytes: -1,
    memoryHistoryJson: "[]",
  })
})

test("RAM formatting and totals count shared processes and containers once", () => {
  assert.equal(radar.formatMemory(-1), "—")
  assert.equal(radar.formatMemory(0), "0.0 MiB")
  assert.equal(radar.formatMemory(104857600), "100 MiB")
  assert.equal(radar.formatMemory(1073741824), "1.00 GiB")
  assert.deepEqual(plain(radar.memorySummary([
    { source: "process", pid: 10, startTime: 20, memoryBytes: 104857600 },
    { source: "process", pid: 10, startTime: 20, memoryBytes: 104857600 },
    { source: "docker", containerId: "abc", memoryBytes: 52428800 },
    { source: "docker", containerId: "abc", memoryBytes: 52428800 },
    { source: "process", pid: 11, startTime: 30, memoryBytes: -1 },
    { serverId: "preview-a", source: "process", pid: 0, memoryBytes: 0 },
    { serverId: "preview-b", source: "process", pid: 0, memoryBytes: 0 },
  ])), { totalBytes: 157286400, measured: 4, unmeasured: 1 })
})

test("system RAM breakdown separates server sources, other usage and available RAM", () => {
  const mib = 1048576
  const servers = [
    { serverId: "web-a", name: "Web", port: 3000, source: "process", pid: 10, startTime: 20, memoryBytes: 200 * mib },
    { serverId: "web-b", name: "Web", port: 3001, source: "process", pid: 10, startTime: 20, memoryBytes: 200 * mib },
    { serverId: "api", name: "API", port: 8000, source: "process", pid: 11, startTime: 21, memoryBytes: 100 * mib },
    { serverId: "unknown", name: "Unknown", port: 9000, source: "docker", containerId: "abc", memoryBytes: -1 },
  ]
  const result = plain(radar.memoryBreakdown(servers, { totalBytes: 1000 * mib, availableBytes: 250 * mib }))
  assert.equal(result.totalBytes, 1000 * mib)
  assert.equal(result.serverBytes, 300 * mib)
  assert.equal(result.otherBytes, 450 * mib)
  assert.equal(result.availableBytes, 250 * mib)
  assert.equal(result.measured, 2)
  assert.equal(result.unmeasured, 1)
  assert.deepEqual(result.sources.map(source => [source.name, source.port, source.bytes, source.barBytes]), [
    ["Web", 3000, 200 * mib, 200 * mib], ["API", 8000, 100 * mib, 100 * mib],
  ])
  assert.equal(result.sources.reduce((sum, source) => sum + source.barBytes, 0)
    + result.otherBytes + result.availableBytes, result.totalBytes)

  const clamped = plain(radar.memoryBreakdown(servers, { totalBytes: 400 * mib, availableBytes: 200 * mib }))
  assert.equal(clamped.otherBytes, 0)
  assert.ok(Math.abs(clamped.sources.reduce((sum, source) => sum + source.barBytes, 0)
    - 200 * mib) < 1)
  assert.deepEqual(plain(radar.normalizeSystemMemory({ totalBytes: 10, availableBytes: 11 })),
    { totalBytes: -1, availableBytes: -1 })
})

test("server equality ignores nothing that the UI renders", () => {
  const base = radar.normalizeServer({ id: "a", name: "app", lanAvailable: false })
  const same = radar.normalizeServer({ id: "a", name: "app", lanAvailable: false })
  const renamed = Object.assign({}, base, { name: "renamed" })
  const lanChanged = Object.assign({}, base, { lanAvailable: true })

  assert.equal(radar.serversEqual(base, same), true)
  assert.equal(radar.serversEqual(base, renamed), false)
  assert.equal(radar.serversEqual(base, lanChanged), false)
})

test("discovers published Docker Compose HTTP ports", () => {
  const raw = [
    '["ed3fec6359f3","api-app-1","node-backend","0.0.0.0:8000->8080/tcp, [::]:8000->8080/tcp","/work/betterat/apps/api","app","api"]',
    '["f7caa08d69cb","api-db-1","postgres:18","0.0.0.0:5432->5432/tcp, [::]:5432->5432/tcp","/work/betterat/apps/api","db","api"]',
  ].join("\n")
  assert.deepEqual(plain(radar.dockerPublishedContexts(raw)), [{
    id: "docker:ed3fec6359f3:8000",
    source: "docker",
    containerId: "ed3fec6359f3",
    displayName: "api / app",
    projectRoot: "/work/betterat/apps/api",
    listener: {
      pid: 0,
      port: 8000,
      process: "api-app-1",
      addresses: ["0.0.0.0", "::"],
    },
    process: {
      pid: 0,
      uid: -1,
      command: "node-backend api app api-app-1",
      cwd: "/work/betterat/apps/api",
    },
    framework: { name: "Docker", id: "docker" },
  }])
})

test("does not HTTP-probe remapped database ports", () => {
  const raw = [
    '["f7caa08d69cb","api-db-1","postgres:18","0.0.0.0:15432->5432/tcp","/work/api","db","api"]',
    '["b49bb7bdabef","queue-1","rabbitmq:management","0.0.0.0:5672->5672/tcp, 0.0.0.0:15672->15672/tcp","/work/api","queue","api"]',
  ].join("\n")

  assert.deepEqual(plain(radar.dockerPublishedContexts(raw)), [{
    id: "docker:b49bb7bdabef:15672",
    source: "docker",
    containerId: "b49bb7bdabef",
    displayName: "api / queue",
    projectRoot: "/work/api",
    listener: {
      pid: 0,
      port: 15672,
      process: "queue-1",
      addresses: ["0.0.0.0"],
    },
    process: {
      pid: 0,
      uid: -1,
      command: "rabbitmq:management api queue queue-1",
      cwd: "/work/api",
    },
    framework: { name: "Docker", id: "docker" },
  }])
})

test("Docker port settings can ignore or explicitly include mappings", () => {
  const database = '["f7caa08d69cb","api-db-1","postgres:18","0.0.0.0:15432->5432/tcp","/work/api","db","api"]'
  assert.deepEqual(plain(radar.dockerPublishedContexts(database)), [])
  assert.equal(radar.dockerPublishedContexts(database, {}, { 15432: true }).length, 1)
  assert.deepEqual(plain(radar.dockerPublishedContexts(database, { 15432: true }, { 15432: true })), [])
})

test("detects LAN reachability", () => {
  assert.equal(radar.lanHostFor(["0.0.0.0"], "192.168.1.42"), "192.168.1.42")
  assert.equal(radar.lanHostFor(["127.0.0.1", "::1"], "192.168.1.42"), "")
  assert.equal(radar.lanHostFor(["10.0.0.8"], "192.168.1.42"), "10.0.0.8")
})

test("finds the active interface and connected LAN subnet", () => {
  const routes = JSON.stringify([
    { dst: "default", dev: "enp5s0", prefsrc: "192.168.0.119" },
    { dst: "172.18.0.0/16", dev: "docker0", scope: "link", prefsrc: "172.18.0.1" },
    { dst: "192.168.0.0/24", dev: "enp5s0", scope: "link", prefsrc: "192.168.0.119" },
  ])
  assert.deepEqual(plain(radar.parseLanRoute(routes)), {
    ip: "192.168.0.119",
    interfaceName: "enp5s0",
    subnet: "192.168.0.0/24",
  })
})

const multiRoutes = JSON.stringify([
  { dst: "default", dev: "wlan0", gateway: "192.168.1.1", metric: 600 },
  { dst: "172.17.0.0/16", dev: "docker0", scope: "link", prefsrc: "172.17.0.1" },
  { dst: "192.168.1.0/24", dev: "wlan0", scope: "link", prefsrc: "192.168.1.42" },
  { dst: "10.0.0.0/24", dev: "enp5s0", scope: "link", prefsrc: "10.0.0.8" },
])
const multiAddresses = JSON.stringify([
  { ifname: "docker0", addr_info: [{ family: "inet", scope: "global", local: "172.17.0.1", prefixlen: 16 }] },
  { ifname: "wlan0", addr_info: [{ family: "inet", scope: "global", local: "192.168.1.42", prefixlen: 24 }] },
  { ifname: "enp5s0", addr_info: [{ family: "inet", scope: "global", local: "10.0.0.8", prefixlen: 24 }] },
])

test("default route without prefsrc resolves its interface address instead of Docker", () => {
  const expected = { ip: "192.168.1.42", interfaceName: "wlan0", subnet: "192.168.1.0/24" }
  assert.deepEqual(plain(radar.parseLanRoute(multiRoutes, multiAddresses)), expected)
  assert.deepEqual(plain(radar.parseLanRoute(multiRoutes)), expected)
  const defaultOnly = JSON.stringify([{ dst: "default", dev: "wlan0" }])
  assert.deepEqual(plain(radar.parseLanRoute(defaultOnly, multiAddresses)), expected)
  assert.equal(radar.parseLanRoute(defaultOnly).ip, "")
  assert.equal(radar.parseLanRoute(multiRoutes, "[]").ip, "", "inactive interface addresses override stale route sources")
})

test("LAN interface selection is explicit and missing interfaces never fall back", () => {
  assert.deepEqual(plain(radar.parseLanRoute(multiRoutes, multiAddresses, "enp5s0")), {
    ip: "10.0.0.8", interfaceName: "enp5s0", subnet: "10.0.0.0/24",
  })
  assert.equal(radar.parseLanRoute(multiRoutes, multiAddresses, "absent").ip, "")
  assert.equal(radar.parseLanRoute("[]", multiAddresses).interfaceName, "wlan0")
  assert.equal(radar.parseLanRoute("[]", multiAddresses, "docker0").interfaceName, "docker0")
})

test("lowest metric default is preferred and malformed network data is ignored", () => {
  const routes = JSON.stringify([
    { dst: "default", dev: "wlan0", metric: 600 }, { dst: "default", dev: "enp5s0", metric: 100 },
  ])
  assert.equal(radar.parseLanRoute(routes, multiAddresses).ip, "10.0.0.8")
  for (const raw of ["invalid", "{}", "null"])
    assert.equal(radar.parseLanRoute(raw, multiAddresses).ip, "")
})

test("each server retains the interface and subnet belonging to its LAN URL", () => {
  const interfaces = radar.parseLanInterfaces(multiRoutes, multiAddresses)
  const route = radar.parseLanRoute(multiRoutes, multiAddresses)
  const context = { listener: listener(3000), process: { cwd: "/work", startTime: 1 }, framework: { name: "Node" } }
  context.listener.addresses = ["10.0.0.8"]
  const server = radar.normalizeServer(radar.serverFromContext(context, "http", route, interfaces))
  assert.equal(server.lanUrl, "http://10.0.0.8:3000")
  assert.equal(server.lanInterface, "enp5s0")
  assert.equal(server.lanSubnet, "10.0.0.0/24")
  context.listener.addresses = ["0.0.0.0"]
  const wildcard = radar.serverFromContext(context, "http", route, interfaces)
  assert.equal(wildcard.lanInterface, "wlan0")
  assert.equal(wildcard.lanSubnet, "192.168.1.0/24")
  context.listener.addresses = ["10.99.0.8"]
  assert.equal(radar.serverFromContext(context, "http", route, interfaces).lanInterface, "")
})

test("restart requires verified recovery for native servers and remains available for Docker", () => {
  assert.equal(radar.actionEnabled(radar.ACTIONS.restart, { source: "process", restartAvailable: false }), false)
  assert.equal(radar.actionEnabled(radar.ACTIONS.restart, { source: "process", restartAvailable: true }), true)
  assert.equal(radar.actionEnabled(radar.ACTIONS.restart, { source: "docker" }), true)
  assert.equal(radar.actionEnabled(radar.ACTIONS.stop, { source: "process", restartAvailable: false }), true)
})

test("local actions stay local and sharing is explicit", () => {
  const server = { localUrl: "http://localhost:3000", lanUrl: "http://192.0.2.12:3000", lanAvailable: true }
  assert.equal(radar.actionUrl(server, false), server.localUrl)
  assert.equal(radar.actionUrl(server, true), server.lanUrl)
  assert.equal(radar.actionEnabled(radar.ACTIONS.copyLan, server), true)
  server.lanAvailable = false
  assert.equal(radar.actionUrl(server, true), "")
  assert.equal(radar.actionEnabled(radar.ACTIONS.copyLan, server), false)
  assert.equal(radar.actionEnabled(radar.ACTIONS.qr, server), false)
  assert.equal(radar.actionEnabled(radar.ACTIONS.copyLocal, server), true)
})

test("source colors are stable across insertion, removal, and reordering", () => {
  const a = { source: "process", pid: 100, startTime: 10 }
  const b = { source: "docker", containerId: "abc123def456" }
  const colors = rows => Object.fromEntries(rows.map(row => [radar.memorySourceKey(row), radar.sourceColorOffset(radar.memorySourceKey(row))]))
  const before = colors([a, b])
  const after = colors([{ source: "process", pid: 5, startTime: 1 }, b, a])
  for (const key of Object.keys(before)) assert.equal(before[key], after[key])
  assert.notEqual(before[radar.memorySourceKey(a)], before[radar.memorySourceKey(b)])
})

test("resource payloads keep process identity and reject other users", () => {
  const raw = JSON.stringify({ ok: true, processes: [
    { pid: 100, uid: 1000, startTime: 10, memoryBytes: 1048576 },
    { pid: 100, uid: 1000, startTime: 11, memoryBytes: 2097152 },
    { pid: 101, uid: 0, startTime: 12, memoryBytes: 100 },
    { pid: 102, uid: 1000, startTime: 0, memoryBytes: 100 },
  ], containers: { abc123def456: 3145728, invalid: 400 }, systemMemory: { totalBytes: 1000, availableBytes: 400 } })
  assert.deepEqual(plain(radar.parseResourcePayload(raw, 1000)), { ok: true,
    memory: { "process:100:10": 1048576, "process:100:11": 2097152, "docker:abc123def456": 3145728 },
    systemMemory: { totalBytes: 1000, availableBytes: 400 } })
  assert.equal(radar.parseResourcePayload("invalid", 1000).ok, false)
})

test("expands Docker published ranges across IPv4 and IPv6 and filters each port", () => {
  const raw = JSON.stringify(["abc123def456", "web", "node", "0.0.0.0:8080-8082->8080-8082/tcp, [::]:8080-8082->8080-8082/tcp", "", "", ""])
  const contexts = plain(radar.dockerPublishedContexts(raw))
  assert.deepEqual(contexts.map(context => context.listener.port), [8080, 8081, 8082])
  assert.ok(contexts.every(context => JSON.stringify(context.listener.addresses) === JSON.stringify(["0.0.0.0", "::"])))
  assert.deepEqual(plain(radar.dockerPublishedContexts(raw, { 8081: true })).map(context => context.listener.port), [8080, 8082])
  const database = JSON.stringify(["abc123def456", "web", "node", "0.0.0.0:16000-16002->5431-5433/tcp", "", "", ""])
  assert.deepEqual(plain(radar.dockerPublishedContexts(database)).map(context => context.listener.port), [16000, 16002])
  assert.equal(radar.dockerPublishedContexts(database, {}, { 16001: true }).length, 3)
})

test("Docker ranges reject malformed bounds, UDP, and unpublished ports", () => {
  for (const mapping of ["0.0.0.0:8080-8082->8080-8081/tcp", "0.0.0.0:8082-8080->8080-8082/tcp", "0.0.0.0:0-2->80-82/tcp", "0.0.0.0:65535-65536->80-81/tcp", "0.0.0.0:8080-8082->8080-8082/udp", "8080-8082/tcp"]) {
    const raw = JSON.stringify(["abc123def456", "web", "node", mapping, "", "", ""])
    assert.deepEqual(plain(radar.dockerPublishedContexts(raw)), [], mapping)
  }
  const ipv6 = JSON.stringify(["abc123def456", "web", "node", ":::8080-8082->8080-8082/tcp", "", "", ""])
  assert.equal(radar.dockerPublishedContexts(ipv6).length, 3)
})

test("manual probe plans bypass both failed and successful caches", () => {
  const contexts = [3000, 3001].map(port => ({ listener: listener(port), process: { startTime: 1 } }))
  const cache = {
    [radar.contextId(contexts[0])]: { scheme: "", expiresAt: 15000 },
    [radar.contextId(contexts[1])]: { scheme: "http", expiresAt: 60000 },
  }
  assert.equal(radar.probePlan(contexts, cache, 100).pending.length, 0)
  assert.deepEqual(plain(radar.probePlan(contexts, cache, 100, true).pending), plain(contexts))
})

test("recognizes exact and broader UFW LAN rules", () => {
  const rules = [
    "-A ufw-user-input -i enp5s0 -p tcp -s 192.168.0.0/24 --dport 3000 -j ACCEPT",
    "-A ufw-user-input -p tcp -s 10.0.0.0/8 -m multiport --dports 3001:3003 -j ACCEPT",
  ].join("\n")
  assert.equal(radar.ufwAllowsPort(rules, "enp5s0", "192.168.0.0/24", 3000), true)
  assert.equal(radar.ufwAllowsPort(rules, "wlan0", "10.12.0.0/24", 3002), true)
  assert.equal(radar.ufwAllowsPort(rules, "enp5s0", "192.168.0.0/24", 4000), false)
})

test("finds only Localhost-managed UFW rules", () => {
  const rules = [
    "### tuple ### allow tcp 3000 0.0.0.0/0 any 192.168.0.0/24 in_enp5s0 comment=6f6d61726368792d6c6f63616c686f7374",
    "-A ufw-user-input -i enp5s0 -p tcp --dport 3000 -s 192.168.0.0/24 -j ACCEPT",
    "### tuple ### allow tcp 8000 0.0.0.0/0 any 192.168.0.0/24 in_enp5s0 comment=6f74686572",
  ].join("\n")
  assert.deepEqual(plain(radar.parseManagedUfwRules(rules, "omarchy-localhost")), [{
    id: "enp5s0:192.168.0.0/24:3000",
    port: 3000,
    interfaceName: "enp5s0",
    subnet: "192.168.0.0/24",
  }])
})

test("process identity participates in stable server IDs", () => {
  const context = {
    listener: { pid: 410, port: 5173 },
    process: { startTime: 991 },
  }
  assert.equal(radar.contextId(context), "410:991:5173")
  context.process.startTime = 992
  assert.equal(radar.contextId(context), "410:992:5173")
})

test("prefers the command-indicated scheme while accepting HTTPS fallback", () => {
  const transfers = [
    { id: "server", scheme: "http", preference: 0 },
    { id: "server", scheme: "https", preference: 1 },
  ]
  assert.deepEqual(plain(radar.parseProbeOutput("1\t200\ttext/html\n", transfers)), {
    server: { scheme: "https", preference: 1 },
  })
  assert.deepEqual(plain(radar.parseProbeOutput("1\t200\n0\t204\n", transfers)), {
    server: { scheme: "http", preference: 0 },
  })
})

test("parses qrencode ASCII output", () => {
  assert.deepEqual(plain(radar.parseQrAscii("######\n##  ##\n######\n")), {
    size: 3,
    rows: ["111", "101", "111"],
  })
})
