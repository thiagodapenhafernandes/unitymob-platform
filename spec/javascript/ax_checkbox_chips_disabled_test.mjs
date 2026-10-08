import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

test('acompanha disabled alterado por painéis condicionais sem mudar a seleção', () => {
  let callback, disconnected = false;
  const state = { classes: {}, attributes: {}, dataset: {} };
  const chip = { classList: { toggle: (key, value) => state.classes[key] = value },
    setAttribute: (key, value) => state.attributes[key] = value,
    removeAttribute: key => delete state.attributes[key], dataset: state.dataset };
  const input = { checked: true, disabled: true, closest: () => chip };
  const element = { querySelectorAll: () => [input] };
  const ctx = vm.createContext({ Controller: class {}, requestAnimationFrame: () => 1, cancelAnimationFrame() {},
    MutationObserver: class { constructor(fn) { callback = fn; } observe(target, options) {
      assert.equal(target, element); assert.equal(options.attributeFilter[0], 'disabled');
    } disconnect() { disconnected = true; } } });
  vm.runInContext(readFileSync('app/javascript/controllers/ax_checkbox_chips_controller.js', 'utf8')
    .replace(/^import .*\n/, '').replace('export default class', 'this.Chips = class'), ctx);
  const controller = new ctx.Chips(); controller.element = element; controller.connect();
  assert.equal(state.attributes['aria-disabled'], 'true');
  input.disabled = false; callback();
  assert.equal(state.classes['is-disabled'], false); assert.equal(state.attributes['aria-disabled'], undefined);
  assert.equal(state.classes['is-checked'], true); assert.equal(input.checked, true);
  input.disabled = true; callback(); assert.equal(state.attributes['aria-disabled'], 'true');
  controller.disconnect(); assert.equal(disconnected, true);
});
