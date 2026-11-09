import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
const source = (await readFile(new URL('../../app/javascript/controllers/nested_form_controller.js', import.meta.url), 'utf8'))
  .replace('import { Controller } from "@hotwired/stimulus"', 'class Controller {}')
const { default: NestedForm } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)
const outer = new NestedForm()
outer.placeholderValue = 'NEW_RECORD'
outer.templateTarget = { innerHTML: 'campaign[NEW_RECORD] condition[NEW_CONDITION]' }
let added
outer.containerTarget = { insertAdjacentHTML: (_, html) => { added = html } }
outer.updatePositions = () => {}
outer.add({ preventDefault() {} })
assert(!added.includes('NEW_RECORD'))
assert(added.includes('NEW_CONDITION'), 'adding a campaign preserves the nested condition placeholder')
const inner = new NestedForm()
inner.placeholderValue = 'NEW_CONDITION'
inner.templateTarget = { innerHTML: added }
inner.containerTarget = outer.containerTarget
inner.updatePositions = () => {}
inner.add({ preventDefault() {} })
assert(!added.includes('NEW_CONDITION'), 'condition additions get their own indexes')

const controller = new NestedForm()
controller.element = {}
const ownPosition = { value: null, closest: () => ownField }
const nestedPosition = { value: 'unchanged', closest: () => nestedField }
const ownField = { closest: () => controller.element, querySelector: () => null, querySelectorAll: () => [nestedPosition, ownPosition] }
const nestedField = { closest: () => ({}), querySelectorAll: () => [nestedPosition] }
controller.containerTarget = { querySelectorAll: () => [ownField, nestedField] }
controller.updatePositions()
assert.equal(ownPosition.value, 1)
assert.equal(nestedPosition.value, 'unchanged', 'outer forms do not reorder nested conditions')
console.log('nested form behavior OK')
