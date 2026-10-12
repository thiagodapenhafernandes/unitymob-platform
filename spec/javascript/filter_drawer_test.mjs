import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import vm from 'node:vm'
const ctx = vm.createContext({ Controller: class {}, document: { activeElement: null } })
vm.runInContext(readFileSync('app/javascript/controllers/filter_drawer_controller.js', 'utf8').replace(/^import .*\n/, '').replace('export default class', 'this.Drawer = class'), ctx)

function setup(low = 700000, high = 21400000) {
  const lo = { value: low, focus() { ctx.document.activeElement = this } }
  const hi = { value: high, focus() { ctx.document.activeElement = this } }
  const fill = { style: {} }, outLo = {}, outHi = {}, minInput = {}, maxInput = {}
  const track = {
    dataset: { min: '700000', max: '21400000', step: '100000', range: 'valor', money: '1' },
    querySelector: (s) => s.includes('lo') ? lo : s.includes('hi') ? hi : fill,
    closest: () => ({ querySelector: (s) => s.includes('out-lo') ? outLo : outHi }),
    getBoundingClientRect: () => ({ left: 0, width: 207 })
  }
  const controller = new ctx.Drawer()
  controller.element = { querySelector: (s) => s.includes('-min') ? minInput : maxInput }
  return { controller, track, lo, hi, minInput, maxInput }
}

test('clique na linha move o limite mais próximo e envia os reais escolhidos', () => {
  const { controller, track, lo, minInput, maxInput } = setup()
  controller.selectRangeValue({ button: 0, target: { matches: () => false }, currentTarget: track, clientX: 28 })
  assert.equal(lo.value, 3500000)
  assert.equal(minInput.value, 3500000)
  assert.equal(maxInput.value, '')
})

test('arraste nativo e teclado sincronizam o teto sem cruzar os limites', () => {
  const { controller, track, lo, hi, minInput, maxInput } = setup(700000, 3500000)
  controller.drawRangeTrack(track)
  assert.equal(maxInput.value, 3500000)
  lo.value = 4000000
  ctx.document.activeElement = lo
  controller.drawRangeTrack(track)
  assert.equal(hi.value, 4000000)
  assert.equal(minInput.value, 4000000)
  assert.equal(maxInput.value, 4000000)
})

test('clique no thumb mantém a interação nativa', () => {
  const { controller, track, lo } = setup()
  controller.selectRangeValue({ button: 0, target: { matches: () => true }, currentTarget: track, clientX: 28 })
  assert.equal(lo.value, 700000)
})
