import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
const ctx = vm.createContext({ Controller: class {} });
vm.runInContext(readFileSync('app/javascript/controllers/public_listing_nav_controller.js', 'utf8').replace(/^import .*\n/, '').replace('export default class', 'this.Nav = class'), ctx);

const fakeEvent = (link) => {
  let prevented = false;
  return {
    event: { target: { closest: () => link }, preventDefault: () => { prevented = true; } },
    prevented: () => prevented
  };
};

test('follow deixa links _top (cards) navegarem a página cheia', () => {
  const c = new ctx.Nav();
  let visited = null;
  c.go = (url) => { visited = url; };
  const cardLink = { href: '/imoveis/apto-centro', hasAttribute: () => false, getAttribute: (name) => name === 'data-turbo-frame' ? '_top' : null };
  const { event, prevented } = fakeEvent(cardLink);
  c.follow(event);
  assert.equal(prevented(), false);
  assert.equal(visited, null);
});

test('follow intercepta paginação/ordenação dentro do frame', () => {
  const c = new ctx.Nav();
  let visited = null;
  c.go = (url) => { visited = url; };
  const pageLink = { href: '/imoveis?page=2', hasAttribute: () => false, getAttribute: () => null };
  const { event, prevented } = fakeEvent(pageLink);
  c.follow(event);
  assert.equal(prevented(), true);
  assert.equal(visited, '/imoveis?page=2');
});


test('falha no carregar mais mantém o botão disponível para retry', async () => {
  const c = new ctx.Nav();
  ctx.fetch = async () => ({ ok: false });
  const status = { textContent: '' };
  const attributes = new Map();
  const link = { href: '/imoveis?page=2', closest: () => ({ querySelector: () => status }), setAttribute: (k,v) => attributes.set(k,v), removeAttribute: k => attributes.delete(k) };
  await c.loadMore({ preventDefault() {}, stopPropagation() {}, currentTarget: link });
  assert.equal(c.loadingMore, false);
  assert.equal(attributes.has('aria-disabled'), false);
  assert.match(status.textContent, /Tente novamente/);
});


test('carregar mais acrescenta na mesma grade e evita cards repetidos', async () => {
  const c = new ctx.Nav();
  c.frameValue = 'public-listing-grid';
  const status = { textContent: '' };
  const oldFooter = { isConnected: true, querySelector: () => status, replaceWith: node => { oldFooter.replacement = node; } };
  const newFooter = { querySelector: () => status };
  const newCard = { dataset: { propertyId: '2' }, setAttribute() {}, focus() {} };
  const grid = { children: [{ dataset: { propertyId: '1' } }], append(...cards) { this.children.push(...cards); } };
  const incoming = { querySelector: selector => selector === '.public-theme-property-grid' ? { children: [{ dataset: { propertyId: '1' } }, newCard] } : newFooter };
  c.element = { querySelector: () => grid };
  ctx.fetch = async () => ({ ok: true, text: async () => '<html></html>' });
  ctx.DOMParser = class { parseFromString() { return { querySelector: () => incoming }; } };
  const link = { href: '/imoveis?page=2', closest: () => oldFooter, setAttribute() {} };
  await c.loadMore({ preventDefault() {}, stopPropagation() {}, currentTarget: link });
  assert.equal(grid.children.length, 2);
  assert.equal(grid.children[1], newCard);
  assert.equal(oldFooter.replacement, newFooter);
  assert.equal(status.textContent, 'Mais imóveis carregados.');
});
