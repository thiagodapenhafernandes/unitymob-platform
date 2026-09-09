import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

function setup() {
  const frames = new Map();
  let nextFrame = 0;
  const events = [];
  let listener;
  const form = {
    addEventListener(type, fn, capture) { assert.equal(type, 'invalid'); assert.equal(capture, true); listener = fn; },
    removeEventListener(type, fn, capture) { assert.equal(type, 'invalid'); assert.equal(capture, true); assert.equal(listener, fn); listener = null; },
    contains: field => field.connected !== false,
    querySelectorAll: () => triggers
  };
  const context = vm.createContext({ Controller: class {},
    requestAnimationFrame: fn => { frames.set(++nextFrame, fn); return nextFrame; },
    cancelAnimationFrame: id => frames.delete(id)
  });
  vm.runInContext(readFileSync('app/javascript/controllers/ax_form_validation_controller.js', 'utf8')
    .replace(/^import .*\n/, '').replace('export default class', 'this.Validation = class'), context);
  const controller = new context.Validation(); controller.element = form; controller.connect();
  const triggers = [];
  function ancestor(id, kind, parent = form, hidden = true) {
    const node = { id, parentElement: parent, hidden,
      matches: selector => selector === 'details' ? kind === 'details' : ['tab', 'disclosure'].includes(kind)
    };
    triggers.push({ disabled: false, getAttribute: () => id, click() { events.push(`open:${id}`); node.hidden = false; } });
    return node;
  }
  function field(name, parent = form) {
    return { parentElement: parent,
      focus: () => events.push(`focus:${name}`),
      reportValidity() {
        events.push(`report:${name}`);
        invalid(this);
      }
    };
  }
  function invalid(target) {
    let prevented = false;
    listener({ target, preventDefault() { prevented = true; } });
    return prevented;
  }
  function flush() { const pending = [...frames.values()]; frames.clear(); pending.forEach(fn => fn()); }
  return { controller, events, ancestor, field, invalid, flush, frames, listener: () => listener };
}

test('reveals nested tabs, details and disclosure outer first before reporting first invalid field', () => {
  const env = setup();
  const outer = env.ancestor('outer', 'tab');
  const inner = env.ancestor('inner', 'tab', outer);
  const details = env.ancestor('details', 'details', inner, false);
  const disclosure = env.ancestor('disclosure', 'disclosure', details);
  assert.equal(env.invalid(env.field('first', disclosure)), true);
  env.invalid(env.field('second', disclosure));
  assert.equal(env.frames.size, 1);
  env.flush();
  assert.equal(details.open, true);
  assert.deepEqual(env.events, ['open:outer', 'open:inner', 'open:disclosure', 'focus:first', 'report:first']);
  assert.equal(env.frames.size, 0, 'reportValidity recursion must not schedule another report');
});

test('visible panel stays open and subsequent validation can report a different field', () => {
  const env = setup();
  const panel = env.ancestor('visible', 'tab', undefined, false);
  env.invalid(env.field('one', panel)); env.flush();
  env.invalid(env.field('two', panel)); env.flush();
  assert.deepEqual(env.events, ['focus:one', 'report:one', 'focus:two', 'report:two']);
});

test('disconnect removes capturing listener and cancels pending validation', () => {
  const env = setup(); env.invalid(env.field('pending'));
  env.controller.disconnect(); env.flush();
  assert.equal(env.listener(), null);
  assert.equal(env.frames.size, 0);
  assert.deepEqual(env.events, []);
});

test('detached field is ignored and unrelated hidden containers are not opened', () => {
  const env = setup();
  const removed = env.field('removed'); removed.connected = false;
  env.invalid(removed); env.flush();
  assert.deepEqual(env.events, []);
  const other = env.ancestor('other', 'unrelated');
  env.invalid(env.field('current', other)); env.flush();
  assert.equal(other.hidden, true);
  assert.deepEqual(env.events, ['focus:current', 'report:current']);
});
