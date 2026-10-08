import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

function setup(initial = {}, blocked = false) {
  const cookies = new Map(Object.entries(initial));
  const storage = new Map();
  const events = [];
  let reloads = 0;
  const document = {
    get cookie() { if (blocked) throw new Error("Cookies blocked"); return [...cookies].map(([key, value]) => `${key}=${value}`).join('; '); },
    set cookie(text) {
      if (blocked) throw new Error("Cookies blocked");
      const [key, value] = text.split(';')[0].split('=');
      if (text.includes('Max-Age=0')) cookies.delete(key); else cookies.set(key, value);
    }
  };
  const window = {
    localStorage: { getItem: key => storage.get(key), setItem: (key, value) => storage.set(key, value), removeItem: key => storage.delete(key) },
    dispatchEvent: event => events.push(event.type), addEventListener() {}, removeEventListener() {},
    location: { reload: () => reloads++ }
  };
  const context = vm.createContext({ document, window, Controller: class {}, CustomEvent: class { constructor(type) { this.type = type; } }, navigator: {} });
  function load(path, name) {
    const source = readFileSync(path, 'utf8').replace(/^import .*\n/gm, '').replace('export default class', `this.${name} = class`);
    vm.runInContext(source, context);
    return new context[name]();
  }
  const controller = load('app/javascript/controllers/lgpd_consent_controller.js', 'Consent');
  const target = () => ({ classList: { toggle() {}, add() {}, remove() {} }, querySelector: () => null });
  controller.bannerTarget = target(); controller.preferencesTarget = target();
  return { window, cookies, storage, events, controller, load, reloads: () => reloads };
}

test('expired or absent cookie does not revive an old localStorage acceptance', () => {
  const env = setup();
  env.storage.set('unitymob_lgpd_consent_v1', 'accepted');
  assert.equal(env.window.UnitymobLgpdConsent.accepted(), false);
});

test('accept, withdraw and reaccept preserve login and synchronize interest choice', () => {
  const env = setup({ login_session: 'keep' });
  env.controller.accept();
  assert.equal(env.window.UnitymobLgpdConsent.accepted(), true);
  assert.ok(env.events.includes('unitymob:lgpd-consent-accepted'));
  env.controller.reject();
  assert.equal(env.window.UnitymobLgpdConsent.accepted(), false);
  assert.equal(env.cookies.get('unitymob_interest_consent'), 'rejected');
  assert.equal(env.reloads(), 1);
  assert.equal(env.cookies.get('login_session'), 'keep');
  env.controller.accept();
  assert.equal(env.cookies.has('unitymob_interest_consent'), false);
  assert.equal(env.window.UnitymobLgpdConsent.accepted(), true);
});

test('initial rejection stays on the page and interest events cannot bypass it', () => {
  const env = setup();
  env.controller.reject();
  assert.equal(env.reloads(), 0);
  const tracker = env.load('app/javascript/controllers/public_interest_tracker_controller.js', 'Tracker');
  tracker.enabledValue = true; tracker.consentRequiredValue = false;
  env.storage.set('unitymob_interest_consent', 'accepted');
  assert.equal(tracker.canTrack(), false);
  assert.equal(tracker.consentAccepted(), false);
});

test('blocked cookies still allow accepting and dismissing the banner for this visit', () => {
  const env = setup({}, true);
  let hidden = false;
  env.controller.bannerTarget.classList.toggle = (name, value) => { hidden = value; };
  env.controller.connect();
  assert.equal(hidden, false);
  env.controller.accept();
  assert.equal(hidden, true);
  assert.equal(env.window.UnitymobLgpdConsent.accepted(), true);
  assert.ok(env.events.includes('unitymob:lgpd-consent-accepted'));
});
