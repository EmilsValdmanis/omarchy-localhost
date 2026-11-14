import assert from "node:assert/strict"
import test from "node:test"
import { loadQmlJs, plain } from "./support/qml_js.mjs"

const Qr = loadQmlJs("Qr.js")

test("parses qrencode ASCII output", () => {
  assert.deepEqual(plain(Qr.parseQrAscii("######\n##  ##\n######\n")), {
    size: 3,
    rows: ["111", "101", "111"],
  })
})
