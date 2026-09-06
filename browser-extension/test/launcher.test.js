import test from "node:test";
import assert from "node:assert/strict";
import { openFromToolbar, configurePanel } from "../src/launcher.js";

test("toolbar creates WhatsApp and opens only its panel, preserving the source page", async () => {
  const calls = [];
  global.chrome = {
    sidePanel: { async setOptions(options) { calls.push(["options", options]); }, async open(options) { calls.push(["panel", options]); } },
    tabs: { async query() { return []; }, async create(options) { calls.push(["create", options]); return { id: 9, windowId: 3 }; } }
  };
  await openFromToolbar({ id: 1, windowId: 3, url: "https://youtube.com/" });
  assert.deepEqual(calls, [
    ["create", { windowId: 3, url: "https://web.whatsapp.com/", active: true }],
    ["options", { tabId: 9, path: "panel.html", enabled: true }], ["panel", { tabId: 9 }]
  ]);
});

test("toolbar reuses the active WhatsApp tab without a window-wide panel", async () => {
  const calls = [];
  global.chrome = { sidePanel: { async setOptions(options) { calls.push(options); }, async open(options) { calls.push(options); } } };
  await openFromToolbar({ id: 9, windowId: 3, url: "https://web.whatsapp.com/" });
  assert.deepEqual(calls, [{ tabId: 9, path: "panel.html", enabled: true }, { tabId: 9 }]);
});

test("other sites disable the panel and returning to WhatsApp enables it", async () => {
  const calls = [];
  global.chrome = { sidePanel: { async setOptions(options) { calls.push(options); } } };
  for (const url of ["https://web.whatsapp.com/", "https://youtube.com/", "chrome://newtab/", "https://web.whatsapp.com/"]) await configurePanel({ id: 9, url });
  assert.deepEqual(calls.map(call => call.enabled), [true, false, false, true]);
});
