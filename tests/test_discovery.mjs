import assert from "node:assert/strict"
import test from "node:test"
import { loadQmlJs, plain } from "./support/qml_js.mjs"

const Discovery = loadQmlJs("Discovery.js")

test("Compose dependency health follows declared services and current replicas", () => {
  function container(service, state, status, options = {}) {
    return JSON.stringify([options.id || service, service, service, options.ports || "",
      options.cwd || "/work/shop", service, options.project || "shop", state, status,
      options.depends || "", options.oneOff || "False", options.slot || "1"])
  }
  const web = container("web", "running", "Up 2 minutes", {
    ports: "127.0.0.1:3000->80/tcp",
    depends: "postgres:service_healthy:false,redis:service_started:false,migrate:service_completed_successfully:false,worker,cache",
  })
  const rows = [
    web,
    container("postgres", "exited", "Exited (1) 1 minute ago", { oneOff: "True" }),
    container("postgres", "running", "Up 2 minutes (unhealthy)"),
    container("redis", "exited", "Exited (0) 2 minutes ago", { ports: "127.0.0.1:5555->80/tcp" }),
    container("migrate", "exited", "Exited (0) 5 minutes ago"),
    container("worker", "running", "Up 1 minute (healthy)"),
    container("worker", "paused", "Up 2 minutes (Paused)", { slot: "2" }),
    container("cache", "running", "Up 1 minute"),
    container("cache", "exited", "Exited (1) yesterday", { id: "old-cache" }),
    container("cache", "restarting", "Restarting (1)", { cwd: "/trees/shop", slot: "3" }),
    container("cache", "dead", "Dead", { project: "different", slot: "4" }),
    container("unrelated", "dead", "Dead"),
  ]
  const [context] = Discovery.classifyDockerPorts(rows.join("\n")).contexts
  assert.equal(Discovery.classifyDockerPorts(rows.join("\n")).contexts.length, 1)
  assert.equal(Discovery.serverFromContext(context, "http", {}).dependencyStates,
    "web running\ncache running\nmigrate completed\npostgres unhealthy\nredis exited\nworker [1] healthy\nworker [2] paused")
  const recovered = [web, container("postgres", "running", "Up 1 minute (healthy)"),
    container("redis", "running", "Up 10 seconds (health: starting)")]
  assert.equal(Discovery.classifyDockerPorts(recovered.join("\n")).contexts[0].dependencyStates,
    "web running\ncache unknown\nmigrate unknown\npostgres healthy\nredis starting\nworker unknown")
  const failures = [web, container("migrate", "exited", "Exited (1) yesterday"),
    container("worker", "restarting", "Restarting (1)"), container("cache", "dead", "Dead")]
  assert.equal(Discovery.classifyDockerPorts(failures.join("\n")).contexts[0].dependencyStates,
    "web running\ncache dead\nmigrate exited\npostgres unknown\nredis unknown\nworker restarting")
})

function listener(port) {
  return { pid: 410, port, process: "node", addresses: ["127.0.0.1"] }
}

test("published Compose one-offs can be skipped independently of the service", () => {
  const rows = ["False", "True"].map((oneOff, i) => JSON.stringify([
    "id-" + i, "shop-web-" + i, "web", "127.0.0.1:" + (8080 + i) + "->80/tcp",
    "/work/shop", "web", "shop", "running", "Up 1 minute", "", oneOff, "1",
  ]))
  const [service, oneOff] = Discovery.classifyDockerPorts(rows.join("\n")).contexts
  assert.equal(service.serviceKey, 'compose:["/work/shop","shop","web"]')
  assert.equal(oneOff.serviceKey, "")
})

