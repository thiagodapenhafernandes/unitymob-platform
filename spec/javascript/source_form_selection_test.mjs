import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const context = vm.createContext({ Controller: class {} })
const source = readFileSync("app/javascript/controllers/meta_rules_controller.js", "utf8")
vm.runInContext(source.replace(/^import .*\n/gm, "").replace("export default class", "this.Selection = class"), context)

function selection(parents, allParents, forms = []) {
  const controller = new context.Selection()
  controller.structureValue = { a: { name: "A", forms: [{ id: "1", name: "Form 1" }] }, b: { name: "B", forms: [{ id: "2", name: "Form 2" }] } }
  controller.allParentsWhenEmptyValue = allParents
  controller.selectedPageIds = () => parents
  controller.selectedFormIds = () => forms
  controller.autoSyncEnabled = () => false
  controller.syncAutoSummary = () => {}
  const options = new Map(), selected = new Set()
  controller.formSelectInstance = {
    clear: () => selected.clear(), clearOptions: () => options.clear(),
    addOption: (option) => options.set(option.value, option.text), addItem: (id) => selected.add(id),
    refreshOptions() {}, refreshItems() {}
  }
  controller.refreshFormsFromSelectedPages()
  return { options, selected }
}

test("LinkedIn vazio mostra os formulários de todas as campanhas", () => {
  assert.deepEqual([...selection([], true).options.keys()], ["1", "2"])
})
test("Meta mantém a exigência atual de selecionar páginas", () => {
  assert.equal(selection([], false).options.size, 0)
})
test("a cascata preserva escolhas válidas e remove formulários de campanhas desmarcadas", () => {
  const result = selection(["b"], true, ["1", "2"])
  assert.deepEqual([...result.options.keys()], ["2"])
  assert.deepEqual([...result.selected], ["2"])
})
