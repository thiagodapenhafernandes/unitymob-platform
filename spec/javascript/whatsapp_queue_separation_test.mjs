import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

function controller(file, document) {
  const context = vm.createContext({ Controller: class {}, document });
  vm.runInContext(readFileSync(file, 'utf8').replace(/^import .*\n/gm, '').replace('export default class', 'this.ControllerClass = class'), context);
  return new context.ControllerClass();
}

test('thread updates remove commercial conversations from the administrative queue', () => {
  let removed = false, refreshed = false;
  const current = { remove: () => { removed = true; } };
  const thread = controller('app/javascript/controllers/wa_thread_controller.js', {
    querySelector: selector => selector.includes('data-conversation-id') ? current : {}
  });
  thread.refreshInboxCounters = () => { refreshed = true; };
  thread.syncQueue({ queue: { id: 123, html: '<a></a>', administrative_inbox: false } });
  assert.equal(removed, true);
  assert.equal(refreshed, true);
});

test('attendance updates cannot reinsert a commercial conversation', () => {
  let removed = false;
  const queue = controller('app/javascript/controllers/wa_queue_controller.js', {
    createElement: () => ({ firstElementChild: { dataset: { administrativeInbox: 'false' } } })
  });
  queue.hasListTarget = true;
  queue.listTarget = { querySelector: () => ({ remove: () => { removed = true; } }) };
  queue.applyAttendanceChange({ conversation_id: 123, visible: true, html: '<a></a>' });
  assert.equal(removed, true);
});
