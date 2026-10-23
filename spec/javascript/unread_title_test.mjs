import { readFileSync } from 'node:fs'
import vm from 'node:vm'
import assert from 'node:assert/strict'
import { test } from 'node:test'
const code = readFileSync('app/javascript/controllers/in_app_notifications_controller.js', 'utf8')
  .replace(/^import .*$/gm, '').replace('export default class', 'globalThis.Notifications = class')
function setup(total = 3, title = 'Salute — Leads') {
  const document = { title }
  const context = { Controller: class {}, document, URL, window: { location: { origin: "https://crm.test" } }, fetch: async () => ({ ok: true, json: async () => ({total, unread_count: 1}) }) }
  vm.runInNewContext(code, context)
  const c = new context.Notifications()
  c.hasSummaryUrlValue = true; c.summaryUrlValue = '/summary'; c.baseTitle = title; c.renderBadge = () => {}
  return { c, document, context }
}
test('usa contagem absoluta do servidor e preserva título sem acumular prefixos', async () => {
  const { c, document } = setup()
  await c.refreshTitle(); assert.equal(document.title, '(3) Salute — Leads')
  await c.refreshTitle(); assert.equal(document.title, '(3) Salute — Leads')
})
test('zero restaura título e falha de rede mantém contagem confirmada', async () => {
  const { c, document, context } = setup(0, 'Conexão — Plataforma')
  await c.refreshTitle(); assert.equal(document.title, 'Conexão — Plataforma')
  context.fetch = async () => { throw Error('offline') }
  document.title = '(2) Conexão — Plataforma'; await c.refreshTitle()
  assert.equal(document.title, '(2) Conexão — Plataforma')
})
test('resposta antiga não sobrescreve navegação nem uma consulta mais recente', async () => {
  const { c, document, context } = setup()
  let resolve
  context.fetch = () => new Promise(r => { resolve = r })
  const pending = c.refreshTitle(); c.disconnected = true
  resolve({ok:true,json:async()=>({total:10})}); await pending
  assert.equal(document.title, 'Salute — Leads')
})

test('carrega a próxima página pessoal do sino sem alterar a contagem', async () => {
  const { c, document, context } = setup()
  let inserted = ''
  c.nextCursor = 90; c.titleRequest = 1
  c.listTarget = { insertAdjacentHTML: (where, html) => { inserted += html } }
  c.moreTarget = {hidden:false}
  context.fetch = async url => {
    assert.equal(url.searchParams.get('before'), '90')
    return {ok:true,json:async()=>({html:'<a>Aviso pessoal</a>',next_cursor:null})}
  }
  await c.more()
  assert.equal(inserted, '<a>Aviso pessoal</a>'); assert.equal(c.moreTarget.hidden, true)
  assert.equal(document.title, 'Salute — Leads')
})
