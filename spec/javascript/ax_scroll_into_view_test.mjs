import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import vm from 'node:vm'

function controller(visible) {
  const calls = []
  let scheduled
  const context = vm.createContext({
    Controller: class {},
    requestAnimationFrame: callback => { scheduled = callback; return 7 },
    cancelAnimationFrame: frame => calls.push(['cancel', frame])
  })
  vm.runInContext(readFileSync('app/javascript/controllers/ax_scroll_into_view_controller.js', 'utf8')
    .replace(/^import .*\n/gm, '').replace('export default class', 'this.Scroll = class'), context)
  const instance = new context.Scroll()
  instance.element = {
    getClientRects: () => visible ? [{}] : [],
    scrollIntoView: () => calls.push(['scroll']),
    focus: () => calls.push(['focus'])
  }
  instance.connect()
  scheduled()
  instance.disconnect()
  return calls
}

test('only the visible responsive panel scrolls and takes keyboard focus', () => {
  assert.deepEqual(controller(true), [['scroll'], ['focus'], ['cancel', 7]])
  assert.deepEqual(controller(false), [['cancel', 7]])
})
