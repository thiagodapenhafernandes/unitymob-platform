import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

function picker(dates = ['2026-10-22', '2026-10-23', '2026-10-24']) {
  const ctx = vm.createContext({ Controller: class {} });
  vm.runInContext(readFileSync('app/javascript/controllers/ax_date_range_controller.js', 'utf8')
    .replace(/^import .*\n/gm, '').replace('export default class', 'this.Picker = class'), ctx);
  const c = new ctx.Picker();
  c.startTarget = { value: '' };
  c.endTarget = { value: '', setCustomValidity(message) { this.error = message; } };
  c.summaryTarget = {};
  c.hasMonthTarget = true;
  c.monthTarget = {};
  c.element = { querySelector: () => ({ dataset: { currentMonth: '2026-10' } }) };
  c.dayTargets = dates.map(date => ({ dataset: { date }, disabled: false, classes: {}, attributes: {},
    classList: { toggle(name, value) { this.owner.classes[name] = value; } },
    setAttribute(name, value) { this.attributes[name] = value; }, focus() { this.focused = true; } }));
  c.dayTargets.forEach(day => { day.classList.owner = day; });
  c.connect();
  return c;
}
const click = (c, index) => c.select({ currentTarget: c.dayTargets[index] });

test('two clicks select inclusive dates; a third starts a new selection; clear resets', () => {
  const c = picker(); click(c, 0);
  assert.equal(c.endTarget.value, ''); assert.match(c.summaryTarget.textContent, /último dia/);
  c.preview({ currentTarget: c.dayTargets[2] });
  assert.equal(c.dayTargets[1].classes['is-preview'], true);
  assert.equal(c.endTarget.value, '');
  c.clearPreview(); assert.equal(c.dayTargets[1].classes['is-selected'], false);
  click(c, 2); assert.equal(c.endTarget.value, '2026-10-24');
  assert.match(c.summaryTarget.textContent, /3 dias/);
  assert.equal(c.dayTargets[1].attributes['aria-pressed'], 'true');
  click(c, 1); assert.equal(c.startTarget.value, '2026-10-23'); assert.equal(c.endTarget.value, '');
  c.clear(); assert.equal(c.startTarget.value, ''); assert.equal(c.endTarget.value, '');
});

test('supports one-day periods, reverse selection and invalid typed dates', () => {
  const c = picker(); click(c, 2); click(c, 0);
  assert.equal(c.startTarget.value, '2026-10-22'); assert.equal(c.endTarget.value, '2026-10-24');
  c.clear(); click(c, 0); click(c, 0); assert.match(c.summaryTarget.textContent, /1 dia$/);
  c.startTarget.value = '2026-10-24'; c.endTarget.value = '2026-10-22'; c.change();
  assert.match(c.endTarget.error, /não pode ser anterior/);
});

test('month replacement preserves selection; dates do not shift across time zones or DST', () => {
  const c = picker(['2026-10-31', '2026-11-02']); click(c, 0);
  c.element.querySelector = () => ({ dataset: { currentMonth: '2026-11' } });
  c.refresh(); assert.equal(c.monthTarget.value, '2026-11'); assert.equal(c.startTarget.value, '2026-10-31');
  click(c, 1); assert.match(c.summaryTarget.textContent, /3 dias/);
});

test('blocked days cannot be endpoints, and arrow navigation skips them', () => {
  const c = picker(); c.dayTargets[1].disabled = true;
  click(c, 1); assert.equal(c.startTarget.value, '');
  c.navigate({ key: 'ArrowRight', currentTarget: c.dayTargets[0], preventDefault() {} });
  assert.equal(c.dayTargets[2].focused, true);
});
