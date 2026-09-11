// Run after request specs export CATEGORY_FORM_SNAPSHOTS; requires jsdom.
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const { JSDOM } = require("jsdom")
const root = path.join(__dirname, "../..")
const snapshots = process.env.CATEGORY_FORM_SNAPSHOTS
assert(snapshots, "Set CATEGORY_FORM_SNAPSHOTS to the directory exported by request specs")
let count = 0
for (const file of fs.readdirSync(snapshots).filter(name => name.endsWith(".html"))) {
  const dom = new JSDOM(fs.readFileSync(path.join(snapshots, file), "utf8"), { runScripts: "outside-only", url: "https://example.test" })
  const w = dom.window
  w.eval(fs.readFileSync(path.join(root, "app/javascript/lib/conditional_fields.js"), "utf8").replaceAll("export function", "function"))
  w.Controller = class {}
  w.eval(fs.readFileSync(path.join(root, "app/javascript/controllers/habitation_form_controller.js"), "utf8").replace(/^import .*\n/gm, "").replace("export default class", "window.FormController = class"))
  const form = new w.FormController()
  form.element = w.document.querySelector(".habitation-form-ui")
  form.categoryTarget = form.element.querySelector('[name="habitation[categoria]"]')
  form.hasCategoryTarget = true
  form.cadastroTypeTarget = form.element.querySelector('[name="ui_cadastro_type"]')
  form.cadastroTypeTargets = [form.cadastroTypeTarget]
  form.detailFieldsValue = JSON.parse(form.element.dataset.habitationFormDetailFieldsValue)
  form.developmentSelectTarget = form.element.querySelector('[name="habitation[codigo_empreendimento]"]')
  form.hasDevelopmentSelectTarget = Boolean(form.developmentSelectTarget)
  form.previousCategory = form.categoryTarget.value
  const categories = JSON.parse(form.element.dataset.habitationFormCategoriesByTypeValue)[form.cadastroTypeTarget.value]
  for (const category of categories) {
    form.categoryTarget.value = category
    form.applyCategoryBehavior()
    const commercial = ["Sala Comercial", "Ponto Comercial", "Loja"].includes(category)
    const development = form.cadastroTypeTarget.value === "empreendimento"
    assert.equal(form.element.querySelector("#infra").hidden, commercial, category)
    assert.equal(form.element.querySelector("#features").hidden, development, category)
    assert.equal(form.element.querySelectorAll('[name="habitation[descricao_web]"]').length, 1)
    const text = form.element.querySelector('[name="habitation[descricao_web]"]')
    assert.equal(text.closest(".tab-pane").id, development ? "infra" : "features")
    assert.equal(text.disabled, false, category + " description remains usable")
    const docks = form.element.querySelector('[name="habitation[docas_qtd]"]')
    if (docks) assert.equal(docks.disabled, !["Galpão", "Galpão em Condomínio"].includes(category), category)
    const floors = form.element.querySelector('[name="habitation[andares_qtd]"]')
    assert.equal(floors.closest(".tab-pane").id, commercial ? "general" : "infra")
    assert.equal(floors.disabled, false)
    count++
  }
  if (categories.includes("Galpão")) {
    form.categoryTarget.value = "Galpão"
    form.applyCategoryBehavior()
    form.previousCategory = "Galpão"
    const docks = form.element.querySelector('[name="habitation[docas_qtd]"]')
    const others = form.element.querySelector('input[name="habitation[caracteristicas][]"][value="Outra operação"]')
    const warehouseType = form.element.querySelector('select#habitation_warehouse_type[name="habitation[caracteristicas][]"]')
    assert(warehouseType, "warehouse type select is rendered")
    assert.equal(form.element.querySelectorAll('input[type="checkbox"][name="habitation[caracteristicas][]"][value="Galpão de Estrutura Metálica com Telhas de Zinco"]').length, 0)
    warehouseType.value = "Galpão de Estrutura Metálica com Telhas de Zinco"
    for (const removed of ["tipo_galpao", "area_total_construida_m2", "testada_terreno_m", "rua_interna_condominio", "operacoes_galpao", "layouts_galpao", "classificacao_galpao", "tipo_piso_galpao", "zoneamentos_galpao", "alimentacao_eletrica", "instalacoes_eletricas"]) {
      assert.equal(form.element.querySelectorAll(`[name="habitation[${removed}]"], [name="habitation[${removed}][]"]`).length, 0, removed)
    }
    const classes = Array.from(form.element.querySelectorAll('input[data-exclusive-choice-group="Classificação"]'))
    assert.equal(classes.length, 3, "AAA, A+ and A remain distinct")
    classes[0].checked = true
    classes[1].checked = true
    w.enforceExclusiveChoice(classes[1], form.element)
    assert.equal(classes[0].checked, false)
    assert.equal(classes[1].checked, true)
    classes[1].disabled = true
    classes[2].checked = true
    w.enforceExclusiveChoice(classes[2], form.element)
    assert.equal(classes[1].checked, true)
    assert.equal(classes[2].checked, false)
    classes[1].disabled = false
    classes[1].checked = false
    others.checked = true
    form.applyCategoryBehavior()
    const otherText = form.element.querySelector('[name="habitation[outra_operacao_galpao]"]')
    assert.equal(otherText.disabled, false)
    assert.equal(otherText.required, true)
    otherText.value = "Montagem"
    others.checked = false
    form.applyCategoryBehavior()
    assert.equal(otherText.disabled, true)
    assert.equal(otherText.required, false)
    assert.equal(otherText.value, "Montagem")
    others.checked = true
    form.applyCategoryBehavior()
    assert.equal(otherText.value, "Montagem")
    docks.value = "4"
    form.categoryTarget.value = "Loja"
    w.confirm = () => false
    form.categoryChanged()
    assert.equal(form.categoryTarget.value, "Galpão")
    assert.equal(docks.value, "4")
    w.confirm = () => true
    form.categoryTarget.value = "Loja"
    form.categoryChanged()
    assert.equal(docks.disabled, true)
    assert.equal(warehouseType.disabled, true)
    form.categoryTarget.value = "Galpão"
    form.categoryChanged()
    assert.equal(docks.value, "4")
    assert.equal(docks.disabled, false)
    assert.equal(warehouseType.value, "Galpão de Estrutura Metálica com Telhas de Zinco")
    assert.equal(warehouseType.disabled, false)
    docks.setAttribute("aria-disabled", "true")
    docks.disabled = true
    form.categoryTarget.value = "Loja"
    form.applyCategoryBehavior()
    form.categoryTarget.value = "Galpão"
    form.applyCategoryBehavior()
    assert.equal(docks.disabled, true, "category switch cannot unlock a forbidden field")
  }
  dom.window.close()
}
console.log(`OK: ${count} category transitions, tabs, field reuse, cancel/restore and permission locks`)
