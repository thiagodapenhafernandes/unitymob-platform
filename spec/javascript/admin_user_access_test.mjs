import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import vm from 'node:vm'

const context = vm.createContext({ Controller: class {} })
vm.runInContext(readFileSync('app/javascript/controllers/admin_user_access_controller.js', 'utf8')
  .replace(/^import .*\n/gm, '').replace('export default class', 'this.Access = class'), context)

test('sales and rental managers follow profile changes and retain eligible selections', () => {
  const controller = new context.Access()
  const options = [
    { value: '', dataset: {} },
    { value: '1', dataset: { position: '100' } },
    { value: '2', dataset: { position: '300' } }
  ]
  const select = () => ({ value: '1', dataset: { profilePosition: '200' }, replaceChildren(...options) { this.options = options } })
  controller.managerSelectTargets = [select(), select()]
  controller.managerOptions = new Map(controller.managerSelectTargets.map((select) => [select, options]))
  controller.syncManagers({ dataset: { position: '200' } })
  for (const select of controller.managerSelectTargets) {
    assert.deepEqual(select.options.map((option) => option.value), ['', '1'])
    assert.equal(select.value, '1')
  }
  controller.syncManagers({ dataset: { position: '1000' } })
  for (const select of controller.managerSelectTargets) {
    assert.deepEqual(select.options.map((option) => option.value), ['', '1', '2'])
    select.value = '2'
  }
  controller.syncManagers({ dataset: { position: '300' } })
  for (const select of controller.managerSelectTargets) {
    assert.deepEqual(select.options.map((option) => option.value), ['', '1'])
    assert.equal(select.value, '')
  }
  controller.syncManagers(null)
  assert.deepEqual(controller.managerSelectTargets[0].options.map((option) => option.value), ['', '1'])
})
