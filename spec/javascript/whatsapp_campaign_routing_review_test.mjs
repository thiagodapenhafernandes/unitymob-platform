import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import vm from 'node:vm'

const context = vm.createContext({ Controller: class {} })
vm.runInContext(readFileSync('app/javascript/controllers/whatsapp_campaign_builder_controller.js', 'utf8')
  .replace(/^import .*\n/gm, '').replace('export default class', 'this.Builder = class'), context)

function row(text, action, rule = {}, message = '') {
  return { querySelector(selector) {
    if (selector.includes('[text]')) return { value: text }
    if (selector.includes('[action]')) return { value: action }
    if (selector.includes('[distribution_rule_id]')) return rule
    if (selector.includes('[message]')) return { value: message }
  } }
}

test('review shows each button, selected queue and C2S destination as text', () => {
  const builder = new context.Builder()
  builder.responseDecisionRowTargets = [
    row('Tenho interesse', 'generate_lead', { value: '9', selectedOptions: [{ textContent: 'Fila <C2S>' }] }),
    row('Sair', 'unsubscribe')
  ]
  builder.distributionRuleDestinationsValue = { 9: 'c2s' }
  builder.responseActionsValue = { unsubscribe: 'Descadastrar contato' }
  builder.hasReviewRoutingTarget = true
  builder.reviewRoutingTarget = {}
  builder.refreshReview()
  assert.match(builder.reviewRoutingTarget.textContent, /Tenho interesse.*Fila: Fila <C2S>.*envio ao C2S, sem distribuição local/)
  assert.match(builder.reviewRoutingTarget.textContent, /Sair.*Descadastrar contato/)
  assert.equal(builder.reviewRoutingTarget.innerHTML, undefined)
})

test('review follows queue changes and reports missing selection', () => {
  const builder = new context.Builder()
  const select = { value: '', selectedOptions: [] }
  builder.responseDecisionRowTargets = [row('Quero', 'generate_lead', select)]
  assert.match(builder.routingReview(), /fila não selecionada/)
  select.value = '4'
  select.selectedOptions = [{ textContent: 'Equipe de locação' }]
  builder.distributionRuleDestinationsValue = { 4: 'unitymob' }
  assert.match(builder.routingReview(), /Equipe de locação.*equipe da Unitymob.*regras da fila/)
})

test('review includes automatic message and handles absent or customized decisions honestly', () => {
  const builder = new context.Builder()
  builder.responseDecisionRowTargets = [row('Ajuda', 'send_message', {}, 'Vamos te atender')]
  builder.responseActionsValue = { send_message: 'Enviar mensagem' }
  assert.match(builder.routingReview(), /Ajuda.*Enviar mensagem: Vamos te atender/)
  builder.responseDecisionRowTargets = []
  assert.match(builder.routingReview(), /Sem decisões de botões/)
  builder.customizedWorkflowValue = true
  assert.match(builder.routingReview(), /Automação personalizada.*fluxo vinculado/)
})
