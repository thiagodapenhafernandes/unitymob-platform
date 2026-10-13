import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const context = vm.createContext({ Controller: class {} })
const source = readFileSync("app/javascript/controllers/conditional_reveal_controller.js", "utf8")
vm.runInContext(source.replace(/^import .*\n/gm, "").replace("export default class", "this.Reveal = class"), context)

function panel(values, hidden = false, fields = []) {
  return { dataset: { conditionalRevealValues: values }, hidden, classList: { toggle() {} }, querySelectorAll: () => fields }
}

test("módulo herdado acompanha a troca do provedor padrão", () => {
  const controller = new context.Reveal()
  controller.kindValue = "select"
  controller.triggerTarget = { value: "" }
  controller.fallbackTrigger = { value: "openai" }
  assert.equal(controller.panelMatches(panel("openai")), true)
  controller.fallbackTrigger.value = "muse"
  assert.equal(controller.panelMatches(panel("openai")), false)
  assert.equal(controller.panelMatches(panel("muse")), true)
  controller.triggerTarget.value = "openai"
  assert.equal(controller.panelMatches(panel("openai")), true)
})

test("revelar provedor mantém campos personalizados ocultos desabilitados e não obrigatórios", () => {
  const controller = new context.Reveal()
  const hiddenParent = {}
  const field = { dataset: { conditionalRequired: "true" }, closest: () => hiddenParent }
  const ordinary = { dataset: {}, closest: () => null }
  controller.setPanelState(panel("openai", true, [field, ordinary]), true)
  assert.equal(field.disabled, true)
  assert.equal(field.required, false)
  assert.equal(ordinary.disabled, false)
})

test("painel aninhado nunca habilita campos de um provedor oculto", () => {
  const controller = new context.Reveal()
  const field = { dataset: {}, closest: () => ({ hidden: true }) }
  controller.setPanelState(panel("__custom__", false, [field]), true)
  assert.equal(field.disabled, true)
})

test("opções explicitamente indisponíveis continuam desabilitadas ao revelar o painel", () => {
  const controller = new context.Reveal()
  const field = { dataset: {}, closest: () => null, getAttribute: () => "true" }
  controller.setPanelState(panel("account", false, [field]), true)
  assert.equal(field.disabled, true)
})
