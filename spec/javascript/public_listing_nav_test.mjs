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
  const cardLink = { href: '/imoveis/apto-centro', getAttribute: (name) => name === 'data-turbo-frame' ? '_top' : null };
  const { event, prevented } = fakeEvent(cardLink);
  c.follow(event);
  assert.equal(prevented(), false);
  assert.equal(visited, null);
});

test('follow intercepta paginação/ordenação dentro do frame', () => {
  const c = new ctx.Nav();
  let visited = null;
  c.go = (url) => { visited = url; };
  const pageLink = { href: '/imoveis?page=2', getAttribute: () => null };
  const { event, prevented } = fakeEvent(pageLink);
  c.follow(event);
  assert.equal(prevented(), true);
  assert.equal(visited, '/imoveis?page=2');
});
