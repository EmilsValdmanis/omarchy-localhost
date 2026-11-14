import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import vm from "node:vm"

export function loadQmlJs(file) {
  const modules = new Map()
  function load(url) {
    if (modules.has(url.href)) return modules.get(url.href)
    const scope = vm.createContext({ console })
    modules.set(url.href, scope)
    const source = readFileSync(url, "utf8")
      .replace(/^\s*\.pragma library\s*$/gm, "")
      .replace(/^\s*\.import "([^"]+)" as (\w+)\s*$/gm, (_line, path, name) => {
        scope[name] = load(new URL(path, url))
        return ""
      })
    vm.runInContext(source, scope, { filename: fileURLToPath(url) })
    return scope
  }
  return load(file instanceof URL ? file : new URL(`../../qml/${file}`, import.meta.url))
}

export const plain = value => JSON.parse(JSON.stringify(value))

export function listModel(rows = []) {
  return {
    rows: plain(rows), writes: 0, reads: 0,
    get count() { return this.rows.length },
    get(index) { this.reads++; return this.rows[index] },
    insert(index, row) { this.writes++; this.rows.splice(index, 0, plain(row)) },
    remove(index, count = 1) { this.writes++; this.rows.splice(index, count) },
    move(from, to, count = 1) {
      this.writes++
      this.rows.splice(to, 0, ...this.rows.splice(from, count))
    },
    set(index, row) { this.writes++; this.rows[index] = plain(row) },
  }
}
