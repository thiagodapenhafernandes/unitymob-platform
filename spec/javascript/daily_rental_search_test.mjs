import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

function controller(name, globals = {}) {
  const context = vm.createContext({ Controller: class {}, ...globals });
  vm.runInContext(readFileSync(`app/javascript/controllers/${name}_controller.js`, 'utf8')
    .replace(/^import .*\n/gm, '').replace('export default class', 'this.Subject = class'), context);
  return new context.Subject();
}

for (const name of ['hero_search', 'search_tabs']) {
  test(`${name} switches daily, rental and sale price options`, () => {
    const c = controller(name, {
      Option: function (label, value) { this.textContent = label; this.value = value; },
      document: { createElement: () => ({}) }
    });
    const select = { value: '', dataset: {}, options: [], set innerHTML(value) { this.options = []; },
      append(option) { this.options.push(option); }, appendChild(option) { this.options.push(option); } };
    c.hasPriceSelectTarget = true;
    c.priceSelectTarget = select;
    c.dailyPriceOptionsValue = [['Todos', ''], ['Até R$ 500', '0-500']];
    c.rentPriceOptionsValue = [['Todos', ''], ['Até R$ 5 mil', '0-5000']];
    c.salePriceOptionsValue = [['Todos', ''], ['Até R$ 1 mi', '0-1000000']];
    for (const [transaction, expected] of [['diaria', '0-500'], ['aluguel', '0-5000'], ['venda', '0-1000000']]) {
      c.updatePriceOptions(transaction);
      assert.equal(select.options[1].value, expected);
    }
  });
}

test('drawer chooses daily bounds and preserves rental and sale bounds', () => {
  const c = controller('filter_drawer');
  const track = { dataset: { dailyMin: '0', dailyMax: '10000', dailyStep: '50', rentalMin: '5000', rentalMax: '50000', rentalStep: '1000', saleMin: '1000000', saleMax: '50000000', saleStep: '100000' } };
  c.formTarget = { querySelector: () => track };
  let actual;
  c.configureRangeTrack = (_, bounds) => { actual = bounds; };
  for (const [transaction, min, step] of [['diaria', 0, 50], ['aluguel', 5000, 1000], ['venda', 1000000, 100000]]) {
    c.syncPriceRangeForTransaction(transaction);
    assert.equal(actual.min, min);
    assert.equal(actual.step, step);
  }
});

test('luxury switches the submitted transaction and replaces the price combobox', () => {
  const c = controller('salute_luxury_theme');
  const button = { dataset: { transactionType: 'diaria' }, setAttribute(name, value) { this[name] = value; } };
  const cloned = {};
  c.transactionButtonTargets = [button];
  c.hasTransactionInputTarget = true;
  c.transactionInputTarget = {};
  c.hasPriceFieldTarget = true;
  c.priceTemplateTargets = [{ dataset: { transactionType: 'diaria' }, content: { cloneNode: () => cloned } }];
  let inserted;
  c.priceFieldTarget = { replaceChildren(node) { inserted = node; } };
  c.setTransaction({ currentTarget: button });
  assert.equal(c.transactionInputTarget.value, 'diaria');
  assert.equal(button['aria-pressed'], 'true');
  assert.equal(inserted, cloned);
});
