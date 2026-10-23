import { readFileSync } from 'node:fs'
import vm from 'node:vm'
import assert from 'node:assert/strict'
import { test } from 'node:test'
const code = readFileSync('app/javascript/controllers/ax_live_thread_controller.js', 'utf8')
  .replace(/^import .*$/gm, '').replace('export default class', 'globalThis.LiveThread = class')
function setup() {
  const subscriptions = { create: (params, callbacks) => ({ params, callbacks }), remove: () => {} }
  const document = { hidden: false, addEventListener() {}, removeEventListener() {} }
  const context = { Controller: class {}, consumer: { subscriptions }, document, URLSearchParams, fetch: async () => ({ok: true}), window: { addEventListener() {}, removeEventListener() {} } }
  vm.runInNewContext(code, context)
  const c = new context.LiveThread()
  c.hasInputTarget = true; c.inputTarget = { value: 'primeira', disabled: false }
  c.submitTarget = { disabled: false }; c.paramsValue = {}; c.channelValue = 'LeadConversationChannel'
  c.frameTarget = { hasAttribute: () => false, reload() { this.reloads = (this.reloads || 0) + 1 }, querySelector: () => ({ dataset: { threadReplyOpen: 'true' } }) }
  c.environment = context
  return c
}
test('recebimento e reconexão atualizam só o frame sem tocar no rascunho', () => {
  const c = setup(); c.connect(); c.subscription.callbacks.received(); c.subscription.callbacks.connected()
  assert.equal(c.inputTarget.value, 'primeira'); assert.equal(c.frameTarget.reloads, 2)
  c.disconnect()
})
test('resposta bem sucedida preserva texto novo digitado durante envio', () => {
  const c = setup(); c.submitting(); c.inputTarget.value = 'segundo rascunho'
  c.submitted({ detail: { success: true } }); assert.equal(c.inputTarget.value, 'segundo rascunho')
})
test('sucesso limpa só o texto enviado; falha mantém o texto', () => {
  const c = setup(); c.submitting(); c.submitted({ detail: { success: false } })
  assert.equal(c.inputTarget.value, 'primeira')
  c.submitting(); c.submitted({ detail: { success: true } }); assert.equal(c.inputTarget.value, '')
})
test('atualização recebida durante carga não é perdida', () => {
  const c = setup(); c.frameTarget.hasAttribute = () => true; c.refresh()
  c.frameTarget.hasAttribute = () => false; c.frameLoaded(); assert.equal(c.frameTarget.reloads, 1)
})

test('só marca como lido o cursor visível em aba com foco, preservando rascunho', async () => {
  const c = setup(); const calls = []
  c.hasReadUrlValue = true; c.readUrlValue = '/read'
  c.environment.window.innerHeight = 800
  c.environment.document.hasFocus = () => true
  c.environment.document.querySelector = () => ({content: 'csrf'})
  c.environment.fetch = async (...args) => { calls.push(args); return {ok:true} }
  c.frameTarget.getBoundingClientRect = () => ({top:20,bottom:300})
  c.frameTarget.querySelector = () => ({dataset:{threadReadCursor:'12',threadReplyOpen:'true'}})
  c.environment.document.hidden = true; c.frameLoaded(); assert.equal(calls.length, 0)
  c.environment.document.hidden = false; c.frameLoaded(); c.frameLoaded()
  assert.equal(calls.length, 1); assert.equal(calls[0][1].body.toString(), 'cursor=12')
  assert.equal(c.inputTarget.value, 'primeira')
})
