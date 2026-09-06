import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const source = readFileSync(new URL("../src/panel.js", import.meta.url), "utf8");
function section(start, end) { return source.slice(source.indexOf(start), source.indexOf(end, source.indexOf(start))); }
test("restores a valid session before any lead or filter response exists", async () => {
  const elements = new Map();
  const session = {origin: "https://dev.unitymob.com.br", user: {id: 1}, tenant: {id: 72}, capabilities: {read_leads: true}};
  const context = vm.createContext({
    $: id => {
      if (!elements.has(id)) elements.set(id, {value: "old", replaceChildren() {}, reset() {}, removeAttribute() {}});
      return elements.get(id);
    },
    Option: function(label, value) { this.label = label; this.value = value; },
    propertySelection: new Map([["1", {}]]), clearPropertySearch() {}, showLeadIdentity() {},
    selectedLead: {id: 99}, resolvedPhone: "old", revision: 0, context: {},
    checkingSession: false, pairing: false, me: null, lastPairCheck: Date.now(), lastSessionCheck: 0,
    ready() { return false; }, request: async () => session,
    renderAccount() {}, feedback(error) { throw error; }
  });
  vm.runInContext(section("function clearLead()", "function renderAccount()"), context);
  vm.runInContext(section("async function refreshSession(", "async function refresh("), context);
  await vm.runInContext("refreshSession(true)", context);
  assert.equal(context.me, session);
  assert.equal(context.selectedLead, null);
  assert.equal(context.propertySelection.size, 0);
  assert.equal(elements.get("property-quick").value, "");
});
