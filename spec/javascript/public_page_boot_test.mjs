import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

for (const readyState of ['loading', 'complete']) {
  test(`gallery loads even when turbo:load was missed (${readyState})`, async () => {
    const listeners = new Map();
    const registered = [];
    const source = readFileSync('app/javascript/public.js', 'utf8')
      .replace(/^import .*$/gm, '')
      .replace(/^application.register\(.*$/gm, '')
      .replace(/import\("[^"]+"\)/g, 'Promise.resolve({ default: class {} })');
    const context = vm.createContext({
      Turbo: { session: {} },
      document: { readyState, addEventListener: (name, fn) => listeners.set(name, fn),
        querySelector: selector => selector.includes('fancybox-gallery') ? {} : null },
      application: { register: name => registered.push(name) }, console
    });
    vm.runInContext(source, context);
    if (readyState === 'loading') listeners.get('DOMContentLoaded')();
    await Promise.resolve();
    assert.deepEqual(registered, ['fancybox-gallery']);
    listeners.get('turbo:load')();
    await Promise.resolve();
    assert.deepEqual(registered, ['fancybox-gallery']);
  });
}
