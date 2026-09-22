import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

function builder(catalog, definition) {
  const context = vm.createContext({ Controller: class {}, window: {}, document: {}, JSON, Object, Array, String, Boolean, Set })
  vm.runInContext(
    readFileSync("app/javascript/controllers/automation_workflow_builder_controller.js", "utf8")
      .replace(/^import .*\n/, "")
      .replace("export default class", "this.Builder = class"),
    context
  )
  const controller = new context.Builder()
  controller.catalog = catalog
  controller.definition = definition
  return controller
}

const triggers = {
  lead_created: "Lead criado", whatsapp_received: "WhatsApp recebido", whatsapp_flow_button: "Clique em botão",
  whatsapp_campaign_started: "Disparo iniciado", proposal_viewed: "Proposta vista", scheduled_routine: "Rotina"
}
const scaffold = {
  nodes: [
    { id: "entry_1", type: "entry", config: {} },
    { id: "response_condition_1", type: "response_condition", config: { button_text: "Comprar" } },
    { id: "action_1", type: "action", config: {} }
  ],
  edges: [{ from: "entry_1", to: "response_condition_1" }, { from: "response_condition_1", to: "action_1" }]
}
const catalog = {
  triggers,
  whatsapp_senders: [{ id: 1, label: "A", phone: "1", waba_id: "wa" }, { id: 2, label: "B", phone: "2", waba_id: "wb" }],
  whatsapp_flow_templates: [
    { id: 10, name: "menu_a", waba_id: "wa", scaffold },
    { id: 20, name: "menu_b", waba_id: "wb", scaffold }
  ]
}
const entry = () => ({ id: "entry_99", type: "entry", config: { trigger: "lead_created", entry_policy: "future" } })
const fresh = () => { const e = entry(); return { e, b: builder(catalog, { nodes: [e], edges: [] }) } }

test("o tipo de início é derivado do gatilho e trocar de tipo escolhe o evento do novo tipo", () => {
  const { e, b } = fresh()
  assert.equal(b.startCategoryOf("lead_created"), "lead")
  assert.equal(b.startCategoryOf("whatsapp_campaign_started"), "whatsapp")
  b.changeStartCategory(e, "whatsapp")
  assert.equal(e.config.trigger, "whatsapp_flow_button")
  b.changeStartCategory(e, "proposal")
  assert.equal(e.config.trigger, "proposal_viewed")
  assert.equal(e.config.entry_policy, "future", "política de entrada preservada")
})

test("templates listados são só os do WABA do número escolhido; sem número, todos", () => {
  const { e, b } = fresh()
  e.config.trigger = "whatsapp_flow_button"
  assert.equal(b.flowTemplatesFor(e).map(t => t.id).join(), "10,20")
  e.config.whatsapp_sender_number_id = "1"
  assert.equal(b.flowTemplatesFor(e).map(t => t.id).join(), "10")
})

test("trocar de número descarta o template de outro número", () => {
  const { e, b } = fresh()
  e.config = { trigger: "whatsapp_flow_button", whatsapp_sender_number_id: "2", whatsapp_template_id: "10" }
  b.afterEntryChange(e, "whatsapp_sender_number_id")
  assert.equal(e.config.whatsapp_template_id, undefined)
})

test("escolher o template monta o caminho por botão ligado à entrada, só com o canvas vazio", () => {
  const { e, b } = fresh()
  e.config = { trigger: "whatsapp_flow_button", whatsapp_sender_number_id: "1", whatsapp_template_id: "10" }
  b.afterEntryChange(e, "whatsapp_template_id")
  assert.equal(b.definition.nodes.map(n => n.id).join(), "entry_99,response_condition_1,action_1")
  assert.equal(JSON.stringify(b.definition.edges[0]), JSON.stringify({ from: "entry_99", to: "response_condition_1" }))

  const before = b.definition.nodes.length
  b.afterEntryChange(e, "whatsapp_template_id")
  assert.equal(b.definition.nodes.length, before, "não duplica nem sobrescreve o que já foi montado")
})

test("um único número já vem escolhido ao selecionar o início por botão", () => {
  const single = { ...catalog, whatsapp_senders: [catalog.whatsapp_senders[0]] }
  const e = entry()
  const b = builder(single, { nodes: [e], edges: [] })
  e.config.trigger = "whatsapp_flow_button"
  b.afterEntryChange(e, "trigger")
  assert.equal(e.config.whatsapp_sender_number_id, "1")
})

test("número e template sobrevivem à normalização do início por botão e somem em outros gatilhos", () => {
  const { e, b } = fresh()
  e.config = { trigger: "whatsapp_flow_button", entry_policy: "future", whatsapp_sender_number_id: "1", whatsapp_template_id: "10", use_as_receptive: true, stage: "x" }
  b.normalizeEntryConfigForTrigger(e)
  assert.equal(e.config.whatsapp_template_id, "10")
  assert.equal(e.config.use_as_receptive, true)
  assert.equal(e.config.stage, undefined)
  e.config.trigger = "lead_created"
  b.normalizeEntryConfigForTrigger(e)
  assert.equal(e.config.whatsapp_template_id, undefined)
  assert.equal(e.config.use_as_receptive, undefined)
})