test("skipped Docker ports remain available for inclusion without duplicate address rows", () => {
  const raw = JSON.stringify(["abcdef123456", "api", "image", "0.0.0.0:8000->8000/tcp, [::]:8000->8000/tcp, 0.0.0.0:15432->5432/tcp", "/work", "api", "demo"])
  const skipped = Discovery.classifyDockerPorts(raw, { 8000: true }, {})
  assert.equal(skipped.contexts.length, 0)
  assert.deepEqual(plain(skipped.diagnostics).sort((a,b) => a.port-b.port), [
    { port: 8000, process: "api", reason: "ignored" },
    { port: 15432, process: "api", reason: "non-http" },
  ])
  const included = Discovery.classifyDockerPorts(raw, {}, { 8000: true, 15432: true })
  assert.equal(included.contexts.length, 2)
  assert.deepEqual(plain(included.diagnostics), [])
})

test("groups IPv4 and IPv6 bindings", () => {
  const raw = [
    'LISTEN 0 511 127.0.0.1:5173 0.0.0.0:* users:(("node",pid=410,fd=22))',
    'LISTEN 0 511 [::]:5173 [::]:* users:(("node",pid=410,fd=23))',
  ].join("\n")
  assert.deepEqual(plain(Discovery.parseSs(raw)), [{
    pid: 410,
    port: 5173,
    process: "node",
    addresses: ["127.0.0.1", "::"],
  }])
})

test("ignores listeners without a visible PID", () => {
  assert.deepEqual(plain(Discovery.parseSs("LISTEN 0 4096 127.0.0.53%lo:53 0.0.0.0:*")), [])
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

  assert.deepEqual(plain(Discovery.parseProcessPayload(payload, 1000)), {
    ok: true,
    error: "",
    projects: {},
    processes: {
      410: {
        pid: 410,
        uid: 1000,
        command: "node app.js",
        argv: ["node", "app.js"],
        project: {},
        cwd: "/work/app",
        cwdDeleted: false,
        executable: "/usr/bin/node",
        startTime: 991,
        restartAvailable: false,
        restartReason: "",
        serviceKey: "",
        serviceEntry: "",
      },
    },
  })
  assert.equal(Discovery.parseProcessPayload("not-json", 1000).ok, false)
})

test("extracts declared ports", () => {
  assert.deepEqual(plain(Discovery.declaredPorts("vite --port 3000 --listen-port=4000 -p5000")), [3000, 4000, 5000])
})

test("a deleted cwd retains the same launch's project and skip identity across scans", () => {
  const process = { pid: 410, startTime: 99, cwd: "/trees/shop/web", command: "node app.js",
    project: { root: "/trees/shop", name: "web" }, serviceKey: "native:web", serviceEntry: "app.js" }
  const endpoint = listener(5173)
  const original = Discovery.classifyListeners([endpoint], { 410: process }).contexts[0]
  const previous = [{ context: original, scheme: "http" }]
  function deleted(startTime) {
    const metadata = { ...process, cwdDeleted: true, project: {}, serviceKey: "", serviceEntry: "", startTime }
    const context = Discovery.classifyListeners([endpoint], { 410: metadata }, {}, {}, previous).contexts[0]
    return Discovery.serverFromContext(context, "http", {})
  }
  const retained = deleted(99)
  assert.equal(retained.name, "web")
  assert.equal(retained.serviceKey, "native:web")
  assert.notEqual(retained.projectRoot, Discovery.serverFromContext(original, "http", {}).projectRoot)
  assert.equal(deleted(100).serviceKey, "")
})

test("keeps multiple listeners and a fallback port despite the requested --port", () => {
  const listeners = [listener(3001), listener(5173), listener(41125)]
  const processes = { 410: { command: "vite --port 3000", cwd: "/work/app" } }
  assert.deepEqual(plain(Discovery.classifyListeners(listeners, processes).contexts).map(row => row.listener), listeners)
})

test("excludes named worker processes independently of their port flag", () => {
  const processes = { 410: { command: "nodejsWorker.js --host 127.0.0.1 --port 35729", cwd: "/work/app" } }
  assert.deepEqual(plain(Discovery.classifyListeners([listener(41523)], processes).contexts), [])
})

