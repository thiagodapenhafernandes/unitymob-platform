import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import vm from 'node:vm'

function controller(file, globals = {}) {
  const context = vm.createContext({ Controller: class {}, ...globals })
  vm.runInContext(readFileSync(file, 'utf8').replace(/^import .*\n/gm, '').replace('export default class', 'this.ControllerClass = class'), context)
  return new context.ControllerClass()
}

test('autocomplete follows conditional disabled state without mutation loops', () => {
  let notify, changes = 0
  const select = controller('app/javascript/controllers/tom_select_controller.js', {
    MutationObserver: class {
      constructor(callback) { notify = callback }
      observe(element, config) { assert.equal(config.attributeFilter[0], 'disabled') }
      disconnect() {}
    }
  })
  select.element = { disabled: false }
  select.tomSelect = {
    isDisabled: false,
    disable() { this.isDisabled = true; changes++ },
    enable() { this.isDisabled = false; changes++ }
  }
  select.observeDisabledState()
  select.element.disabled = true
  notify()
  assert.equal(select.tomSelect.isDisabled, true)
  notify()
  assert.equal(changes, 1)
  select.element.disabled = false
  notify()
  assert.equal(select.tomSelect.isDisabled, false)
  assert.equal(changes, 2)
})

test('audience field changes update autocomplete operators and preserve a valid selection', () => {
  const builder = controller('app/javascript/controllers/whatsapp_campaign_builder_controller.js')
  const options = ['in', 'equals', 'with_any', 'without_any'].map(value => ({ value, disabled: false }))
  let selection, resets = 0
  const select = {
    options, value: 'in',
    tomselect: {
      options: Object.fromEntries(options.map(option => [option.value, { text: option.value }])),
      updateOption(value, data) { this.options[value] = data },
      setValue(value, silent) { assert.equal(silent, true); selection = value; resets++ },
      refreshOptions(open) { assert.equal(open, false) }
    }
  }
  builder.syncOperatorOptions(select, 'tags')
  assert.equal(selection, 'with_any')
  assert.equal(select.tomselect.options.in.disabled, true)
  assert.equal(select.tomselect.options.with_any.disabled, false)
  select.value = 'without_any'
  selection = 'without_any'
  builder.syncOperatorOptions(select, 'tags')
  assert.equal(selection, 'without_any')
  assert.equal(resets, 1, 'typing in the same filter must not reset autocomplete search')
})
