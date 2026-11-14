import assert from "node:assert/strict"
import test from "node:test"

import { loadQmlJs } from "./support/qml_js.mjs"

const motion = loadQmlJs("Motion.js")

test("animation duration supports old shells and respects newer motion preferences", () => {
  assert.equal(motion.duration({}, 160), 160)
  assert.equal(motion.duration({ duration: value => value * 2 }, 160), 320)
  assert.equal(motion.duration({ reduceMotion: true, duration: value => value * 2 }, 160), 0)
})