test("port hints parse addresses and positional ports, not unrelated numeric options", () => {
  assert.deepEqual(plain(Discovery.declaredPorts("gunicorn app:app --bind=0.0.0.0:4567 --workers 4")), [4567])
  assert.deepEqual(plain(Discovery.declaredPorts("php -S [::]:8082")), [8082])
  assert.deepEqual(plain(Discovery.declaredPorts("python -m http.server 8010 --bind 127.0.0.1")), [8010])
  assert.deepEqual(plain(Discovery.declaredPorts("custom --port 70000 --timeout 3000")), [])
})

test("debugger and database listeners are excluded unless explicitly included", () => {
  const listeners = [listener(3000), listener(9229), listener(6379)]
  const process = { command: "node --inspect app.js", cwd: "/work/app" }
  assert.deepEqual(plain(Discovery.classifyListeners(listeners, { 410: process }).contexts).map(row => row.listener.port), [3000])
  assert.deepEqual(plain(Discovery.classifyListeners(listeners, { 410: process }, {}, { 9229: true }).contexts).map(row => row.listener.port), [3000, 9229])
  assert.deepEqual(plain(Discovery.inspectorPorts("node --inspect-brk=127.0.0.1:9230 app.js")), [9230])
  assert.equal((Discovery.classifyListeners([listener(4567)], { [listener(4567).pid]: { command: "custom-server --port 4567", cwd: "/work/app" } }).contexts.length > 0), true)
})

test("TanStack Devtools helper ports are skipped without merging distinct apps", () => {
  const processes = {
    410: { command: "bun /work/web/node_modules/vite/bin/vite.js dev --port 3000 --host 0.0.0.0", cwd: "/work/web",
      project: { dependencies: ["@tanstack/react-start", "@tanstack/devtools-vite"] } },
    411: { command: "bun /work/admin/node_modules/vite/bin/vite.js dev --port 3001", cwd: "/work/admin",
      project: { dependencies: ["@tanstack/react-start", "@tanstack/devtools-vite"] } },
  }
  const listeners = [listener(3000), listener(4206),
    { ...listener(3001), pid: 411 }, { ...listener(4206), pid: 411, addresses: ["::1"] }]
  const selected = Discovery.classifyListeners(listeners, processes).contexts
  assert.deepEqual(plain(selected).map(row => row.listener.port), [3000, 3001])
  assert.deepEqual(plain(Discovery.classifyListeners(listeners, processes).diagnostics).map(row => [row.port, row.reason]),
    [[4206, "devtools"], [4206, "devtools"]])
  assert.equal(Discovery.classifyListeners(listeners, processes, {}, { 4206: true }).contexts.length, 4)
  assert.equal(Discovery.classifyListeners(listeners, processes, { 4206: true }, { 4206: true }).contexts.length, 2)
  assert.equal(Discovery.classifyListeners([listener(4206)], processes).contexts.length, 1, "a lone endpoint remains visible")
  processes[410].command = "vite --port 4206"
  assert.equal(Discovery.classifyListeners(listeners.slice(0, 2), processes).contexts.length, 2, "explicit app ports win")
  processes[410].command = "vite"
  assert.equal(Discovery.classifyListeners([listener(5173), listener(4206)], processes).contexts.length, 1, "default Vite port")
  processes[410].project.dependencies = ["@tanstack/react-start"]
  assert.equal(Discovery.classifyListeners(listeners.slice(0, 2), processes).contexts.length, 2, "Start alone does not imply Devtools")
})

