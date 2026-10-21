import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import vm from 'node:vm'

function setup(track) {
  let fallback
  const context = vm.createContext({ Controller: class {},
    window: { UnitymobTracking: { track }, location: {
      origin: 'https://example.test', pathname: '/imovel', search: '?email=private@example.test'
    } },
    setTimeout: fn => { fallback = fn; return 1 }, clearTimeout() {}
  })
  vm.runInContext(readFileSync('app/javascript/controllers/lead_capture_controller.js', 'utf8')
    .replace(/^import .*\n/gm, '').replace('export default class', 'this.Capture = class'), context)
  return { controller: new context.Capture(), fallback: () => fallback() }
}

const success = { success: true, analytics_event: {
  event: 'generate_lead', event_id: 'opaque-event', phone_e164: '+5547991234567', business_type: 'venda',
  property_code: 'AP123', form_id: 'whatsapp_modal', email: 'private@example.test'
} }

test('encaminha somente dados permitidos e aguarda callback antes de continuar', async () => {
  let args, finished = false
  const { controller } = setup((...values) => { args = values; return true })
  const pending = controller.trackConfirmedLead(success).then(() => { finished = true })
  assert.equal(finished, false)
  assert.equal(args[0], 'generate_lead')
  assert.equal(args[1].page_url, 'https://example.test/imovel')
  assert.equal(args[1].property_code, 'AP123')
  assert.equal(args[1].email, undefined)
  assert.equal(args[1].phone_e164, '+5547991234567')
  args[2].onComplete()
  await pending
  assert.equal(finished, true)
})

test('não conta clique, erro, resposta legada ou complemento como lead', async () => {
  const { controller } = setup(() => assert.fail('não deve emitir'))
  for (const result of [null, { success: true }, { ...success, success: false },
    { success: true, analytics_event: { event: 'whatsapp_click', event_id: 'id' } }]) {
    await controller.trackConfirmedLead(result)
  }
})

test('recusa ou falha das tags não impede seguir o atendimento', async () => {
  for (const track of [() => false, () => { throw new Error('bloqueador') }]) {
    await setup(track).controller.trackConfirmedLead(success)
  }
})

test('tag sem callback não prende o visitante', async () => {
  const { controller, fallback } = setup(() => true)
  const pending = controller.trackConfirmedLead(success)
  fallback()
  await pending
})
