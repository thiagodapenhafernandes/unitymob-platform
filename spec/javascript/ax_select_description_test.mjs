import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import vm from 'node:vm'
const context = vm.createContext({ Controller: class {} })
vm.runInContext(readFileSync('app/javascript/controllers/ax_select_description_controller.js', 'utf8')
  .replace(/^import .*\n/gm, '').replace('export default class', 'this.SelectDescription = class'), context)

test('renders current description, updates on selection and treats descriptions as text', () => {
  const controller = new context.SelectDescription()
  controller.optionsValue = { venda: 'Venda identificada', todos: '<b>Qualquer natureza</b>' }
  controller.controlTarget = { value: 'venda' }
  controller.descriptionTarget = { textContent: '' }
  controller.connect()
  assert.equal(controller.descriptionTarget.textContent, 'Venda identificada')
  controller.controlTarget.value = 'todos'
  controller.update()
  assert.equal(controller.descriptionTarget.textContent, '<b>Qualquer natureza</b>')
  controller.controlTarget.value = ''
  controller.update()
  assert.equal(controller.descriptionTarget.textContent, '')
})
