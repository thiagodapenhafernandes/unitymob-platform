import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const source = (await readFile(new URL('../../app/javascript/controllers/menu_sections_controller.js', import.meta.url), 'utf8'))
  .replace('import { Controller } from "@hotwired/stimulus"', 'class Controller {}')
const { default: MenuSections } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

class ClassList {
  constructor(...values) { this.values = new Set(values) }
  toggle(name, force) { force ? this.values.add(name) : this.values.delete(name) }
  contains(name) { return this.values.has(name) }
  add(name) { this.values.add(name) }
  remove(name) { this.values.delete(name) }
}


function section({ active = false } = {}) {
  const listeners = new Map()
  const target = { hidden: false, scrollHeight: 100, style: {}, classList: new ClassList() }
  const trigger = {
    attrs: { 'aria-expanded': 'false' },
    setAttribute(name, value) { this.attrs[name] = String(value) },
    getAttribute(name) { return this.attrs[name] },
    closest() { return node }
  }
  const node = {
    classList: new ClassList(),
    querySelector(selector) {
      if (selector.includes("target='trigger'")) return trigger
      if (selector.includes("target='items'")) return target
      if (selector === '.ax-nav__section-items .ax-nav__link.active') return active ? {} : null
      return null
    },
    addEventListener(type, callback) { listeners.set(type, callback) },
    removeEventListener(type) { listeners.delete(type) },
    dispatch(type) { listeners.get(type)?.({ currentTarget: node, type }) },
    matches() { return false },
    contains(element) { return element?.section === node }
  }
  return { node, trigger, target }
}

global.window = { setTimeout, clearTimeout, matchMedia: () => ({ matches: true }) }
global.document = { body: { classList: { contains: name => name === 'is-compact' } }, activeElement: null }

const product = section()
const operation = section({ active: true })
const controller = new MenuSections()
controller.element = { querySelectorAll: () => [product.node, operation.node] }
controller.connect()

assert.equal(product.target.hidden, true, 'inactive compact section starts closed')
assert.equal(operation.target.hidden, false, 'active compact section keeps its full-sidebar state')
assert.equal(operation.node.classList.contains('is-previewing'), false, 'active compact section does not show a flyout until hover/focus')

product.node.dispatch('mouseenter')
assert.equal(product.target.hidden, false, 'hover opens compact section')
assert.equal(product.trigger.getAttribute('aria-expanded'), 'true')
assert.equal(product.node.classList.contains('is-previewing'), true, 'hover marks only the previewed section as visible')
assert.equal(operation.target.hidden, false, 'hovering another compact section preserves current full-sidebar state')
assert.equal(operation.node.classList.contains('is-previewing'), false, 'hovering another compact section hides the previous flyout')

controller.toggle({ currentTarget: product.trigger })
assert.equal(product.target.hidden, false, 'clicking compact section trigger must not close the hover panel')

document.activeElement = { section: product.node }
product.node.dispatch('mouseleave')
await new Promise(resolve => setTimeout(resolve, 190))
assert.equal(product.target.hidden, true, 'mouseleave closes compact preview even after a click leaves focus inside')
assert.equal(product.node.classList.contains('is-previewing'), false, 'mouseleave removes compact preview visibility')
assert.equal(product.trigger.getAttribute('aria-expanded'), 'false')

product.node.dispatch('focusin')
assert.equal(product.target.hidden, false, 'keyboard focus opens compact section')
assert.equal(product.node.classList.contains('is-previewing'), true, 'keyboard focus marks preview visibility')
product.node.dispatch('focusout')
await new Promise(resolve => setTimeout(resolve, 190))
assert.equal(product.target.hidden, false, 'focus inside keeps compact section available for keyboard users')
assert.equal(product.node.classList.contains('is-previewing'), true, 'focus inside keeps preview visible')
document.activeElement = null
product.node.dispatch('focusout')
await new Promise(resolve => setTimeout(resolve, 190))
assert.equal(product.target.hidden, true, 'focus leaving compact section closes it')
assert.equal(product.node.classList.contains('is-previewing'), false, 'focus leaving removes preview visibility')

console.log('Compact sidebar section preview: passed')
