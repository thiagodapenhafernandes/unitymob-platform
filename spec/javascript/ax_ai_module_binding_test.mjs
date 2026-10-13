import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"
const context = vm.createContext({ Controller: class {} })
vm.runInContext(readFileSync("app/javascript/controllers/ax_ai_module_binding_controller.js", "utf8").replace(/^import .*\n/gm, "").replace("export default class", "this.Binding = class"), context)
function binding() {
  const c = new context.Binding()
  const fields = { "#ai_provider": { value: "openai" }, "#oa": { value: "gpt-saved" }, "#oaCustom": { value: "gpt-custom" }, "#meta": { value: "__automatic__" }, "#metaCustom": { value: "" } }
  c.form = { querySelector: selector => fields[selector] }
  c.presetsValue = { openai: { label: "OpenAI", modelId: "oa", customId: "oaCustom", fallback: "gpt-default" }, muse: { label: "Meta Muse", modelId: "meta", customId: "metaCustom", fallback: "muse-default" } }
  c.exceptionTarget = { checked: false }
  c.providerTarget = { value: "openai" }
  c.modelTargets = [{ dataset: { provider: "openai" }, value: "gpt-exception" }, { dataset: { provider: "muse" }, value: "" }]
  c.customTargets = [{ dataset: { provider: "openai" }, value: "gpt-manual" }]
  c.summaryTarget = {}; c.statusTarget = {}
  return { c, fields }
}
test("herança acompanha provedor e modelo do preset sem salvar", () => {
  const { c, fields } = binding()
  c.sync(); assert.equal(c.summaryTarget.textContent, "OpenAI · gpt-saved")
  fields["#oa"].value = "__custom__"
  c.sync(); assert.equal(c.summaryTarget.textContent, "OpenAI · gpt-custom")
  fields["#ai_provider"].value = "muse"
  c.sync(); assert.equal(c.summaryTarget.textContent, "Meta Muse · muse-default")
})
test("exceção permanece independente e desativá-la volta ao preset", () => {
  const { c, fields } = binding()
  c.exceptionTarget.checked = true; fields["#ai_provider"].value = "muse"
  c.sync(); assert.equal(c.summaryTarget.textContent, "OpenAI · gpt-exception")
  c.modelTargets[0].value = "__custom__"
  c.sync(); assert.equal(c.summaryTarget.textContent, "OpenAI · gpt-manual")
  c.exceptionTarget.checked = false
  c.sync(); assert.equal(c.summaryTarget.textContent, "Meta Muse · muse-default")
})
