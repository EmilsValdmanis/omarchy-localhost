.import "Network.js" as Network

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
  var requested = Network.cidrBounds(subnet)
  if (!requested) return false
  var lines = String(raw || "").split(/\r?\n/)
  for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
    var line = lines[lineIndex].trim()
    if (line.indexOf("-A ufw-user-input ") !== 0) continue
    var fields = line.split(/\s+/)
    var options = {}
    var understood = true
    for (var fieldIndex = 2; fieldIndex < fields.length; fieldIndex++) {
      var field = fields[fieldIndex]
      // Negation changes the meaning of the next match; do not infer access.
      if (field === "!" || field.charAt(0) !== "-") return false
      // UFW rate limits use valueless recent flags. Keep parsing so an
      // unrelated port/interface/subnet can rule this line out, but never
      // infer unrestricted access from a rule containing these matches.
      if (field === "--set" || field === "--update") {
        understood = false
        continue
      }
      var next = fields[fieldIndex + 1]
      if (!next || next.charAt(0) === "-" || next === "!") return false
      if (field === "-m") {
        if (next !== "tcp" && next !== "multiport") understood = false
      } else if (["-p", "-i", "-s", "--dport", "--dports", "-j"].indexOf(field) !== -1) {
        if (options[field] !== undefined) return false
        options[field] = next
      } else understood = false
      fieldIndex++
    }

    var protocol = String(options["-p"] || "all").toLowerCase()
    if (protocol === "udp" || protocol === "icmp" || (/^\d+$/.test(protocol) && protocol !== "0" && protocol !== "6")) continue
    if (["all", "tcp", "0", "6"].indexOf(protocol) === -1) understood = false
    if (options["-i"]) {
      var iface = options["-i"]
      if (iface.charAt(iface.length - 1) === "+") {
        if (String(interfaceName).indexOf(iface.slice(0, -1)) !== 0) continue
      } else if (iface !== interfaceName) continue
    }
    var source = options["-s"] ? Network.cidrBounds(options["-s"]) : { first: 0, last: 4294967295 }
    if (!source) return false
    if (source.last < requested.first || source.first > requested.last) continue
    var portSpec = options["--dport"] || options["--dports"]
    if (portSpec && !/^\d+(?:[:-]\d+)?(?:,\d+(?:[:-]\d+)?)*$/.test(portSpec)) return false
    if (portSpec && !portSpecAllows(portSpec, port)) continue
    // A preceding non-ACCEPT rule may deny even part of the requested subnet.
    if (options["-j"] !== "ACCEPT") return false
    if (understood && source.first <= requested.first && source.last >= requested.last) return true
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

function parseManagedUfwRules(raw) {
  var expected = MANAGED_COMMENT
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

var MANAGED_COMMENT = "omarchy-localhost"
var statusCommand = [
  "bash", "-c",
  "if ! command -v ufw >/dev/null || ! systemctl is-active --quiet ufw; then echo inactive; exit 0; fi; echo active; cat /etc/ufw/user.rules 2>/dev/null || echo unreadable"
]

function parseStatus(raw, exitCode) {
  var text = String(raw || "")
  var active = exitCode === 0 && text.indexOf("active\n") === 0
  var rules = active ? text.slice(7) : ""
  var unreadable = exitCode !== 0 || rules.split(/\r?\n/).indexOf("unreadable") !== -1
  return { active: active, rules: rules, unreadable: unreadable,
    managedRules: active && !unreadable ? parseManagedUfwRules(rules) : [] }
}

function commandFor(rule, remove) {
  return ["pkexec", "/usr/bin/ufw"].concat(remove ? ["--force", "delete"] : [], [
    "allow", "in", "on", String(rule.interfaceName), "from", String(rule.subnet),
    "to", "any", "port", String(rule.port), "proto", "tcp", "comment", MANAGED_COMMENT
  ])
}