test("Azure Functions worker endpoints are skipped only alongside the same host's app port", () => {
  for (const address of ["127.0.0.1", "::1"]) {
    const processes = { 410: { command: "/tools/func start --address 0.0.0.0 --port 7073", cwd: "/work/notifications" } }
    const listeners = [{ ...listener(7073), addresses: ["0.0.0.0"] }, { ...listener(36811), addresses: [address] }]
    const selected = Discovery.classifyListeners(listeners, processes).contexts
    assert.deepEqual(plain(selected).map(row => row.listener.port), [7073])
    assert.equal(Discovery.classifyListeners(listeners, processes).diagnostics[0].reason, "worker")
    assert.equal(Discovery.classifyListeners(listeners, processes, {}, { 36811: true }).contexts.length, 2)
    assert.equal(Discovery.classifyListeners([listeners[1]], processes).contexts.length, 1, "no primary endpoint, no suppression")
    assert.equal(Discovery.classifyListeners([{ ...listeners[0], pid: 411 }, listeners[1]], processes).contexts.length, 1,
      "another process's app port is not evidence")
    processes[410].command = "func start"
    assert.equal(Discovery.classifyListeners([{ ...listeners[0], port: 7071 }, listeners[1]], processes).contexts.length, 1)
    processes[410].command = "func start --port 7073 --listen-port 36811"
    assert.equal(Discovery.classifyListeners(listeners, processes).contexts.length, 2, "both explicitly declared endpoints are kept")
    processes[410].command = "node app.js --port 7073"
    assert.equal(Discovery.classifyListeners(listeners, processes).contexts.length, 2, "generic multi-port servers are unchanged")
    processes[410].command = "func start --port 7073"
    listeners[1].addresses = [address, "0.0.0.0"]
    assert.equal(Discovery.classifyListeners(listeners, processes).contexts.length, 2, "public secondary endpoints are kept")
  }
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
    plain(Discovery.classifyListeners([discordListener], { "36559": discordProcess }).contexts),
    [],
  )
})

test("ignores packaged runtime helpers without hiding real Node commands", () => {
  const genericListener = listener(6463)

  assert.equal((Discovery.classifyListeners([genericListener], { [genericListener.pid]: {
    command: "desktop-app --type=renderer --enable-node-leakage-in-renderers", cwd: "/work/app",
  } }).contexts.length > 0), false)
  assert.equal((Discovery.classifyListeners([genericListener], { [genericListener.pid]: {
    command: "/usr/bin/node custom-server.js", cwd: "/work/app",
  } }).contexts.length > 0), true)
})

test("respects ignored ports and explicit include overrides", () => {
  const generic = listener(4567)
  const process = { command: "custom-local-server", cwd: "/work/custom" }

  assert.equal((Discovery.classifyListeners([generic], { [generic.pid]: process }).contexts.length > 0), false)
  assert.equal((Discovery.classifyListeners([generic], { [generic.pid]: process } , {}, { 4567: true }).contexts.length > 0), true)
  assert.equal((Discovery.classifyListeners([generic], { [generic.pid]: process } , { 4567: true }, { 4567: true }).contexts.length > 0), false)
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
  assert.deepEqual(plain(Discovery.classifyListeners(listeners, processes, { 4567: true }, {}).diagnostics), [
    { port: 4567, process: "node", reason: "ignored" },
  ])
  assert.deepEqual(plain(Discovery.classifyListeners(listeners, processes, { 4567: true }).contexts)
    .map(context => context.listener.port), [5173, 5199])
})

test("classifies browser responses", () => {
  assert.equal(Discovery.browserResponse(200), true)
  assert.equal(Discovery.browserResponse(307), true)
  assert.equal(Discovery.browserResponse(401), true)
  assert.equal(Discovery.browserResponse(404), true)
  assert.equal(Discovery.browserResponse(400), true)
  assert.equal(Discovery.browserResponse(599), true)
  assert.equal(Discovery.browserResponse(0), false)
  assert.equal(Discovery.browserResponse(600), false)
})

