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
    closePropertyGallery() {}, editedForms: new Set(), propertySelection: new Map([["1", {}]]), clearPropertySearch() {}, catalogResets: 0, propertyCatalog: {reset() { context.catalogResets++; }}, showLeadIdentity() {},
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
  assert.equal(context.catalogResets, 1);
});

test("internal note hides and clears the result while operational contacts require it", () => {
  const elements = {
    "contact-kind": {value: "ligacao", dataset: {attemptKinds: JSON.stringify(["ligacao", "whatsapp", "email", "visita"])}},
    "contact-result": {value: "nao_respondeu"}, "contact-result-field": {}
  };
  const context = vm.createContext({$: id => elements[id]});
  vm.runInContext(section("function syncContactResult()", '$("contact-kind").addEventListener'), context);
  for (const kind of ["ligacao", "whatsapp", "email", "visita"]) {
    elements["contact-kind"].value = kind;
    vm.runInContext("syncContactResult()", context);
    assert.equal(elements["contact-result"].required, true);
    assert.equal(elements["contact-result-field"].hidden, false);
  }
  elements["contact-kind"].value = "nota";
  vm.runInContext("syncContactResult()", context);
  assert.equal(elements["contact-result"].required, false);
  assert.equal(elements["contact-result"].disabled, true);
  assert.equal(elements["contact-result"].value, "");
  assert.equal(elements["contact-result-field"].hidden, true);
});

test("task and appointment payloads reject invalid local date before silent failure", () => {
  const elements = {
    "task-title": {value: "Retornar"},
    "task-kind": {value: "follow_up"},
    "task-priority": {value: "normal"},
    "task-due": {value: ""},
    "task-description": {value: "Cliente pediu simulação"},
    "appointment-title": {value: "Visita"},
    "appointment-kind": {value: "visita"},
    "appointment-start": {value: "2026-12-01T09:30"},
    "appointment-end": {value: ""},
    "appointment-location": {value: "Imóvel"},
    "appointment-notes": {value: "Levar proposta impressa"},
    "new-lead-name": {value: ""},
    "new-lead-email": {value: ""},
    "note-body": {value: ""},
    "contact-kind": {value: "nota"},
    "contact-result": {value: ""},
    "status-stage": {value: ""},
    "label-options": {querySelectorAll: () => []}
  };
  const context = vm.createContext({$: id => elements[id]});
  vm.runInContext(section("function isoDateTime(", "for (const [formId, type]"), context);

  assert.throws(() => context.writePayload("create_task", {stage_id: 1}), /invalid_fields/);

  const payload = context.writePayload("create_appointment", {stage_id: 1});
  assert.equal(payload.starts_at, new Date("2026-12-01T09:30").toISOString());
  assert.equal(payload.ends_at, "");
  assert.equal(payload.notes, "Levar proposta impressa");

  elements["task-due"].value = "2026-12-01T10:00";
  assert.equal(context.writePayload("create_task", {stage_id: 1}).description, "Cliente pediu simulação");
});

test("write forms explain why a save was not sent", () => {
  const context = vm.createContext({saving: false, ready: () => true, context: {state: "ready"}, resolvedPhone: "5511999999999", selectedLead: null, errors: {context_changed: "mudou", invalid_phone: "telefone"}});
  vm.runInContext(section("function writeBlockedReason(", "for (const [formId, type]"), context);

  assert.equal(context.writeBlockedReason("create_lead"), "");
  assert.equal(context.writeBlockedReason("create_task"), "Selecione um lead antes de salvar.");
  context.resolvedPhone = "";
  assert.equal(context.writeBlockedReason("create_lead"), "telefone");
  context.resolvedPhone = "5511999999999";
  context.context = {state: "loading"};
  assert.equal(context.writeBlockedReason("create_lead"), "mudou");
});

test("already_connected keeps its reset action next to the banner", () => {
  let placedAfter = null;
  const elements = new Map([
    ["feedback", { textContent: "", after(node) { placedAfter = node; } }],
    ["reset-connection", { hidden: true }],
  ]);
  const context = vm.createContext({
    $: id => elements.get(id),
    me: null, clearContext() {}, renderAccount() {},
  });
  vm.runInContext(section("const errors = {", "function showLeadIdentity("), context);
  vm.runInContext(section("function feedback(error) {", "function renderAccount()"), context);
  vm.runInContext('feedback({ message: "already_connected" })', context);
  assert.equal(elements.get("reset-connection").hidden, false);
  assert.equal(placedAfter, elements.get("reset-connection"));
  assert.match(elements.get("feedback").textContent, /conexão anterior/);
  vm.runInContext('feedback({ message: "unavailable" })', context);
  assert.equal(elements.get("reset-connection").hidden, true);
});
