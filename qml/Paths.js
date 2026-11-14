function basename(path) {
  var value = String(path || "").replace(/\/+$/, "")
  var slash = value.lastIndexOf("/")
  return slash === -1 ? value : value.slice(slash + 1)
}
