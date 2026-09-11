const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const script = fs.readFileSync(path.join(__dirname, '../www/app.js'), 'utf8');
const startup = fs.readFileSync(path.join(__dirname, '../www/index.html'), 'utf8').match(/<script>([\s\S]*?)<\/script>/)[1];

function login(tenant) {
  const elements = new Map();
  let submitted = false;
  const storage = new Map();
  const element = () => ({ value: 'test', innerHTML: '', style: {}, classList: { add() {}, remove() {}, toggle() {} }, addEventListener(event, cb) { this[event] = cb; }, setAttribute() {}, appendChild() {}, submit() { submitted = true; } });
  const document = { getElementById(id) { if (!elements.has(id)) elements.set(id, element()); return elements.get(id); }, createElement: element, body: element(), documentElement: element() };
  vm.runInNewContext(script, { URL, document, window: {}, localStorage: { setItem: (k, v) => storage.set(k, v) }, fetch: async url => { assert.equal(url, 'https://webhooks.unitymob.com.br/discovery/resolve'); return { ok: true, json: async () => ({ tenant_url: tenant }) }; } });
  return { run: () => elements.get('login-form').submit({ preventDefault() {} }), submitted: () => submitted, storage };
}

for (const tenant of ['http://example.com', 'javascript:alert(1)', 'https://user:secret@example.com', 'invalid']) {
  test(`rejects unsafe discovery destination ${tenant}`, async () => {
    const app = login(tenant); await app.run();
    assert.equal(app.submitted(), false); assert.equal(app.storage.size, 0);
  });
}
test('HTTPS discovery permits login and remembers tenant', async () => {
  const app = login('https://example.com'); await app.run();
  assert.equal(app.submitted(), true); assert.equal(app.storage.get('unitymob_tenant_url'), 'https://example.com');
});
for (const [tenant, expected] of [['http://example.com', null], ['https://example.com', 'https://example.com/field']]) {
  test(`saved tenant navigation ${tenant}`, () => {
    let destination = null, removed = false;
    vm.runInNewContext(startup, { URL, URLSearchParams, window: { location: { search: '', replace: url => destination = url } }, document: { documentElement: { classList: { add() {} } } }, localStorage: { getItem: () => tenant, removeItem: () => removed = true } });
    assert.equal(destination, expected); assert.equal(removed, expected === null);
  });
}
