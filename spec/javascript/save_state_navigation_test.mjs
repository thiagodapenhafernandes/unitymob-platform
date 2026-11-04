import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import vm from 'node:vm'
const context = vm.createContext({ Controller: class {}, CustomEvent: class { constructor(type) { this.type = type } } })
vm.runInContext(readFileSync('app/javascript/controllers/save_state_controller.js', 'utf8')
  .replace(/^import .*\n/gm, '').replace('export default class', 'this.SaveState = class'), context)

test('confirms internal navigation in the shared modal, keeps dirty state until explicit discard', () => {
  const controller = new context.SaveState()
  const dispatched = []
  let clicked = 0
  const link = { dataset: {}, href: '/catalog', getAttribute: () => '/catalog', click: () => clicked++ }
  context.window = { location: { href: '/edit' } }
  controller.dirty = true
  controller.hasNavigationModalTarget = true
  controller.navigationModalTarget = { dispatchEvent: (event) => dispatched.push(event.type) }
  let prevented = 0
  controller.confirmNavigation({ button: 0, target: { closest: () => link }, preventDefault: () => prevented++, stopImmediatePropagation() {} })
  assert.equal(prevented, 1)
  assert.equal(controller.dirty, true)
  assert.equal(clicked, 0)
  controller.discardAndNavigate({ preventDefault() {} })
  assert.equal(controller.dirty, false)
  assert.equal(clicked, 1)
  assert.deepEqual(dispatched, ['ax-modal:open', 'ax-modal:close'])
})

test('saving requests normal form validation and keeps changes dirty until submit begins', () => {
  const controller = new context.SaveState()
  controller.navigationModalTarget = { dispatchEvent() {} }
  controller.dirty = true
  let requested = false
  controller.element = { querySelector: () => null, requestSubmit: () => { requested = true } }
  controller.saveBeforeLeaving({ preventDefault() {} })
  assert.equal(requested, true)
  assert.equal(controller.saveOptionsConfirmed, true)
  assert.equal(controller.dirty, true)
})
