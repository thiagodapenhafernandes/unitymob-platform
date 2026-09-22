import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

function setup() {
  class Input { constructor(file, multiple = false) { this.type = "file"; this.files = file ? [file] : []; this.multiple = multiple } }
  const revoked = []
  const frame = { children: ["EMPTY"], get childNodes() { return this.children }, replaceChildren(...nodes) { this.children = nodes } }
  const context = vm.createContext({
    Controller: class {}, HTMLInputElement: Input,
    URL: { createObjectURL: () => "blob:x", revokeObjectURL: (url) => revoked.push(url) },
    document: { createElement: () => ({}) }
  })
  vm.runInContext(readFileSync("app/javascript/controllers/ax_media_preview_controller.js", "utf8").replace(/^import .*\n/, "").replace("export default class", "this.C = class"), context)
  const controller = new context.C()
  controller.element = { querySelector: () => frame }
  return { controller, frame, Input, revoked }
}

test("mostra a imagem escolhida e volta ao estado anterior ao limpar", () => {
  const { controller, frame, Input, revoked } = setup()
  controller.pick({ target: new Input({ type: "image/png" }) })
  assert.equal(frame.children.length, 1)
  assert.equal(frame.children[0].src, "blob:x")
  controller.pick({ target: new Input(null) })
  assert.equal(frame.children[0], "EMPTY")
  assert.deepEqual([...revoked], ["blob:x"])
})

test("ignora arquivo que não é imagem e campo múltiplo", () => {
  const { controller, frame, Input } = setup()
  controller.pick({ target: new Input({ type: "application/pdf" }) })
  controller.pick({ target: new Input({ type: "image/png" }, true) })
  assert.equal(frame.children[0], "EMPTY")
})
