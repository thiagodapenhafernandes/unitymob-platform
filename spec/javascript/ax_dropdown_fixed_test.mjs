import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
const events = [];
const ctx = vm.createContext({
  AxPopoverController: class { listen() {} stopListening() {} },
  window: { innerHeight: 600, addEventListener: (...args) => events.push(args[0]), removeEventListener() {}, setTimeout() {}, clearTimeout() {} },
  document: { addEventListener: (...args) => events.push(args[0]), removeEventListener() {} }
});
vm.runInContext(readFileSync('app/javascript/controllers/ax_dropdown_controller.js','utf8').replace(/^import .*\n/, '').replace('export default class','this.Dropdown = class'),ctx);
function dropdown(fixed) {
  const c = new ctx.Dropdown();
  c.fixedValue = fixed; c.closePeers = () => {};
  c.element = { classList: { add() {}, remove() {} }, closest: () => null };
  c.hasTriggerTarget = true;
  c.triggerTarget = { setAttribute() {}, getBoundingClientRect: () => ({right: 500, bottom: 580}) };
  c.menuTarget = { hidden: true, style: {}, offsetWidth: 200, offsetHeight: 150, querySelectorAll: () => [], getBoundingClientRect() {} };
  return c;
}
test('fixed menus fit in viewport and listen for scrolling and resizing', () => {
  events.length = 0; const c = dropdown(true); c.open();
  assert.equal(c.menuTarget.style.position, 'fixed');
  assert.equal(c.menuTarget.style.left, '300px');
  assert.equal(c.menuTarget.style.top, '442px');
  assert.deepEqual(events, ['resize','scroll']);
});
test('existing dropdowns retain their positioning by default', () => {
  events.length = 0; const c = dropdown(false); c.open();
  assert.equal(c.menuTarget.style.position, undefined);
  assert.equal(events.length, 0);
});
