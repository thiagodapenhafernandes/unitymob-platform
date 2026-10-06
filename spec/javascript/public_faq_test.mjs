import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

test('FAQ combines category and accent-insensitive search, hides empty groups and can reset', () => {
  const context = vm.createContext({ Controller: class {} });
  vm.runInContext(readFileSync('app/javascript/controllers/public_faq_controller.js', 'utf8').replace(/^import .*\n/gm, '').replace('export function', 'function').replace('export default class', 'this.FAQ = class'), context);
  const items = [{ dataset: { categories: 'Compra, Documentação' }, textContent: 'Documentação e ITBI' }, { dataset: { categories: 'Locação' }, textContent: 'Aluguel garantido' }];
  const groups = items.map(item => ({ querySelectorAll: () => [item] }));
  const empty = {};
  const filters = ['', 'Compra', 'Locação'].map(category => ({ dataset: { category }, setAttribute(name, value) { this[name] = value; } }));
  const element = { querySelector: () => empty, querySelectorAll(selector) { return selector.includes('filter') ? filters : selector.includes('group') ? groups : items; } };
  context.applyFAQFilters(element, 'Compra', 'documentacao');
  assert.equal(items[0].hidden, false); assert.equal(items[1].hidden, true);
  assert.equal(groups[1].hidden, true); assert.equal(filters[1]['aria-pressed'], 'true');
  context.applyFAQFilters(element, 'Compra', 'aluguel');
  assert.equal(empty.hidden, false); assert.equal(groups[0].hidden, true);
  context.applyFAQFilters(element, '', '');
  assert.equal(items.every(item => !item.hidden), true); assert.equal(empty.hidden, true);
});
