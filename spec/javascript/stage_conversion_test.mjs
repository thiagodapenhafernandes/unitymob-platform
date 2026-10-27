import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import vm from 'node:vm'
const context = vm.createContext({ Controller: class {} })
vm.runInContext(readFileSync('app/javascript/controllers/stage_conversion_controller.js', 'utf8')
  .replace(/^import .*\n/gm, '').replace('export default class', 'this.Conversion = class'), context)
function controller(event, disabled = false) {
 const c = new context.Conversion()
 c.eventTarget = { value: event, disabled }
 c.actionsValue = { visit: 'visit_completed' }
 const options = ['stage_entered','qualified','visit_completed','deal_closed'].map(value => ({value,disabled:false}))
 c.triggerTarget = { value: 'qualified', options, selectedOptions: [options[1]] }
 return c
}
test('Google permits only stage entry or the matching operational action', () => {
 const c=controller('visit');c.sync()
 assert.equal(c.triggerTarget.disabled,false)
 assert.equal(c.triggerTarget.options[1].disabled,true)
 assert.equal(c.triggerTarget.options[2].disabled,false)
 assert.equal(c.triggerTarget.value,'stage_entered')
})
test('missing integration and no event keep the action disabled without deleting its value', () => {
 for (const c of [controller('visit',true),controller('none')]) {
  c.sync();assert.equal(c.triggerTarget.disabled,true);assert.equal(c.triggerTarget.value,'qualified')
 }
})
test('Meta permits any explicitly configured action', () => {
 const c=controller('Schedule');c.actionsValue={};c.sync()
 assert.equal(c.triggerTarget.options.every(option=>!option.disabled),true)
 assert.equal(c.triggerTarget.value,'qualified')
})
