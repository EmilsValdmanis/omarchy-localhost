import assert from "node:assert/strict"
import test from "node:test"
import { loadQmlJs, plain } from "./support/qml_js.mjs"

const Firewall = loadQmlJs("Firewall.js")

test("recognizes exact and broader UFW LAN rules", () => {
  const rules = [
    "-A ufw-user-input -i enp5s0 -p tcp -s 192.168.0.0/24 --dport 3000 -j ACCEPT",
    "-A ufw-user-input -p tcp -s 10.0.0.0/8 -m multiport --dports 3001:3003 -j ACCEPT",
  ].join("\n")
  assert.equal(Firewall.ufwAllowsPort(rules, "enp5s0", "192.168.0.0/24", 3000), true)
  assert.equal(Firewall.ufwAllowsPort(rules, "wlan0", "10.12.0.0/24", 3002), true)
  assert.equal(Firewall.ufwAllowsPort(rules, "enp5s0", "192.168.0.0/24", 4000), false)
})

test("UFW access checks respect earlier denies and unknown restrictions", () => {
  const allow = "-A ufw-user-input -p tcp --dport 3000 -j ACCEPT"
  const check = rules => Firewall.ufwAllowsPort(rules, "wlan0", "192.168.1.0/24", 3000)
  assert.equal(check(`-A ufw-user-input -p tcp -s 192.168.1.42 --dport 3000 -j DROP\n${allow}`), false)
  assert.equal(check(`-A ufw-user-input -p tcp -s 10.0.0.0/8 --dport 3000 -j DROP\n${allow}`), true)
  assert.equal(check(`-A ufw-user-input -p udp --dport 3000 -j DROP\n${allow}`), true)
  assert.equal(check(`-A ufw-user-input -i wl+ -p tcp --dport 3000 -j DROP\n${allow}`), false)
  assert.equal(check(`-A ufw-user-input -i en+ -p tcp --dport 3000 -j DROP\n${allow}`), true)
  assert.equal(check(`-A ufw-user-input -p all -j DROP\n${allow}`), false)
  assert.equal(check("-A ufw-user-input -p tcp -d 192.168.2.1 --dport 3000 -j ACCEPT"), false)
  assert.equal(check("-A ufw-user-input ! -s 192.168.1.0/24 -p tcp --dport 3000 -j ACCEPT"), false)
  assert.equal(check(`-A ufw-user-input -p tcp --dport 3000 -j ufw-user-limit\n${allow}`), false)
})

test("unrelated UFW rate-limit rules do not hide later LAN allow rules", () => {
  const allow = "-A ufw-user-input -i wlan0 -p tcp -s 192.168.1.0/24 --dport 3000 -j ACCEPT"
  const limitSteps = [
    "-m conntrack --ctstate NEW -m recent --set",
    "-m conntrack --ctstate NEW -m recent --update --seconds 30 --hitcount 6 -j ufw-user-limit",
    "-j ufw-user-limit-accept",
  ]
  for (const match of [
    "-p tcp --dport 22",
    "-i eth0 -p tcp --dport 3000",
    "-p tcp -s 10.0.0.0/8 --dport 3000",
  ]) {
    const rules = limitSteps.map(step => `-A ufw-user-input ${match} ${step}`).join("\n")
    assert.equal(Firewall.ufwAllowsPort(`${rules}\n${allow}`, "wlan0", "192.168.1.0/24", 3000), true, match)
    for (const step of limitSteps)
      assert.equal(Firewall.ufwAllowsPort(`-A ufw-user-input ${match} ${step}\n${allow}`,
        "wlan0", "192.168.1.0/24", 3000), true, `${match} ${step}`)
  }
})

test("LAN authorization and removal scope the same managed TCP rule", () => {
  const rule = { interfaceName: "wlan0", subnet: "192.168.1.0/24", port: 3000 }
  assert.deepEqual(plain(Firewall.commandFor(rule, false)), [
    "pkexec", "/usr/bin/ufw", "allow", "in", "on", "wlan0", "from", "192.168.1.0/24",
    "to", "any", "port", "3000", "proto", "tcp", "comment", "omarchy-localhost",
  ])
  assert.deepEqual(plain(Firewall.commandFor(rule, true)), [
    "pkexec", "/usr/bin/ufw", "--force", "delete", "allow", "in", "on", "wlan0", "from", "192.168.1.0/24",
    "to", "any", "port", "3000", "proto", "tcp", "comment", "omarchy-localhost",
  ])
})

test("firewall status distinguishes inactive, unreadable and failed checks", () => {
  assert.deepEqual(plain(Firewall.parseStatus("inactive\n", 0)), {
    active: false, rules: "", unreadable: false, managedRules: [],
  })
  assert.equal(Firewall.parseStatus("active\nunreadable\n", 0).unreadable, true)
  assert.equal(Firewall.parseStatus("", 1).unreadable, true)
  assert.equal(Firewall.parseStatus("inactive\n", 1).unreadable, true)
  assert.equal(Firewall.parseStatus("active\n-A ufw-user-input -j ACCEPT\n", 0).active, true)
})

test("matching UFW rate-limit rules still prevent assuming unrestricted LAN access", () => {
  const allow = "-A ufw-user-input -p tcp --dport 3000 -j ACCEPT"
  for (const step of [
    "-m conntrack --ctstate NEW -m recent --set",
    "-m conntrack --ctstate NEW -m recent --update --seconds 30 --hitcount 6 -j ufw-user-limit",
    "-j ufw-user-limit-accept",
  ]) {
    assert.equal(Firewall.ufwAllowsPort(`-A ufw-user-input -p tcp --dport 3000 ${step}\n${allow}`,
      "wlan0", "192.168.1.0/24", 3000), false, step)
  }
})

test("finds only Localhost-managed UFW rules", () => {
  const rules = [
    "### tuple ### allow tcp 3000 0.0.0.0/0 any 192.168.0.0/24 in_enp5s0 comment=6f6d61726368792d6c6f63616c686f7374",
    "-A ufw-user-input -i enp5s0 -p tcp --dport 3000 -s 192.168.0.0/24 -j ACCEPT",
    "### tuple ### allow tcp 8000 0.0.0.0/0 any 192.168.0.0/24 in_enp5s0 comment=6f74686572",
  ].join("\n")
  assert.deepEqual(plain(Firewall.parseManagedUfwRules(rules)), [{
    id: "enp5s0:192.168.0.0/24:3000",
    port: 3000,
    interfaceName: "enp5s0",
    subnet: "192.168.0.0/24",
  }])
})
