import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import vm from 'node:vm'

const context = vm.createContext({ Controller: class {} })
vm.runInContext(readFileSync('app/javascript/controllers/meta_rules_controller.js', 'utf8')
  .replace(/^import .*\n/gm, '').replace('export default class', 'this.MetaRules = class'), context)

function controller() {
  const rule = new context.MetaRules()
  rule.hasAutoSyncTarget = true
  rule.autoSyncTarget = { checked: true }
  rule.hasExclusionSelectTarget = true
  rule.exclusionSelectTarget = { tomselect: { items: ['excluded'] } }
  rule.formSelectInstance = {
    options: { excluded: {}, included: {}, new: {} }, items: ['excluded'],
    clear() { this.items = [] }, addItems(ids) { this.items.push(...ids) }
  }
  rule.syncAutoSummary = () => {}
  return rule
}

test('automatic selection excludes exceptions, removal restores inclusion', () => {
  const rule = controller()
  rule.updateExclusions()
  assert.deepEqual(Array.from(rule.formSelectInstance.items), ['included', 'new'])
  assert.equal(rule.isAllMetaFormsSelectedAutomatically(), true)
  rule.exclusionSelectTarget.tomselect.items = []
  rule.updateExclusions()
  assert.deepEqual(Array.from(rule.formSelectInstance.items), ['excluded', 'included', 'new'])
})

test('disabled sync preserves exceptions and manual selections', () => {
  const rule = controller()
  rule.autoSyncTarget.checked = false
  rule.updateExclusions()
  assert.deepEqual(Array.from(rule.excludedFormIds()), ['excluded'])
  assert.deepEqual(Array.from(rule.formSelectInstance.items), ['excluded'])
  assert.equal(rule.isAllMetaFormsSelectedAutomatically(), false)
})
