import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import vm from 'node:vm'
const context = vm.createContext({ Controller: class {}, document: { createElement: () => ({ textContent: '' }) } })
vm.runInContext(readFileSync('app/javascript/controllers/distribution_rule_summary_controller.js', 'utf8')
  .replace(/^import .*\n/gm, '').replace('export default class', 'this.Summary = class'), context)

test('summary reflects business and OR cities as text, including removal of the city restriction', () => {
  const controller = new context.Summary()
  const cities = { selectedOptions: [{ value: 'Itapema' }, { value: 'Porto Belo' }] }
  const business = { selectedOptions: [{ textContent: 'Locação' }] }
  controller.element = { querySelector: selector => selector.includes('property_cities') ? cities : selector.includes('business_type') ? business : null }
  controller.checked = () => false
  controller.agentCount = () => 0
  controller.hasLineTarget = true
  controller.hasChipsTarget = false
  controller.hasAgentCountTarget = false
  let appended
  controller.lineTarget = { innerHTML: '', append: node => { appended = node } }
  controller.render()
  assert.equal(appended.textContent, ' Locação E (Itapema OU Porto Belo).')
  cities.selectedOptions = []
  controller.render()
  assert.equal(appended.textContent, ' Locação E (qualquer cidade).')
  cities.selectedOptions = [{ value: '<b>Cidade</b>' }]
  controller.render()
  assert.equal(appended.textContent, ' Locação E (<b>Cidade</b>).')
  assert.equal(controller.lineTarget.innerHTML.includes('<b>Cidade</b>'), false)
})
