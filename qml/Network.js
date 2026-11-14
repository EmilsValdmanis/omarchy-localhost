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

function parseLanInterfaces(addressRaw) {
  var interfaces = []
  try {
    var addresses = JSON.parse(String(addressRaw || "[]"))
    if (!Array.isArray(addresses)) return interfaces
    function addAddress(ip, device, subnet) {
      if (ipv4Number(ip) < 0 || isLoopback(ip) || isUnspecified(ip) || isLinkLocal(ip) || device === "lo" || !device) return
      for (var i = 0; i < interfaces.length; i++)
        if (interfaces[i].ip === ip && interfaces[i].interfaceName === device) return
      interfaces.push({ ip: ip, interfaceName: device, subnet: subnet })
    }
    for (var addressIndex = 0; addressIndex < addresses.length; addressIndex++) {
      var entry = addresses[addressIndex]
      var info = entry.addr_info || []
      for (var infoIndex = 0; infoIndex < info.length; infoIndex++) {
        var address = info[infoIndex]
        if (address.family !== "inet" || address.scope !== "global") continue
        var prefix = Number(address.prefixlen)
        var ip = String(address.local || "")
        var size = Math.pow(2, 32 - prefix)
        var network = Math.floor(ipv4Number(ip) / size) * size
        var octets = []
        for (var octet = 3; octet >= 0; octet--)
          octets.push(Math.floor(network / Math.pow(256, octet)) % 256)
        addAddress(ip, String(entry.ifname || ""),
          Number.isInteger(prefix) && prefix >= 1 && prefix <= 32 ? octets.join(".") + "/" + prefix : "")
      }
    }
  } catch (exception) {}
  return interfaces
}

function parseLanRoute(raw, interfaces, selectedInterface) {
  var empty = { ip: "", interfaceName: "", subnet: "" }
  var selected = String(selectedInterface || "").trim()
  try {
    var routes = JSON.parse(String(raw || "[]"))
    if (!Array.isArray(routes)) return empty
    var defaults = routes.filter(function(route) { return route.dst === "default" })
    defaults.sort(function(a, b) { return Number(a.metric || 0) - Number(b.metric || 0) })
    if (selected) defaults = [{ dev: selected }]
    for (var index = 0; index < defaults.length; index++) {
      var route = defaults[index]
      var source = String(route.prefsrc || route.src || "")
      for (var i = 0; i < interfaces.length; i++) {
        if (interfaces[i].interfaceName === route.dev && (!source || interfaces[i].ip === source))
          return interfaces[i]
      }
    }
    // An explicit selection or an unresolved default never falls back to Docker.
    if (selected || defaults.length) return empty
    for (var fallback = 0; fallback < interfaces.length; fallback++)
      if (!/^(?:docker|br-|veth|virbr|cni|flannel|podman)/.test(interfaces[fallback].interfaceName))
        return interfaces[fallback]
  } catch (exception) {}
  return empty
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

