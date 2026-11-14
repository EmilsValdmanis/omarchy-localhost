import assert from "node:assert/strict"
import test from "node:test"
import { loadQmlJs, plain } from "./support/qml_js.mjs"

const Discovery = loadQmlJs("Discovery.js")
const Network = loadQmlJs("Network.js")
const Servers = loadQmlJs("Servers.js")

function listener(port) {
  return { pid: 410, port, process: "node", addresses: ["127.0.0.1"] }
}

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

test("detects LAN reachability", () => {
  assert.equal(Network.lanHostFor(["0.0.0.0"], "192.168.1.42"), "192.168.1.42")
  assert.equal(Network.lanHostFor(["127.0.0.1", "::1"], "192.168.1.42"), "")
  assert.equal(Network.lanHostFor(["10.0.0.8"], "192.168.1.42"), "10.0.0.8")
})

test("finds the active interface and connected LAN subnet", () => {
  const routes = JSON.stringify([
    { dst: "default", dev: "enp5s0", prefsrc: "192.168.0.119" },
    { dst: "172.18.0.0/16", dev: "docker0", scope: "link", prefsrc: "172.18.0.1" },
    { dst: "192.168.0.0/24", dev: "enp5s0", scope: "link", prefsrc: "192.168.0.119" },
  ])
  assert.deepEqual(plain(Network.parseLanRoute(routes, Network.parseLanInterfaces(JSON.stringify([
    { ifname: "enp5s0", addr_info: [{ family: "inet", scope: "global", local: "192.168.0.119", prefixlen: 24 }] }
  ])))), {
    ip: "192.168.0.119",
    interfaceName: "enp5s0",
    subnet: "192.168.0.0/24",
  })
})

test("default route without prefsrc resolves its interface address instead of Docker", () => {
  const expected = { ip: "192.168.1.42", interfaceName: "wlan0", subnet: "192.168.1.0/24" }
  assert.deepEqual(plain(Network.parseLanRoute(multiRoutes, Network.parseLanInterfaces(multiAddresses))), expected)
  const defaultOnly = JSON.stringify([{ dst: "default", dev: "wlan0" }])
  assert.deepEqual(plain(Network.parseLanRoute(defaultOnly, Network.parseLanInterfaces(multiAddresses))), expected)
  assert.equal(Network.parseLanRoute(defaultOnly, []).ip, "")
  assert.equal(Network.parseLanRoute(multiRoutes, []).ip, "", "inactive interface addresses override stale route sources")
})

test("LAN interface selection is explicit and missing interfaces never fall back", () => {
  assert.deepEqual(plain(Network.parseLanRoute(multiRoutes, Network.parseLanInterfaces(multiAddresses), "enp5s0")), {
    ip: "10.0.0.8", interfaceName: "enp5s0", subnet: "10.0.0.0/24",
  })
  assert.equal(Network.parseLanRoute(multiRoutes, Network.parseLanInterfaces(multiAddresses), "absent").ip, "")
  assert.equal(Network.parseLanRoute("[]", Network.parseLanInterfaces(multiAddresses)).interfaceName, "wlan0")
  assert.equal(Network.parseLanRoute("[]", Network.parseLanInterfaces(multiAddresses), "docker0").interfaceName, "docker0")
})

test("lowest metric default is preferred and malformed network data is ignored", () => {
  const routes = JSON.stringify([
    { dst: "default", dev: "wlan0", metric: 600 }, { dst: "default", dev: "enp5s0", metric: 100 },
  ])
  assert.equal(Network.parseLanRoute(routes, Network.parseLanInterfaces(multiAddresses)).ip, "10.0.0.8")
  for (const raw of ["invalid", "{}", "null"])
    assert.equal(Network.parseLanRoute(raw, Network.parseLanInterfaces(multiAddresses)).ip, "")
})

test("each server retains the interface and subnet belonging to its LAN URL", () => {
  const interfaces = Network.parseLanInterfaces(multiAddresses)
  const route = Network.parseLanRoute(multiRoutes, Network.parseLanInterfaces(multiAddresses))
  const context = { listener: listener(3000), process: { cwd: "/work", startTime: 1 }, framework: { name: "Node" } }
  context.listener.addresses = ["10.0.0.8"]
  const server = Servers.normalizeServer(Discovery.serverFromContext(context, "http", route, interfaces))
  assert.equal(server.lanUrl, "http://10.0.0.8:3000")
  assert.equal(server.lanInterface, "enp5s0")
  assert.equal(server.lanSubnet, "10.0.0.0/24")
  context.listener.addresses = ["0.0.0.0"]
  const wildcard = Discovery.serverFromContext(context, "http", route, interfaces)
  assert.equal(wildcard.lanInterface, "wlan0")
  assert.equal(wildcard.lanSubnet, "192.168.1.0/24")
  context.listener.addresses = ["10.99.0.8"]
  assert.equal(Discovery.serverFromContext(context, "http", route, interfaces).lanInterface, "")
})
