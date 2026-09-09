import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
const ctx = vm.createContext({ Controller: class {} });
vm.runInContext(readFileSync('app/javascript/controllers/ax_tabs_controller.js', 'utf8').replace(/^import .*\n/, '').replace('export default class', 'this.Tabs = class'), ctx);
test('reveals the active tab horizontally without moving the page', () => {
  const c = new ctx.Tabs(); c.revealActiveValue = true;
  c.element = { clientWidth: 364, scrollLeft: 0, getBoundingClientRect: () => ({left: 12, right: 376}) };
  const bounds = { left: 750, right: 900 };
  c.tabTargets = [{ getAttribute: () => 'true', getBoundingClientRect: () => bounds }];
  c.revealActiveTab(); assert.equal(c.element.scrollLeft, 524);
  bounds.left = -20; bounds.right = 80;
  c.revealActiveTab(); assert.equal(c.element.scrollLeft, 492);
});
test('leaves other tab consumers and invisible strips unchanged', () => {
  const c = new ctx.Tabs(); c.revealActiveValue = false;
  c.revealActiveTab();
  c.revealActiveValue = true; c.element = { clientWidth: 0, scrollLeft: 7 };
  c.revealActiveTab(); assert.equal(c.element.scrollLeft, 7);
});
