import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

test('WhatsApp validates required fields and sends only visible typed values to the configured wa.me number', () => {
  const opened = [];
  const context = vm.createContext({ Controller: class {}, URL, window: { open: (...args) => opened.push(args) } });
  vm.runInContext(readFileSync('app/javascript/controllers/public_form_modal_controller.js', 'utf8').replace(/^import .*\n/gm, '').replace('export default class', 'this.Form = class'), context);
  const controller = new context.Form();
  const fields = [{ querySelector: () => ({ textContent: 'Interesse' }), querySelectorAll: () => [
    { type: 'radio', checked: true, value: 'venda', tagName: 'INPUT' }, { type: 'radio', checked: false, value: 'locacao', tagName: 'INPUT' }, { type: 'hidden', value: 'secret' }, { type: 'file', value: '/private' }
  ] }];
  controller.element = { closest: () => null };
  controller.hasFormTarget = true;
  controller.whatsappUrlValue = 'https://wa.me/5547999999999';
  controller.formTarget = { dataset: { publicFormTitle: 'Anunciar imóvel' }, reportValidity: () => false, querySelectorAll: () => fields };
  controller.whatsapp(); assert.equal(opened.length, 0);
  controller.formTarget.reportValidity = () => true;
  controller.whatsapp(); assert.equal(opened.length, 1);
  const url = new URL(opened[0][0]);
  assert.equal(url.hostname, 'wa.me'); assert.equal(url.searchParams.get('text'), 'Anunciar imóvel\nInteresse: venda');
  assert.equal(opened[0][2], 'noopener,noreferrer');
  controller.whatsappUrlValue = 'https://evil.test/5547999999999'; controller.whatsapp();
  assert.equal(opened.length, 1);
});
