import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const fields = { stape_identifier: '3ceniiuiwsxi', stape_configuration: 'dxfrp44=ABC123', stape_domain: 'https://gtm.saluteimoveis.com.br', stape_loader_domain: 'https://load.gtm.saluteimoveis.com.br' };
const source = readFileSync('app/views/layouts/_stape_loader.html.erb', 'utf8')
  .replace(/<%#[\s\S]*?%>/g, '')
  .replace(/<%= raw json_escape\(tracking_setting\.(\w+)\.to_json\) %>/g, (_, field) => JSON.stringify(fields[field]));
function load(userAgent, cookie = '', blocked = false) {
  const urls = [], w = {};
  const document = { get cookie() { if (blocked) throw new Error('Denied'); return cookie; } };
  vm.runInNewContext(source, { w, document, navigator: { userAgent }, loadScript: url => urls.push(url), console: { warn() {} } });
  assert.equal(w.dataLayer.length, 1);
  assert.equal(w.dataLayer[0].event, 'gtm.js');
  assert.equal(urls.length, 1);
  return urls[0];
}

test('Chrome and Safari without UID use the ordinary loader', () => {
  const expected = 'https://load.gtm.saluteimoveis.com.br/3ceniiuiwsxi.js?dxfrp44=ABC123';
  assert.equal(load('Chrome/130'), expected);
  assert.equal(load('Version/17.0 Mobile Safari/605.1'), expected);
  assert.equal(load('Version/16.3 Safari/605.1', 'si_uid=TEST'), expected);
});

test('Safari 16.4+ with UID uses the proxy and encodes the cookie', () => {
  assert.equal(load('Version/17.0 Mobile Safari/605.1', 'other=x; si_uid=test+uid'),
    'https://gtm.saluteimoveis.com.br/3cenkpiiuiwsxi.js?dxfrp44=ABC123&bi=test%2Buid');
});

test('blocked cookies fall back without stopping the loader', () => {
  assert.match(load('Version/17.0 Safari/605.1', '', true), /^https:\/\/load\.gtm\./);
});