test("discovers published Docker Compose HTTP ports", () => {
  const raw = [
    '["ed3fec6359f3","api-app-1","node-backend","0.0.0.0:8000->8080/tcp, [::]:8000->8080/tcp","/work/betterat/apps/api","app","api"]',
    '["f7caa08d69cb","api-db-1","postgres:18","0.0.0.0:5432->5432/tcp, [::]:5432->5432/tcp","/work/betterat/apps/api","db","api"]',
  ].join("\n")
  assert.deepEqual(plain(Discovery.classifyDockerPorts(raw).contexts), [{
    id: "docker:ed3fec6359f3:8000",
    source: "docker",
    containerId: "ed3fec6359f3",
    dependencyStates: "app unknown",
    displayName: "api / app",
    projectRoot: "/work/betterat/apps/api",
    serviceKey: 'compose:["/work/betterat/apps/api","api","app"]',
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

  assert.deepEqual(plain(Discovery.classifyDockerPorts(raw).contexts), [{
    id: "docker:b49bb7bdabef:15672",
    source: "docker",
    containerId: "b49bb7bdabef",
    dependencyStates: "queue unknown",
    displayName: "api / queue",
    projectRoot: "/work/api",
    serviceKey: 'compose:["/work/api","api","queue"]',
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

test("Compose service skips follow container replacement and ports within the same project", () => {
  function key(id, port, cwd, service, project) {
    const row = [id, "instance", "node", "0.0.0.0:" + port + "->8080/tcp", cwd, service, project]
    const context = Discovery.classifyDockerPorts(JSON.stringify(row)).contexts[0]
    return Discovery.serverFromContext(context, "http", {}).serviceKey
  }
  const original = key("first", 6006, "/work/atlas", "ui", "atlas")
  assert.ok(original)
  assert.equal(key("replacement", 6007, "/work/atlas", "ui", "atlas"), original)
  assert.notEqual(key("other", 6006, "/work/atlas", "api", "atlas"), original)
  assert.notEqual(key("other", 6006, "/trees/atlas", "ui", "atlas"), original)
  assert.equal(key("standalone", 6006, "", "", ""), "")
})

test("Docker port settings can ignore or explicitly include mappings", () => {
  const database = '["f7caa08d69cb","api-db-1","postgres:18","0.0.0.0:15432->5432/tcp","/work/api","db","api"]'
  assert.deepEqual(plain(Discovery.classifyDockerPorts(database).contexts), [])
  assert.equal(Discovery.classifyDockerPorts(database, {}, { 15432: true }).contexts.length, 1)
  assert.deepEqual(plain(Discovery.classifyDockerPorts(database, { 15432: true }, { 15432: true }).contexts), [])
})

test("expands Docker published ranges across IPv4 and IPv6 and filters each port", () => {
  const raw = JSON.stringify(["abc123def456", "web", "node", "0.0.0.0:8080-8082->8080-8082/tcp, [::]:8080-8082->8080-8082/tcp", "", "", ""])
  const contexts = plain(Discovery.classifyDockerPorts(raw).contexts)
  assert.deepEqual(contexts.map(context => context.listener.port), [8080, 8081, 8082])
  assert.ok(contexts.every(context => JSON.stringify(context.listener.addresses) === JSON.stringify(["0.0.0.0", "::"])))
  assert.deepEqual(plain(Discovery.classifyDockerPorts(raw, { 8081: true }).contexts).map(context => context.listener.port), [8080, 8082])
  const database = JSON.stringify(["abc123def456", "web", "node", "0.0.0.0:16000-16002->5431-5433/tcp", "", "", ""])
  assert.deepEqual(plain(Discovery.classifyDockerPorts(database).contexts).map(context => context.listener.port), [16000, 16002])
  assert.equal(Discovery.classifyDockerPorts(database, {}, { 16001: true }).contexts.length, 3)
})

test("Docker ranges reject malformed bounds, UDP, and unpublished ports", () => {
  for (const mapping of ["0.0.0.0:8080-8082->8080-8081/tcp", "0.0.0.0:8082-8080->8080-8082/tcp", "0.0.0.0:0-2->80-82/tcp", "0.0.0.0:65535-65536->80-81/tcp", "0.0.0.0:8080-8082->8080-8082/udp", "8080-8082/tcp"]) {
    const raw = JSON.stringify(["abc123def456", "web", "node", mapping, "", "", ""])
    assert.deepEqual(plain(Discovery.classifyDockerPorts(raw).contexts), [], mapping)
  }
  const ipv6 = JSON.stringify(["abc123def456", "web", "node", ":::8080-8082->8080-8082/tcp", "", "", ""])
  assert.equal(Discovery.classifyDockerPorts(ipv6).contexts.length, 3)
})

test("bounds large Docker ranges while preserving explicit and ordinary ports", () => {
  const raw = [
    JSON.stringify(["abc123def456", "many", "node", "0.0.0.0:3000-65000->3000-65000/tcp, [::]:3000-65000->3000-65000/tcp", "", "", ""]),
    JSON.stringify(["def123abc456", "one", "node", "0.0.0.0:8080->8080/tcp", "", "", ""]),
  ].join("\n")
  const result = Discovery.classifyDockerPorts(raw, { 3000: true }, { 65000: true })
  const contexts = plain(result.contexts)
  const range = contexts.filter(context => context.containerId === "abc123def456")
  assert.equal(result.truncated, true)
  assert.ok(range.length <= 128)
  assert.ok(range.some(context => context.listener.port === 65000))
  assert.ok(!range.some(context => context.listener.port === 3000))
  assert.ok(range.every(context => JSON.stringify(context.listener.addresses) === JSON.stringify(["0.0.0.0", "::"])))
  assert.ok(contexts.some(context => context.containerId === "def123abc456" && context.listener.port === 8080))
})

test("caps Docker candidates across many containers and reports truncation", () => {
  const raw = Array.from({ length: 1030 }, (_, index) => JSON.stringify([
    String(index), "web", "node", "0.0.0.0:8080->8080/tcp", "", "", "",
  ])).join("\n")
  const result = Discovery.classifyDockerPorts(raw)
  assert.equal(result.contexts.length, 1024)
  assert.equal(result.truncated, true)
  const smaller = Discovery.classifyDockerPorts(raw.split("\n")[0])
  assert.equal(smaller.truncated, false)
})

test("Docker truncation warning only reports omitted eligible ports", () => {
  const raw = JSON.stringify(["abc123def456", "web", "node", "0.0.0.0:3000-3127->3000-3127/tcp", "", "", ""])
  const result = Discovery.classifyDockerPorts(raw, {}, { 3127: true })
  assert.equal(result.contexts.length, 128)
  assert.equal(result.truncated, false)
})

test("manual probe plans bypass both failed and successful caches", () => {
  const contexts = [3000, 3001].map(port => ({ listener: listener(port), process: { startTime: 1 } }))
  const cache = {
    [Discovery.probeCacheKey(contexts[0])]: { scheme: "", expiresAt: 15000 },
    [Discovery.probeCacheKey(contexts[1])]: { scheme: "http", expiresAt: 60000 },
  }
  assert.equal(Discovery.probePlan(contexts, cache, 100).pending.length, 0)
  assert.deepEqual(plain(Discovery.probePlan(contexts, cache, 100, true).pending), plain(contexts))
})

test("probe cache invalidates when the probe host or preferred scheme changes", () => {
  const context = { listener: { pid: 1, port: 3000, addresses: ["127.0.0.1"] }, process: { startTime: 1, command: "node app" } }
  const cache = { [Discovery.probeCacheKey(context)]: { scheme: "http", expiresAt: 60000 } }
  assert.equal(Discovery.probePlan([context], cache, 100).pending.length, 0)
  context.listener.addresses = ["::1"]
  assert.equal(Discovery.probePlan([context], cache, 100).pending.length, 1)
  context.listener.addresses = ["127.0.0.1"]
  context.process.command = "node app --https"
  assert.equal(Discovery.probePlan([context], cache, 100).pending.length, 1)
})

test("process identity participates in stable server IDs", () => {
  const context = {
    listener: { pid: 410, port: 5173 },
    process: { startTime: 991 },
  }
  assert.equal(Discovery.contextId(context), "410:991:5173")
  context.process.startTime = 992
  assert.equal(Discovery.contextId(context), "410:992:5173")
})

test("maps out-of-order curl status lines to responding transfers, including HTTP errors", () => {
  const raw = "2\t501\n1\t000\n3\t405\n0\t204\n"
  assert.deepEqual(plain(Discovery.probeStatuses(raw)), [204, 0, 501, 405])
})

test("probes learn a quiet target without requiring any specific route", () => {
  const context = { process: { command: "node" } }
  function scan(statuses, cached, manual) {
    let probe = Discovery.firstProbe(context, cached, manual)
    const targets = []
    for (const status of statuses) {
      targets.push(probe.target)
      const result = Discovery.probeResult(probe, status)
      if (!result.retry) return { targets, cached: result }
      probe = result.retry
    }
    assert.fail("probe did not finish")
  }
  for (const [statuses, targets] of [
    [[200], ["/"]], [[301], ["/"]], [[404, 204], ["/", "/health"]],
    [[405, 405, 204], ["/", "/health", "*"]], [[429], ["/"]], [[503], ["/"]],
  ]) {
    const first = scan(statuses)
    assert.deepEqual(first.targets, targets)
    assert.deepEqual(scan([200], first.cached).targets, [targets.at(-1)])
  }
  const rejected = scan([404, 404, 400])
  assert.deepEqual(rejected.targets, ["/", "/health", "*"])
  assert.equal(rejected.cached.scheme, "http")
  assert.deepEqual(scan([404], rejected.cached).targets, ["/"])
  assert.deepEqual(scan([404, 200], rejected.cached, true).targets, ["/", "/health"])
  assert.deepEqual(scan([404, 0, 0]).cached.target, "/")
  for (const target of ["/health", "*"]) {
    const cached = { scheme: "https", target }
    const recovered = scan([0, 200], cached)
    assert.deepEqual(recovered.targets, [target, "/"])
    assert.equal(recovered.cached.scheme, "https")
    const switched = scan([0, 0, 204], cached)
    assert.deepEqual(switched.targets, [target, "/", target])
    assert.deepEqual(plain(switched.cached), { scheme: "http", target })
    const rootOnly = scan([0, 0, 0, 200], cached)
    assert.deepEqual(rootOnly.targets, [target, "/", target, "/"])
    assert.deepEqual(plain(rootOnly.cached), { scheme: "http", target: "/" })
    assert.equal(scan([0, 0, 0, 0], cached).cached.scheme, "")
  }
  assert.equal(scan([0, 0]).cached.scheme, "")
})

test("successful and failed probe caches both expire", () => {
  const contexts = [1, 2, 3, 4].map(pid => ({
    listener: { pid, port: 3000 + pid }, process: { startTime: 10 },
  }))
  const ids = contexts.map(context => Discovery.contextId(context))
  const keys = contexts.map(context => Discovery.probeCacheKey(context))
  const cache = {
    [keys[0]]: { scheme: "http", expiresAt: 101 },
    [keys[1]]: { scheme: "https", expiresAt: 100 },
    [keys[2]]: { scheme: "", expiresAt: 101 },
  }
  const plan = Discovery.probePlan(contexts, cache, 100)
  assert.deepEqual(plain(plan.schemes), { [ids[0]]: "http" })
  assert.deepEqual(plain(plan.pending), plain([contexts[1], contexts[3]]))
  assert.equal(Discovery.probePlan(contexts, cache, 101).pending.length, 4)
})
