import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const source = readFileSync('app/javascript/lib/clipboard.js', 'utf8').replace('export async function', 'async function');
function setup(clipboard = {}, legacyResult = false) {
  const calls = [];
  const input = { value: '', style: {}, setAttribute() {}, focus() {}, select() {}, setSelectionRange() {}, remove() { calls.push('removed'); } };
  const dialog = { appendChild() { calls.push('dialog'); } };
  const context = vm.createContext({ navigator: { clipboard }, Blob,
    ClipboardItem: class { constructor(data) { this.data = data; } },
    document: { activeElement: { focus() { calls.push('focus restored'); } },
      createElement: () => input, querySelector: () => dialog,
      execCommand() { return legacyResult; } },
    window: { prompt(message, text) { calls.push(['manual', text]); } } });
  vm.runInContext(source, context);
  return { copy: context.copyText, calls };
}

test('reserves clipboard during the click before the generated URL resolves', async () => {
  let resolveUrl, items;
  const url = new Promise(resolve => { resolveUrl = resolve; });
  const { copy } = setup({ write: value => { items = value; return value[0].data['text/plain'].then(() => {}); } });
  const result = copy(url);
  assert.ok(items, 'write must be called synchronously');
  resolveUrl('https://example.test/i/tracked');
  assert.equal(await (await items[0].data['text/plain']).text(), 'https://example.test/i/tracked');
  assert.equal(await result, true);
});

test('writes a ready URL synchronously with writeText', async () => {
  let written;
  const { copy } = setup({ writeText: text => { written = text; return Promise.resolve(); } });
  const result = copy('https://example.test/i/tracked');
  assert.equal(written, 'https://example.test/i/tracked');
  assert.equal(await result, true);
});

test('blocked API falls back inside the modal and restores focus', async () => {
  const { copy, calls } = setup({ writeText: () => Promise.reject(new Error('denied')) }, true);
  assert.equal(await copy('tracked'), true);
  assert.deepEqual(calls, ['dialog', 'removed', 'focus restored']);
});

test('failed legacy copy offers the actual URL without reporting success', async () => {
  const { copy, calls } = setup();
  assert.equal(await copy(Promise.resolve('tracked')), false);
  assert.deepEqual(calls.at(-1), ['manual', 'tracked']);
});

test('failed generation never copies an empty URL', async () => {
  const { copy, calls } = setup();
  assert.equal(await copy(Promise.resolve(null)), false);
  assert.equal(await copy(Promise.reject(new Error('failed'))), false);
  assert.deepEqual(calls, []);
});


test('a WebView rejecting write before consuming content handles failed generation', async () => {
  const { copy, calls } = setup({ write: () => Promise.reject(new Error('blocked')) });
  assert.equal(await copy(Promise.resolve(null)), false);
  assert.deepEqual(calls, []);
});
