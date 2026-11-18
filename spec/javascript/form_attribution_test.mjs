import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import vm from 'node:vm'

function setup(cookie = 'unitymob_lgpd_consent=accepted') {
  const storage = () => {
    const data = new Map()
    return { getItem: key => data.get(key) || null, setItem: (key, value) => data.set(key, value), removeItem: key => data.delete(key), data }
  }
  const listeners = new Map()
  const window = { location: new URL('https://site.test/?gclid=First_Click&utm_campaign=imoveis'),
    localStorage: storage(), sessionStorage: storage(),
    addEventListener: (name, callback) => listeners.set(name, callback),
    removeEventListener: name => listeners.delete(name) }
  const document = { cookie, referrer: 'https://google.com/' }
  const context = vm.createContext({ Controller: class {}, window, document, URL })
  vm.runInContext(readFileSync('app/javascript/lib/lead_attribution.js', 'utf8').replace(/export /g, ''), context)
  vm.runInContext(readFileSync('app/javascript/controllers/form_attribution_controller.js', 'utf8')
    .replace(/^import .*\n/gm, '').replace('export default class', 'this.FormAttribution = class'), context)
  const controller = new context.FormAttribution()
  controller.connect()
  return { controller, window, document, listeners, context }
}

test('inclui primeira chegada e sessão em FormData sem tocar nos campos ou arquivos do formulário', () => {
  const { controller } = setup()
  const formData = new FormData()
  formData.set('contact[name]', 'Maria')
  formData.set('public_form_submission[utm_campaign]', 'Resposta de campo personalizado')
  formData.set('cv', new Blob(['curriculo']), 'curriculo.pdf')
  controller.append({ formData })
  assert.equal(formData.get('attribution[gclid]'), 'First_Click')
  assert.equal(formData.get('attribution[first_touch][gclid]'), 'First_Click')
  assert.equal(formData.get('attribution[conversion_touch][utm_campaign]'), 'imoveis')
  assert.equal(formData.get('contact[name]'), 'Maria')
  assert.equal(formData.get('public_form_submission[utm_campaign]'), 'Resposta de campo personalizado')
  assert.equal(formData.get('cv').name, 'curriculo.pdf')
})

test('reutiliza a chegada capturada pelo modal ao navegar até outro formulário', () => {
  const { window, document, context } = setup()
  window.location = new URL('https://site.test/contato')
  document.referrer = 'https://site.test/'
  const otherForm = new context.FormAttribution()
  otherForm.connect()
  const formData = new FormData()
  otherForm.append({ formData })
  assert.equal(formData.get('attribution[gclid]'), 'First_Click')
  assert.equal(formData.get('attribution[landing_url]'), 'https://site.test/?gclid=First_Click&utm_campaign=imoveis')
})

test('sem consentimento mantém captura em memória; aceite persiste e recusa remove dados anteriores', () => {
  const { controller, window, document, listeners } = setup('')
  const formData = new FormData()
  controller.append({ formData })
  assert.equal(formData.get('attribution[gclid]'), 'First_Click')
  assert.equal(window.localStorage.data.size, 0)
  document.cookie = 'unitymob_lgpd_consent=accepted'
  listeners.get('unitymob:lgpd-consent-accepted')()
  assert.equal(window.localStorage.data.size, 1)
  document.cookie = 'unitymob_lgpd_consent=rejected'
  listeners.get('unitymob:lgpd-consent-rejected')()
  controller.append({ formData })
  assert.equal([...formData.keys()].length, 0)
  assert.equal(window.localStorage.data.size, 0)
  controller.disconnect()
  assert.equal(listeners.size, 0)
})

test('armazenamento indisponível não impede preparar o formulário', () => {
  const { controller, window } = setup()
  Object.defineProperty(window, 'sessionStorage', { get() { throw new Error('unavailable') } })
  const formData = new FormData()
  assert.doesNotThrow(() => controller.append({ formData }))
  assert.equal(formData.get('attribution[gclid]'), 'First_Click')
})
