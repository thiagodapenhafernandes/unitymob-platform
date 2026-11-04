import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import vm from 'node:vm'

function setup(value, start = value.length, end = start) {
  const document = {}
  const context = vm.createContext({ Controller: class {}, document })
  vm.runInContext(readFileSync('app/javascript/controllers/mask_controller.js', 'utf8')
    .replace(/^import .*\n/gm, '').replace('export default class', 'this.Mask = class'), context)
  const subject = new context.Mask()
  const listeners = new Set()
  let writes = 0
  const element = {
    get value() { return value },
    set value(next) { writes++; value = next; this.selectionStart = this.selectionEnd = next.length },
    selectionStart: start, selectionEnd: end,
    setSelectionRange(start, end) { this.selectionStart = start; this.selectionEnd = end },
    addEventListener(_, listener) { listeners.add(listener) },
    removeEventListener(_, listener) { listeners.delete(listener) }
  }
  subject.element = document.activeElement = element
  subject.typeValue = 'currency'
  return { subject, element, listeners, writes: () => writes }
}

test('preserva cursor e seleção quando o valor já está formatado', () => {
  const { subject, element, writes } = setup('7.200,00', 2, 4)
  subject.currencyMask()
  assert.equal(writes(), 0)
  assert.equal(element.selectionStart, 2)
  assert.equal(element.selectionEnd, 4)
})

test('preserva posição entre dígitos ao inserir e apagar no meio do valor', () => {
  for (const [value, caret, expected, position] of [
    ['79.200,00', 2, '79.200,00', 2],
    ['7.20,00', 3, '720,00', 2],
    ['72.200,00', 3, '72.200,00', 3],
    ['1234', 4, '12,34', 5],
    ['0001', 4, '0,01', 4],
    ['', 0, '', 0]
  ]) {
    const { subject, element } = setup(value, caret)
    subject.currencyMask()
    assert.equal(element.value, expected)
    assert.equal(element.selectionStart, position)
  }
})

test('remove o mesmo evento ao desconectar e não acumula eventos na reconexão', () => {
  const { subject, listeners } = setup('7.200,00')
  subject.connect()
  assert.equal(listeners.size, 1)
  subject.disconnect()
  assert.equal(listeners.size, 0)
  subject.connect()
  assert.equal(listeners.size, 1)
})

test('apagar o separador não prende o cursor antes do próximo dígito', () => {
  for (const [inputType, expected] of [['deleteContentBackward', 1], ['deleteContentForward', 2]]) {
    const { subject, element } = setup('7200,00', 1)
    subject.input({ inputType })
    assert.equal(element.value, '7.200,00')
    assert.equal(element.selectionStart, expected)
  }
})

test('mantém as máscaras vizinhas de CEP, CPF e CNPJ', () => {
  for (const [type, value, expected] of [
    ['cep', '88330000', '88330-000'],
    ['cpf_cnpj', '12345678901', '123.456.789-01'],
    ['cpf_cnpj', '12345678000190', '12.345.678/0001-90']
  ]) {
    const { subject, element } = setup(value)
    subject.typeValue = type
    subject.mask()
    assert.equal(element.value, expected)
  }
})
