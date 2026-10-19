import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFileSync } from 'node:fs';

function setup({ loaded = false } = {}) {
  const elements = [];
  const document = {
    querySelector: selector => elements.find(element => selector.startsWith(element.tag) && element.isConnected),
    createElement: tag => ({
      tag, dataset: {}, listeners: {}, sheet: loaded,
      addEventListener(event, callback) { this.listeners[event] = callback; },
      remove() { this.isConnected = false; },
    }),
    head: { appendChild(element) { element.isConnected = true; elements.push(element); } },
  };
  const context = vm.createContext({ document });
  vm.runInContext(readFileSync('app/javascript/lib/phone_input_styles.js', 'utf8')
    .replace('export function', 'function') + '\nthis.load = loadPhoneInputStyles;', context);
  return { load: context.load, elements, document };
}

test('waits for phone CSS before measuring and shares one load across fields', async () => {
  const { load, elements } = setup();
  let ready = false;
  const first = load();
  assert.equal(load(), first);
  first.then(() => { ready = true; });
  await Promise.resolve();
  assert.equal(ready, false);
  assert.equal(elements.filter(element => element.tag === 'link').length, 1);
  elements.find(element => element.tag === 'link').listeners.load();
  await first;
  assert.equal(ready, true);
});

test('reuses an already loaded stylesheet', async () => {
  const { load, elements, document } = setup({ loaded: true });
  document.head.appendChild(document.createElement('link'));
  await load();
  assert.equal(elements.filter(element => element.tag === 'link').length, 1);
});

test('a failed stylesheet can be retried without duplicating shared styles', async () => {
  const { load, elements } = setup();
  const failed = load();
  elements.find(element => element.tag === 'link').listeners.error();
  await assert.rejects(failed, /estilos do telefone/);
  const retry = load();
  elements.filter(element => element.tag === 'link').at(-1).listeners.load();
  await retry;
  assert.equal(elements.filter(element => element.tag === 'style').length, 1);
});
