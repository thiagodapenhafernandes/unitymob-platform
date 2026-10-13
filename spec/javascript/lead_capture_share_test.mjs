import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

function setup(token) {
  const opened = [];
  const context = vm.createContext({Controller: class {}, document: {body: {style: {}}},
    window: {open: (...args) => opened.push(args)}, setTimeout: () => {}});
  vm.runInContext(readFileSync('app/javascript/controllers/lead_capture_controller.js', 'utf8')
    .replace(/^import .*\n/gm, '').replace('export default class', 'this.Capture = class'), context);
  const controller = new context.Capture();
  for (const field of ['propertyId', 'leadType', 'origin', 'shareToken']) {
    controller[`has${field[0].toUpperCase()}${field.slice(1)}Target`] = true;
    controller[`${field}Target`] = {};
  }
  controller.modalTarget = {classList: {remove: value => opened.push(value)}};
  controller.requiresLeadForm = () => false;
  controller.whatsappUrlFor = () => 'https://wa.me/central';
  controller.fetchWhatsappRouting = async () => ({capture_required: false, whatsapp_url: 'https://wa.me/central'});
  controller.shareTokenValue = token || '';
  return {controller, opened};
}

test('token da página ou do card força captura mesmo com formulário geral desativado', async () => {
  for (const fromCard of [true, false]) {
    const {controller, opened} = setup(fromCard ? '' : 'broker-page-pagina');
    await controller.open({preventDefault(){}, stopPropagation(){}, currentTarget: {
      dataset: {propertyId: '123', ...(fromCard ? {shareToken: 'broker-page-card'} : {})}}});
    assert.equal(controller.shareTokenTarget.value, fromCard ? 'broker-page-card' : 'broker-page-pagina');
    assert.equal(controller.propertyIdTarget.value, '123');
    assert.deepEqual(opened, ['hidden']);
  }
});

test('sem vínculo mantém o acesso direto ao WhatsApp configurado', async () => {
  const {controller, opened} = setup('');
  await controller.open({preventDefault(){}, stopPropagation(){}, currentTarget: {dataset: {propertyId: '123'}}});
  assert.deepEqual(opened, [['https://wa.me/central', '_blank']]);
});

test('token de compartilhamento comum não recebe a nova captura obrigatória', async () => {
  const {controller, opened} = setup('token-comum');
  await controller.open({preventDefault(){}, stopPropagation(){}, currentTarget: {dataset: {propertyId: '123'}}});
  assert.deepEqual(opened, [['https://wa.me/central', '_blank']]);
});
