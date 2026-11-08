import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import vm from 'node:vm'

const template = readFileSync('app/views/layouts/_tracking_head.html.erb', 'utf8')
const pageFunctions = template.slice(template.indexOf('      function pageContext()'), template.indexOf('      function loadScript('))
const trackFunctions = template.slice(template.indexOf('      function trackingPayload('), template.indexOf('      function closestTrackedClick('))
  .replace('<%= raw Leads::Attribution::BUSINESS_TYPE_VALUES.to_json %>', JSON.stringify({ sale: 'venda', rent: 'locacao', general: 'geral' }))
function setup({ enabled = true, consent = true } = {}) {
  let context = { page_type: 'home', business_type: 'geral', site_language: 'pt-br' }
  const w = { location: { pathname: '/', href: 'https://example.test/' }, dataLayer: [] }
  const d = { cookie: consent ? 'unitymob_lgpd_consent=accepted' : '', getElementById: () => ({ textContent: JSON.stringify(context) }) }
  const scope = vm.createContext({ w, d, structuredEvents: enabled, lastPageContext: '', initialContext: {}, COOKIE_KEY: 'unitymob_lgpd_consent', ACCEPTED_VALUE: 'accepted' })
  vm.runInContext(pageFunctions + trackFunctions, scope)
  return { w, d, scope, navigate(value) { context = value; w.location.pathname = '/imovel' } }
}
test('contexto vem antes do evento, respeita consentimento e não duplica visualização', () => {
  const { w, scope, navigate } = setup()
  navigate({ page_type: 'property', business_type: 'locacao', property_id: '42', property_code: 'AP42', ecommerce: { items: [{ item_id: 'AP42' }] } })
  scope.trackPageContext(); scope.trackPageContext()
  assert.equal(w.dataLayer.filter(x => x.event === 'view_item').length, 1)
  assert.equal(w.dataLayer[1].page_type, 'property')
  assert.equal(w.dataLayer[2].property_id, '42')
  assert.equal(w.dataLayer[2].value, undefined)
  const blocked = setup({ consent: false }); blocked.scope.trackPageContext()
  assert.equal(blocked.w.dataLayer.length, 0)
})
test('troca de página limpa imóvel e identidade anteriores sem fabricar page_view', () => {
  const { w, scope, navigate } = setup()
  navigate({ page_type: 'property', business_type: 'venda', property_id: '42' }); scope.trackPageContext()
  navigate({ page_type: 'home', business_type: 'geral' }); scope.trackPageContext()
  assert.equal(w.dataLayer.at(-2).property_id, null)
  assert.equal(w.dataLayer.at(-2).user_data, null)
  assert.equal(w.dataLayer.at(-1).page_type, 'home')
  assert.equal(w.dataLayer.filter(x => x.event === 'page_view').length, 0)
})
test('contas sem opção mantêm o contrato legado; dados pessoais ficam apenas em user_data', () => {
  const payload = { business_type: 'venda', property_id: '42', property_code: 'AP42', email: 'ignored@example.test', phone_e164: '+5547991234567', user_data: { external_id: '8' }, lead_id: '8', transaction_id: 'opaque' }
  const enabled = setup().scope.trackingPayload('generate_lead', payload)
  assert.equal(enabled.property_id, '42'); assert.equal(enabled.transaction_id, 'opaque')
  assert.equal(enabled.email, undefined); assert.equal(enabled.phone_e164, undefined)
  const legacy = setup({ enabled: false }).scope.trackingPayload('generate_lead', payload)
  assert.equal(legacy.property_id, 'AP42'); assert.equal(legacy.user_data, undefined)
})

test('identidade fica disponível ao container, sem virar parâmetro customizado do Pixel direto', () => {
  const { w, scope } = setup()
  let args
  w.fbq = (...values) => { args = values }
  scope.track('generate_lead', { user_data: { email_address: 'private@example.test' }, event_id: 'opaque' })
  assert.equal(w.dataLayer.at(-1).user_data.email_address, 'private@example.test')
  assert.equal(args[2].user_data, undefined)
})
