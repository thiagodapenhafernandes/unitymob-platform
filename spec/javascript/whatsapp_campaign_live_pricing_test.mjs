import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import vm from 'node:vm'
const context = vm.createContext({ Controller: class {} })
vm.runInContext(readFileSync('app/javascript/controllers/whatsapp_campaign_live_controller.js', 'utf8')
  .replace(/^import .*\n/gm, '').replace('export default class', 'this.Live = class'), context)
test('live updates do not turn missing official costs into BRL zero or a fixed estimate', () => {
  const live = new context.Live()
  assert.equal(live.metricValue('cost', null), '—')
  assert.equal(live.metricValue('cpl', null), '—')
  assert.equal(live.metricValue('delivered', 7), '7')
  assert.match(live.metricHint('cost', {}), /não informa custo por disparo/)
})
test('dynamic cards preserve unknown measurement and display genuine repeat clicks safely', () => {
  const live = new context.Live()
  live.escape = (value) => String(value ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;')
  live.escapeAttribute = live.escape
  const html = live.interactionCard({ label: '<script>bad</script>', count: 1, rate: 50, hint: '2 cliques recebidos', tone: 'green' })
  assert.match(html, /&lt;script&gt;/)
  assert.doesNotMatch(html, /<script>/)
  assert.match(html, /2 cliques recebidos/)
  assert.match(live.interactionCard({ label: 'Abrir site', count: null }), /Não mensurável/)
})
test('history displays multiple responses and escapes customer input', () => {
  const live = new context.Live()
  live.hasInteractionHistoryTarget = true
  live.interactionHistoryTarget = {}
  live.escape = (value) => String(value ?? '').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
  live.renderInteractionHistory([{ label: '<img>', kind: 'Clique', recipient: 'Cliente', occurred_at: '14/11', action: 'Registrar' }, { label: 'Outro botão', kind: 'Clique' }])
  assert.match(live.interactionHistoryTarget.innerHTML, /&lt;img&gt;/)
  assert.match(live.interactionHistoryTarget.innerHTML, /Outro botão/)
  assert.equal((live.interactionHistoryTarget.innerHTML.match(/<tr>/g) || []).length, 2)
})
