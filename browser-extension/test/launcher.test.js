import test from "node:test";
import assert from "node:assert/strict";
import { openFromToolbar, configurePanel } from "../src/launcher.js";

test("toolbar opens the panel synchronously before creating WhatsApp, preserving the source page", async () => {
  const calls = [];
  global.chrome = {
    sidePanel: { async setOptions(options) { calls.push(["options", options]); }, async open(options) { calls.push(["panel", options]); } },
    tabs: { async query() { return []; }, async create(options) { calls.push(["create", options]); return { id: 9, windowId: 3 }; } }
  };
  await openFromToolbar({ id: 1, windowId: 3, url: "https://youtube.com/" });
  assert.deepEqual(calls, [
    ["panel", { windowId: 3 }],
    ["create", { windowId: 3, url: "https://web.whatsapp.com/", active: true } ]
  ]);
});

test("toolbar reuses the active WhatsApp tab", async () => {
  const calls = [];
  global.chrome = { sidePanel: { async setOptions(options) { calls.push(options); }, async open(options) { calls.push(options); } } };
  await openFromToolbar({ id: 9, windowId: 3, url: "https://web.whatsapp.com/" });
  assert.deepEqual(calls, [{ windowId: 3 }]);
});

test("panel is restricted to WhatsApp, including after navigating away and back", async () => {
  const calls = [];
  global.chrome = { sidePanel: { async setOptions(options) { calls.push(options); } } };
  for (const url of ["https://web.whatsapp.com/", "https://youtube.com/", "chrome://newtab/", "https://web.whatsapp.com/"]) await configurePanel({ id: 9, url });
  assert.deepEqual(calls.map(call => call.enabled), [true, false, false, true]);
});


test("toolbar focuses an existing WhatsApp tab in the same window", async () => {
  const calls = [];
  global.chrome = {
    sidePanel: { async open(options) { calls.push(["panel", options]); } },
    tabs: {
      async query(options) { assert.deepEqual(options, { windowId: 3, url: "https://web.whatsapp.com/*" }); return [{ id: 9 }]; },
      async update(id, options) { calls.push(["focus", id, options]); }
    }
  };
  const opening = openFromToolbar({ id: 1, windowId: 3, url: "https://example.com/" });
  assert.deepEqual(calls, [["panel", { windowId: 3 }]]);
  await opening;
  assert.deepEqual(calls.at(-1), ["focus", 9, { active: true }]);
});
