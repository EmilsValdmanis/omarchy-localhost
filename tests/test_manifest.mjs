import assert from "node:assert/strict"
import { lstatSync, readFileSync, readdirSync } from "node:fs"
import { join, normalize, resolve } from "node:path"
import test from "node:test"
import { fileURLToPath } from "node:url"

const root = fileURLToPath(new URL("..", import.meta.url))
const manifest = JSON.parse(readFileSync(join(root, "manifest.json"), "utf8"))
const entryPointKeys = {
  "bar-widget": "barWidget",
  panel: "panel",
  overlay: "overlay",
  menu: "menu",
  service: "service",
  bar: "bar",
}

test("manifest contains publishable marketplace metadata", () => {
  assert.equal(manifest.schemaVersion, 1)
  assert.match(manifest.id, /^(?!omarchy\.)[a-z0-9]+(?:[.-][a-z0-9]+)+$/)
  assert.ok(typeof manifest.name === "string" && manifest.name.trim())
  assert.ok(typeof manifest.version === "string" && manifest.version.length <= 64)
  assert.ok(typeof manifest.author === "string" && manifest.author.trim())
  assert.ok(typeof manifest.description === "string" && manifest.description.trim())
  assert.ok(Array.isArray(manifest.kinds) && manifest.kinds.length > 0)
  assert.ok(manifest.entryPoints && typeof manifest.entryPoints === "object")
  assert.doesNotThrow(() => readFileSync(join(root, "README.md")))
  assert.doesNotThrow(() => readFileSync(join(root, "LICENSE")))
})

test("manifest kinds have safe, existing entry points", () => {
  for (const kind of manifest.kinds) {
    const key = entryPointKeys[kind]
    assert.ok(key, `unsupported plugin kind: ${kind}`)
    const entryPoint = manifest.entryPoints[key]
    assert.ok(typeof entryPoint === "string" && entryPoint.endsWith(".qml"), `${kind} entry point`)
    assert.equal(normalize(entryPoint), entryPoint, `${entryPoint} must be normalized`)
    assert.ok(!entryPoint.startsWith("/") && !entryPoint.startsWith(".."), `${entryPoint} must be relative`)
    assert.doesNotThrow(() => readFileSync(resolve(root, entryPoint)), `${entryPoint} must exist`)
  }
})

test("bar settings have matching defaults and schema entries", () => {
  const widget = manifest.barWidget
  assert.ok(widget && widget.defaults && Array.isArray(widget.schema))
  const schema = Object.fromEntries(widget.schema.map((entry) => [entry.key, entry]))
  for (const [key, value] of Object.entries(widget.defaults)) {
    assert.ok(schema[key], `missing schema for ${key}`)
    assert.deepEqual(schema[key].defaultValue, value, `${key} default must match`)
  }
  assert.equal(schema.refreshIntervalSec.min, 1)
  assert.equal(schema.refreshIntervalSec.max, 30)
  assert.equal(schema.authorizeFirewallForQr.type, "boolean")
  assert.equal(schema.ignoredPorts.type, "string")
  assert.equal(schema.alwaysIncludePorts.type, "string")
})

test("plugin folder contains no symlinks", () => {
  function inspect(directory) {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      if (entry.name === ".git") continue
      const path = join(directory, entry.name)
      assert.equal(lstatSync(path).isSymbolicLink(), false, `${path} must not be a symlink`)
      if (entry.isDirectory()) inspect(path)
    }
  }

  inspect(root)
})
