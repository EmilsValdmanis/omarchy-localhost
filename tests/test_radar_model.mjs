import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"
import vm from "node:vm"

const source = readFileSync(new URL("../RadarModel.js", import.meta.url), "utf8")
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

test("extracts declared ports", () => {
  assert.deepEqual(plain(radar.declaredPorts("vite --port 3000 --listen-port=4000 -p5000")), [3000, 4000, 5000])
})

test("keeps an explicit server port and drops helper listeners", () => {
  const listeners = [listener(3000), listener(33945), listener(41125)]
  assert.deepEqual(plain(radar.primaryListeners(listeners, "vite --port 3000")), [listeners[0]])
})

test("drops a worker listener whose port flag names its parent", () => {
  assert.deepEqual(
    plain(radar.primaryListeners([listener(41523)], "nodejsWorker.js --host 127.0.0.1 --port 35729")),
    [],
  )
})

test("prefers a conventional port without an explicit flag", () => {
  const listeners = [listener(46869), listener(5173)]
  assert.deepEqual(plain(radar.primaryListeners(listeners, "vite")), [listeners[1]])
})

test("detects common localhost frameworks", () => {
  const cases = [
    ["node node_modules/.bin/next dev", "next"],
    ["node node_modules/.bin/vue-cli-service serve", "vue"],
    ["bun run dev", "bun"],
    ["python -m uvicorn app:app", "fastapi"],
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

test("classifies browser responses", () => {
  assert.equal(radar.browserResponse(200, "text/html; charset=utf-8"), true)
  assert.equal(radar.browserResponse(307, ""), true)
  assert.equal(radar.browserResponse(401, "application/json"), true)
  assert.equal(radar.browserResponse(404, "text/html"), true)
  assert.equal(radar.browserResponse(400, "text/plain"), true)
  assert.equal(radar.browserResponse(404, ""), true)
  assert.equal(radar.browserResponse(0, ""), false)
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

test("recognizes exact and broader UFW LAN rules", () => {
  const rules = [
    "-A ufw-user-input -i enp5s0 -p tcp -s 192.168.0.0/24 --dport 3000 -j ACCEPT",
    "-A ufw-user-input -p tcp -s 10.0.0.0/8 -m multiport --dports 3001:3003 -j ACCEPT",
  ].join("\n")
  assert.equal(radar.ufwAllowsPort(rules, "enp5s0", "192.168.0.0/24", 3000), true)
  assert.equal(radar.ufwAllowsPort(rules, "wlan0", "10.12.0.0/24", 3002), true)
  assert.equal(radar.ufwAllowsPort(rules, "enp5s0", "192.168.0.0/24", 4000), false)
})

test("parses qrencode ASCII output", () => {
  assert.deepEqual(plain(radar.parseQrAscii("######\n##  ##\n######\n")), {
    size: 3,
    rows: ["111", "101", "111"],
  })
})
