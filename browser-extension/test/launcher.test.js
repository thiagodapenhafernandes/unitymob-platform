import test from "node:test";
import assert from "node:assert/strict";
import { openFromToolbar, configurePanel } from "../src/launcher.js";

for (const scenario of ["current", "existing", "new"]) {
  test(`toolbar opens only the WhatsApp tab (${scenario}), never a window panel`, async () => {
    const calls = [];
    const target = { id: 9, windowId: 3, url: "https://web.whatsapp.com/" };
    global.chrome = {
      runtime: {},
      sidePanel: {
        setOptions(options, callback) { calls.push(["options", options]); callback(); },
        open(options, callback) { assert.deepEqual(options, { tabId: 9 }); calls.push(["open", options]); callback(); }
      },
      tabs: {
        query(options, callback) { assert.equal(options.windowId, 3); callback(scenario === "existing" ? [target] : []); },
        update(id, options, callback) { assert.equal(id, 9); calls.push(["focus", options]); callback(target); },
        create(options, callback) { assert.equal(options.url, target.url); calls.push(["create", options]); callback(target); }
      }
    };
    await openFromToolbar(scenario === "current" ? target : { id: 1, windowId: 3, url: "https://example.com" });
    assert.deepEqual(calls.slice(-2), [["options", {tabId: 9, path: "panel.html", enabled: true}], ["open", {tabId: 9}]]);
  });
}

test("navigation outside WhatsApp disables the tab panel", async () => {
  const enabled = [];
  global.chrome = { sidePanel: { async setOptions(options) { enabled.push(options.enabled); } } };
  for (const url of ["https://web.whatsapp.com/", "https://conexaobc.com/", "chrome://newtab/", "https://web.whatsapp.com/"]) await configurePanel({ id: 9, url });
  assert.deepEqual(enabled, [true, false, false, true]);
});

test("a failed tab lookup rejects without opening any panel", async () => {
  global.chrome = { runtime: {}, tabs: { query(options, callback) { chrome.runtime.lastError = {message: "Tab unavailable"}; callback(); } } };
  await assert.rejects(openFromToolbar({ id: 1, windowId: 3, url: "https://example.com" }), /Tab unavailable/);
});
