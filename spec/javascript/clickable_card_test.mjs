import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
const ctx = vm.createContext({ Controller: class {} });
vm.runInContext(readFileSync('app/javascript/controllers/clickable_card_controller.js', 'utf8').replace(/^import .*\n/gm, '').replace('export default class', 'this.Card = class'), ctx);

test('card navega uma vez mesmo dentro de um ancestral com data-action; controles e swipe não navegam', () => {
  const card = new ctx.Card();
  const outerAction = {}, innerButton = {};
  let clicks = 0;
  card.urlValue = '/imoveis/apartamento';
  card.element = { contains: node => node === innerButton, querySelector: () => ({ click: () => clicks++ }) };
  const event = node => ({ target: { closest: selector => selector.startsWith('a,') ? node : null } });
  card.handleClick(event(outerAction));
  assert.equal(clicks, 1);
  card.handleClick(event(innerButton));
  assert.equal(clicks, 1);
  card.isDragging = true;
  card.handleClick(event(outerAction));
  assert.equal(clicks, 1);
});

 test('fallback respeita Drive desativado no público e ativado no admin', () => {
  const card = new ctx.Card();
  card.element = { contains: () => false, querySelector: () => null };
  card.urlValue = '/imoveis/apartamento';
  const visits = [];
  ctx.Turbo = { session: { drive: false }, visit: url => visits.push(['turbo', url]) };
  ctx.window = { location: { assign: url => visits.push(['document', url]) } };
  const event = { target: { closest: () => null } };
  card.handleClick(event);
  ctx.Turbo.session.drive = true;
  card.handleClick(event);
  assert.deepEqual(visits, [['document', card.urlValue], ['turbo', card.urlValue]]);
});
