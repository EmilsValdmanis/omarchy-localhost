function sync(model, entries, key, equal) {
  var incoming = Object.create(null)
  var rows = []
  for (var i = 0; i < entries.length; i++) {
    var row = entries[i]
    if (!row[key] || incoming[row[key]]) continue
    incoming[row[key]] = true
    rows.push(row)
  }
  var changed = false
  for (var old = model.count - 1; old >= 0; old--) {
    if (!incoming[model.get(old)[key]]) {
      model.remove(old)
      changed = true
    }
  }
  for (var target = 0; target < rows.length; target++) {
    var next = rows[target]
    if (target >= model.count || model.get(target)[key] !== next[key]) {
      var current = target + 1
      while (current < model.count && model.get(current)[key] !== next[key]) current++
      if (current < model.count) model.move(current, target, 1)
      else model.insert(target, next)
      changed = true
    }
    if (!equal(model.get(target), next)) {
      model.set(target, next)
      changed = true
    }
  }
  return changed
}
