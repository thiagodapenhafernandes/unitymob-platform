import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"
const context = vm.createContext({ Controller: class {} })
vm.runInContext(readFileSync("app/javascript/controllers/ax_textarea_expand_controller.js", "utf8").replace(/^import .*\n/gm, "").replace("export default class", "this.Editor = class"), context)
test("expandir e recolher preserva o texto e informa o estado acessível", () => {
  const c = new context.Editor()
  c.compactRowsValue = 8; c.expandedRowsValue = 20
  c.fieldTarget = { rows: 8, value: "Texto salvo\\ncom instruções" }
  const attributes = { "aria-expanded": "false" }
  c.buttonTarget = { getAttribute: name => attributes[name], setAttribute: (name,value) => attributes[name] = value }
  c.toggle(); assert.equal(c.fieldTarget.rows,20); assert.equal(attributes['aria-expanded'],'true'); assert.equal(c.buttonTarget.textContent,'Recolher editor')
  c.toggle(); assert.equal(c.fieldTarget.rows,8); assert.equal(attributes['aria-expanded'],'false'); assert.equal(c.fieldTarget.value,"Texto salvo\\ncom instruções")
})
