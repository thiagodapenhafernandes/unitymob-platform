import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFileSync } from 'node:fs';

function setup({ category = 'Terreno', comparison = 'street', complement = '', unit = '', developmentCode = '' } = {}) {
  const requests = [];
  const context = vm.createContext({ Controller: class {}, AbortController, URLSearchParams, setTimeout, clearTimeout, console,
    fetch: (url, options) => new Promise(resolve => requests.push({ url, options, resolve: data => resolve({ json: async () => data }) }))
  });
  vm.runInContext(readFileSync('app/javascript/controllers/habitation_duplicate_check_controller.js', 'utf8')
    .replace(/^import .*\n/, '').replace('export default class', 'this.Check = class'), context);
  const controller = new context.Check();
  for (const [name, value] of Object.entries({ category, comparison, complement, unit, developmentCode, street: 'Avenida Marcio Ferreira de Mello e Silva', number: '55', commercialStatus: 'Venda' })) {
    controller[`${name}Target`] = { value };
    controller[`has${name[0].toUpperCase()}${name.slice(1)}Target`] = true;
  }
  controller.urlValue = '/check'; controller.requestVersion = 0;
  controller.showDuplicate = () => { controller.notice = 'duplicate'; };
  controller.showAvailable = controller.clearStatus = () => { controller.notice = ''; };
  controller.toggleSubmit = disabled => { controller.disabled = disabled; };
  return { controller, requests };
}

test('a new terrain draft switches from street to unit identity for Lote E and E', async () => {
  const { controller, requests } = setup();
  assert.equal(controller.comparisonValue(), 'street');
  for (const complement of ['Lote E', 'E']) {
    controller.complementTarget.value = complement;
    const pending = controller.check();
    const request = requests.at(-1);
    const params = new URL(request.url, 'https://example.test').searchParams;
    assert.equal(params.get('category'), 'Terreno');
    assert.equal(params.get('comparison'), 'condominium_unit');
    assert.equal(params.get('complement'), complement);
    request.resolve({ duplicate: false, matches: [] }); await pending;
    assert.equal(controller.disabled, false);
  }
});

test('removing the complement restores the street rule even on an already saved draft', () => {
  const { controller } = setup({ comparison: 'condominium_unit', complement: 'Lote E' });
  controller.complementTarget.value = '';
  assert.equal(controller.comparisonValue(), 'street');
});

test('apartments and linked developments keep their unit rule and real duplicates block advancement', async () => {
  for (const options of [{ category: 'Apartamento', comparison: 'unit', unit: '101' }, { category: 'Terreno', complement: 'Lote E', unit: 'E', developmentCode: '4652' }]) {
    const { controller, requests } = setup(options);
    assert.equal(controller.comparisonValue(), 'unit');
    const pending = controller.check(); requests[0].resolve({ duplicate: true, matches: [{ codigo: '1030' }] }); await pending;
    assert.equal(controller.disabled, true);
  }
});

test('an old duplicate response cannot override a newer available result', async () => {
  const { controller, requests } = setup();
  const old = controller.check();
  controller.complementTarget.value = 'Lote E';
  const current = controller.check();
  requests[1].resolve({ duplicate: false }); await current;
  requests[0].resolve({ duplicate: true }); await old;
  assert.equal(controller.disabled, false);
  assert.equal(requests[0].options.signal.aborted, true);
});

test('changing a field invalidates a response even during the debounce interval', async () => {
  const { controller, requests } = setup();
  const pending = controller.check();
  controller.complementTarget.value = 'Lote E'; controller.schedule();
  requests[0].resolve({ duplicate: true }); await pending;
  assert.notEqual(controller.disabled, true);
  controller.disconnect();
});

test('disconnecting prevents a late response from touching the form', async () => {
  const { controller, requests } = setup();
  const pending = controller.check(); controller.disconnect();
  requests[0].resolve({ duplicate: true }); await pending;
  assert.equal(controller.disabled, undefined);
});

test('reconnecting the same controller does not accept a response from its previous connection', async () => {
  const { controller, requests } = setup();
  const old = controller.check(); controller.disconnect(); controller.connect();
  requests[0].resolve({ duplicate: true }); await old;
  assert.equal(controller.disabled, undefined);
  controller.disconnect();
  requests[1].resolve({ duplicate: false });
});

test('Casa em Condomínio 1 G uses the complement even with a linked development, in sale and rental', async () => {
  const { controller, requests } = setup({ category: 'Casa em Condomínio', complement: '1 G', developmentCode: '1074', comparison: 'street' });
  for (const status of ['Venda', 'Aluguel']) {
    controller.commercialStatusTarget.value = status;
    const pending = controller.check();
    const request = requests.at(-1);
    const params = new URL(request.url, 'https://example.test').searchParams;
    assert.equal(params.get('category'), 'Casa em Condomínio');
    assert.equal(params.get('comparison'), 'condominium_unit');
    assert.equal(params.get('complement'), '1 G');
    assert.equal(params.get('development_code'), '1074');
    assert.equal(params.get('status'), status);
    request.resolve({ duplicate: false }); await pending;
    assert.equal(controller.disabled, false);
  }
});
