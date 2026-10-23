import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const source = readFileSync('app/javascript/controllers/broker_share_controller.js', 'utf8')
  .replace(/^import .*\n/gm, '').replace('export default class', 'this.Share = class');

function setup({ native = false, blocked = false, url = 'https://example.test/i/opaque' } = {}) {
  const calls = [];
  const popup = { opener: {}, close: () => calls.push('close'), location: { replace: value => calls.push(value) } };
  const context = vm.createContext({ Controller: class {}, encodeURIComponent,
    window: { Capacitor: { isNativePlatform: () => native },
      open: () => { calls.push('open'); return blocked ? null : popup; },
      location: { assign: value => calls.push(value) } } });
  vm.runInContext(source, context);
  const controller = new context.Share();
  controller.propertyTitleValue = 'Apartamento';
  controller.ensureSharedUrl = async () => { calls.push('generate'); return url; };
  return { controller, calls, popup };
}

test('reserves the tab before generating the share URL and removes opener', async () => {
  const { controller, calls, popup } = setup();
  await controller.whatsapp({ preventDefault() {}, stopPropagation() {} });
  assert.deepEqual(calls.slice(0, 2), ['open', 'generate']);
  assert.equal(popup.opener, null);
  assert.match(calls.at(-1), /^https:\/\/wa.me\/\?text=Apartamento%20https/);
});

test('native app and blocked popup use same-window navigation', async () => {
  for (const options of [{ native: true }, { blocked: true }]) {
    const { controller, calls } = setup(options);
    await controller.whatsapp({ preventDefault() {}, stopPropagation() {} });
    assert.match(calls.at(-1), /^https:\/\/wa.me\//);
    if (options.native) assert.equal(calls.includes('open'), false);
  }
});

test('failed generation closes the reserved tab', async () => {
  const { controller, calls } = setup({ url: null });
  await controller.whatsapp({ preventDefault() {}, stopPropagation() {} });
  assert.deepEqual(calls, ['open', 'generate', 'close']);
});
