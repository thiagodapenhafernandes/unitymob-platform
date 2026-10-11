import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import vm from 'node:vm'

const context = vm.createContext({ Controller: class {} })
vm.runInContext(readFileSync('app/javascript/controllers/lead_status_board_controller.js', 'utf8')
  .replace(/^import .*\n/gm, '').replace('export default class', 'this.Board = class'), context)

function stage(id, name) {
  const field = { value: name }
  return { dataset: { id }, querySelector: () => field, field }
}
function select(kind, values, tomselect = null) {
  return { dataset: { leadStatusStageOptions: kind }, options: values.map(([value, textContent]) => ({ value, textContent })), tomselect }
}
function container(selects = [], templates = []) {
  return { querySelectorAll: selector => selector.includes('automation-template') ? templates : selects }
}

test('renames native and Tom Select destinations and future automation templates without changing IDs or selections', () => {
  const board = new context.Board()
  const source = stage('10', 'Contato <novo>')
  const destination = stage('20', 'Proposta revisada')
  board.rows = () => [source, destination, stage('', 'Nova etapa sem ID')]
  board.pipelineNameTarget = { value: 'Venda atualizada' }
  const updates = []
  const tomselect = { items: ['20'], options: { '20': { value: '20', text: 'Proposta', $order: 4 } },
    updateOption: (id, data) => { updates.push([id, data]); tomselect.options[id] = data } }
  const multi = select('plain', [['20', 'Proposta']], tomselect)
  const automation = select('qualified', [['10', 'Venda · Contato'], ['90', 'Pós-venda · Reativar']])
  const replacement = select('plain', [['10', 'Contato']])
  const nested = select('qualified', [['20', 'Venda · Proposta']])
  const futureTemplate = { content: container([automation]) }
  const nestedTemplate = { content: container([nested]) }
  board.element = container([multi, replacement])
  board.listTarget = container([], [futureTemplate])
  board.templateTarget = { content: container([], [nestedTemplate]) }

  board.refreshStageOptions()

  assert.equal(multi.options[0].textContent, 'Proposta revisada')
  assert.equal(replacement.options[0].textContent, 'Contato <novo>')
  assert.equal(automation.options[0].textContent, 'Venda atualizada · Contato <novo>')
  assert.equal(automation.options[1].textContent, 'Pós-venda · Reativar')
  assert.equal(nested.options[0].textContent, 'Venda atualizada · Proposta revisada')
  assert.deepEqual(tomselect.items, ['20'])
  assert.equal(updates[0][1].value, '20')
  assert.equal(updates[0][1].$order, 4)
  board.refreshStageOptions()
  assert.equal(updates.length, 1)
})

test('switching stages hides panels without moving, rebuilding or resetting their fields', () => {
  const board = new context.Board()
  const panels = [stage('10', 'Nome ainda não salvo'), stage('20', 'Outro nome')]
  const buttons = panels.map(() => ({ active: false, pressed: null,
    classList: { toggle(_name, active) { this.button.active = active } },
    setAttribute(_name, value) { this.pressed = value } }))
  buttons.forEach(button => { button.classList.button = button })
  board.rows = () => panels
  board.navigationItems = new Map(panels.map((panel, index) => [panel, { querySelector: () => buttons[index] }]))
  board.openRow(panels[1])
  assert.equal(panels[0].hidden, true)
  assert.equal(panels[1].hidden, false)
  assert.equal(buttons[1].pressed, 'true')
  board.openRow(panels[0])
  assert.equal(panels[0].field.value, 'Nome ainda não salvo')
  assert.equal(buttons[0].active, true)
  assert.equal(buttons[1].active, false)
})

test('automation payload retains inactive rules and deletion markers and excludes hidden action configurations', () => {
  const board = new context.Board()
  function rule(id, action, active, destroy) {
    const inputs = { trigger: { value: 'customer_inactivity' }, after_amount: { value: '2' }, after_unit: { value: 'days' },
      auto_advance_to_stage_id: { value: '20' }, action_type: { value: action }, active: { checked: active } }
    const configs = [['task_title', 'Retomar atendimento', false], ['due_in_days', '3', false], ['note', 'Nota mantida', null], ['distribution_rule_id', '40', true]]
      .map(([name, value, hidden]) => ({ dataset: { leadStatusAutomationConfigField: name }, value,
        closest: () => hidden === null ? null : { hidden } }))
    return { dataset: { automationId: id, destroy }, querySelector: selector => inputs[selector.match(/="([^"]+)"/)[1]], querySelectorAll: () => configs }
  }
  const rules = [rule('1', 'create_task', false, 'false'), rule('2', 'move_stage', true, 'true')]
  const payload = JSON.parse(JSON.stringify(board.automationsFor({ querySelectorAll: () => rules })))
  assert.equal(payload[0].active, false)
  assert.equal(payload[0].after_unit, 'days')
  assert.deepEqual(payload[0].action_config, { task_title: 'Retomar atendimento', due_in_days: '3', note: 'Nota mantida' })
  assert.equal(payload[1]._destroy, true)
  assert.equal(payload[1].auto_advance_to_stage_id, '20')
})
