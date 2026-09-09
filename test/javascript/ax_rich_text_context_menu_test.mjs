import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const source = (await readFile(new URL('../../app/javascript/controllers/ax_rich_text_controller.js', import.meta.url), 'utf8')).replace('import { Controller } from "@hotwired/stimulus"', 'class Controller {}')
const { default: RichText } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)
const controller = new RichText()
let closed = 0
let restored = 0
const inside = {}
controller.menuTarget = { matches: () => true, contains: target => target === inside, hidePopover: () => closed++ }
controller.restoreSelection = () => restored++
controller.dismissMenu({ type: 'pointerdown', button: 2, target: {} })
controller.dismissMenu({ type: 'pointerup', button: 2, target: {} })
assert.equal(closed, 0, 'right-click must leave the menu open')
controller.dismissMenu({ type: 'pointerdown', button: 0, target: inside })
assert.equal(closed, 0, 'interacting with the menu must not close it')
controller.dismissMenu({ type: 'pointerdown', button: 0, target: {} })
assert.equal(closed, 1, 'left-click outside closes the menu')
controller.dismissMenu({ type: 'keydown', key: 'Escape', preventDefault() {} })
assert.equal(closed, 2)
assert.equal(restored, 1, 'Escape restores the editor selection')
const template = await readFile(new URL('../../app/views/admin/shared/ui/_rich_text_field.html.erb', import.meta.url), 'utf8')
assert.match(template, /popover="manual"/, 'native light dismiss must not race with contextmenu')
console.log('Context menu dismissal: passed')
