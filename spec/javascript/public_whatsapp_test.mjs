import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import vm from 'node:vm'

const vendorUrl = 'data:text/javascript;base64,' + Buffer.from(readFileSync('vendor/javascript/libphonenumber-max.js', 'utf8')).toString('base64')
const validatorSource = readFileSync('app/javascript/lib/public_whatsapp.js', 'utf8').replace('"libphonenumber-max"', JSON.stringify(vendorUrl))
const context = await import('data:text/javascript;base64,' + Buffer.from(validatorSource).toString('base64'))
const cases = JSON.parse(readFileSync('spec/fixtures/phones/public_whatsapp.json'))
for (const [raw, e164] of Object.entries(cases.valid)) {
  test(`aceita ${raw}`, () => assert.equal(context.validatePublicWhatsapp(raw).e164, e164))
}
for (const raw of cases.invalid) {
  test(`rejeita ${raw}`, () => {
    assert.ok(context.validatePublicWhatsapp(raw).error)
    assert.equal(context.validatePublicWhatsapp(raw).e164, undefined)
  })
}

function capture(response, phone = '(47) 99123-4567') {
  const calls = []
  const ctx = vm.createContext({ Controller: class {}, validatorModule: context,
    window: { location: { href: '/imovel' }, axToast: () => calls.push('error') }, document: { referrer: '' } })
  vm.runInContext(readFileSync('app/javascript/controllers/lead_capture_controller.js', 'utf8')
    .replace(/^import .*\n/gm, '').replace('await import("lib/public_whatsapp")', 'validatorModule')
    .replace('export default class', 'this.Capture = class'), ctx)
  const controller = new ctx.Capture()
  Object.assign(controller, { nameTarget: { value: 'Cliente Teste' }, phoneTarget: { value: phone, focus() {}, setAttribute() {}, removeAttribute() {} },
    phoneErrorTarget: { textContent: '', hidden: true }, propertyIdTarget: { value: '' }, submitButtonTarget: { disabled: false }, hasSubmitButtonTarget: true,
    trackingParams: () => ({}), sendLeadData: async data => { calls.push(data.phone); return response },
    trackConfirmedLead: async () => calls.push('conversion'), close: () => calls.push('close'), showSuccessMessage() {} })
  return { controller, calls, event: { preventDefault() {}, target: { reset: () => calls.push('reset') } }, ctx }
}
test('inválido não envia nem emite conversão', async () => {
  const { controller, calls, event } = capture(null, '(47) 99999-9999')
  await controller.submit(event)
  assert.equal(calls.length, 0)
  assert.ok(controller.phoneErrorTarget.textContent)
  assert.equal(controller.submitButtonTarget.disabled, false)
})
test('rejeição do servidor mantém formulário e não emite conversão', async () => {
  const { controller, calls, event } = capture({ success: false, field_errors: { phone: 'Inválido no servidor' } })
  await controller.submit(event)
  assert.deepEqual(calls, ['+5547991234567'])
  assert.equal(controller.phoneErrorTarget.textContent, 'Inválido no servidor')
})
test('somente resposta aceita precede conversão e reset', async () => {
  const { controller, calls, event } = capture({ success: true }, '+351912345678')
  await controller.submit(event)
  assert.deepEqual(calls, ['+351912345678', 'conversion', 'close', 'reset'])
})
test('falha de transporte mantém dados para tentar novamente', async () => {
  const { controller, calls, event } = capture(null)
  await controller.submit(event)
  assert.deepEqual(calls, ['+5547991234567', 'error'])
  assert.equal(controller.submitting, false)
})
