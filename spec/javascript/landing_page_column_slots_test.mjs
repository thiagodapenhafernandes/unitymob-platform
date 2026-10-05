import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

test('column invitations appear only for empty columns and return after removal', () => {
  const slots = [];
  const context = vm.createContext({ Controller: class {}, document: {
    createElement: () => ({ dataset: {}, append(button) { this.button = button; },
      after(node) { if (node.className === 'lp-column-slots') slots.push(node); } })
  } });
  vm.runInContext(readFileSync('app/javascript/controllers/landing_page_builder_controller.js', 'utf8')
    .replace(/^import .*\n/gm, '').replace('export default class', 'this.Builder = class'), context);
  const controller = new context.Builder();
  const makeBlock = (type, column = '1') => ({
    dataset: { blockType: type }, classList: { toggle() {} },
    querySelectorAll: () => [],
    querySelector(selector) {
      this.fields ||= {};
      return this.fields[selector] ||= { value: selector.includes('[columns]') ? '2' : selector.includes('[column]') ? column : '',
        options: [], closest: () => ({}) };
    },
    after(node) { if (node.className === 'lp-column-slots') slots.push(node); }
  });
  const section = makeBlock('section');
  let children = [makeBlock('gallery', '2'), makeBlock('text', '1')];
  controller.liveBlocks = () => [section, ...children];
  controller.sectionMembers = () => [section, ...children];
  controller.positionOf = () => '0';
  controller.listTarget = { querySelectorAll: () => { slots.length = 0; return []; } };
  controller.emptyTarget = { querySelector: () => ({}) };

  controller.reindex();
  assert.equal(slots.length, 0);
  children = children.filter(block => block.dataset.blockType !== 'text');
  controller.reindex();
  assert.equal(slots.length, 1);
  assert.equal(slots[0].button.textContent, 'Coluna 1 · Adicionar bloco nesta coluna');
  children.push(makeBlock('text', '1'));
  controller.reindex();
  assert.equal(slots.length, 0);
});
