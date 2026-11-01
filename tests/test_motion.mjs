import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"
import vm from "node:vm"

const motion = vm.createContext({})
vm.runInContext(readFileSync(new URL("../qml/Motion.js", import.meta.url), "utf8"), motion)

test("animation duration supports old shells and respects newer motion preferences", () => {
  assert.equal(motion.duration({}, 160), 160)
  assert.equal(motion.duration({ duration: value => value * 2 }, 160), 320)
  assert.equal(motion.duration({ reduceMotion: true, duration: value => value * 2 }, 160), 0)
})
