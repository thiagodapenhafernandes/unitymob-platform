import test, { beforeEach } from "node:test";
import assert from "node:assert/strict";
import { contextKey } from "../src/context.js";
let listener, stored, temporary, requests, projection, installed, tabUpdated;
const origin = "https://dev.unitymob.com.br";
const identity = { id: "a".repeat(32), getURL: path => `chrome-extension://${"a".repeat(32)}/${path}` };
const sender = { id: identity.id, url: identity.getURL("panel.html") };
const validConnection = () => ({ origin, token: "t".repeat(43), termsAccepted: true, expires_at: new Date(Date.now() + 60000).toISOString() });
const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
global.chrome = {
  runtime: { ...identity, onInstalled: { addListener(fn) { installed = fn; } }, onStartup: { addListener() {} }, onMessage: { addListener(fn) { listener = fn; } } },
  storage: { local: {
    async setAccessLevel() {},
    async get(key) { return { [key]: stored[key] }; },
    async set(value) { Object.assign(stored, value); },
    async remove(keys) { for (const key of [keys].flat()) delete stored[key]; }
  }, session: {
    async setAccessLevel() {},
    async get(key) { return { [key]: temporary[key] }; },
    async set(value) { Object.assign(temporary, value); },
    async remove(keys) { for (const key of [keys].flat()) delete temporary[key]; }
  } },
  action: { onClicked: { addListener() {} } },
  sidePanel: { async setOptions() {} }, permissions: { async contains() { return true; } },
  tabs: { onUpdated: { addListener(fn) { tabUpdated = fn; } }, async get(id) { return { id, active: true, url: "https://web.whatsapp.com/" }; }, async create() {} },
  scripting: { async executeScript() { return [{ frameId: 0, result: { ...projection } }]; } }
};
await import("../src/background.js");
function send(message, from = sender) {
  return new Promise(resolve => { if (listener(message, from, resolve) === false) resolve("ignored"); });
}
beforeEach(() => {
  stored = { connection: validConnection() }; temporary = {}; requests = [];
  projection = { state: "ready", account: "5511888888888@c.us", chatId: "5511999999999@c.us", phone: "+5511999999999" };
  global.fetch = async (url, options) => { requests.push({ url, options }); return json({ leads: [] }); };
});
test("only the native panel can call the worker", async () => {
  for (const from of [{ ...sender, tab: { id: 1 } }, { ...sender, url: "https://web.whatsapp.com/" }, { ...sender, id: "b".repeat(32) }]) {
    assert.equal(await send({ type: "me" }, from), "ignored");
  }
  assert.equal(requests.length, 0);
});
test("does not offer arbitrary URLs, methods, scripts or lead paths", async () => {
  delete stored.connection;
  assert.equal((await send({ type: "connect", origin: "https://dev.unitymob.com.br.evil.test" })).ok, false);
  assert.equal((await send({ type: "fetch", url: origin })).ok, false);
  stored.connection = validConnection();
  assert.equal((await send({ type: "lead", tabId: 1, contextKey: contextKey(projection), leadId: "../session" })).ok, false);
  assert.equal(requests.length, 0);
});
test("queries only its fixed API without cookies or redirects", async () => {
  const result = await send({ type: "resolve", tabId: 1, contextKey: contextKey(projection) });
  assert.equal(result.ok, true);
  assert.equal(requests[0].url, `${origin}/api/v1/browser_extension/leads/resolve`);
  assert.equal(requests[0].options.credentials, "omit");
  assert.equal(requests[0].options.redirect, "error");
  assert.deepEqual(JSON.parse(requests[0].options.body), { contact_phone: projection.phone });
  assert.equal(JSON.stringify(result).includes(stored.connection.token), false);
});
test("drops CRM results when the WhatsApp chat changed in flight", async () => {
  global.fetch = async () => { projection.chatId = "other@lid"; return json({ leads: [{ id: 1 }] }); };
  assert.deepEqual(await send({ type: "resolve", tabId: 1, contextKey: contextKey(projection) }), { ok: false, error: "context_changed" });
});
test("simultaneous panels exchange one verifier only once", async () => {
  delete stored.connection;
  temporary.pairing = { origin, verifier: "v".repeat(43), code: "signed-code", until: Date.now() + 60000 };
  let exchanges = 0;
  global.fetch = async () => { exchanges++; return json({ token: "t".repeat(43), expires_at: validConnection().expires_at }); };
  const results = await Promise.all([send({ type: "pair" }), send({ type: "pair" })]);
  assert.equal(exchanges, 1);
  assert.deepEqual(results.map(result => result.data.state), ["connected", "connected"]);
  assert.equal(temporary.pairing, undefined);
});
test("an old failed request cannot erase a newer authorization", async () => {
  global.fetch = async () => { stored.connection = { ...validConnection(), token: "n".repeat(43) }; return json({}, 401); };
  assert.equal((await send({ type: "me" })).error, "http_401");
  assert.equal(stored.connection.token, "n".repeat(43));
});
test("revocation errors retain the current connection for retry; success removes it", async () => {
  global.fetch = async () => json({}, 500);
  assert.equal((await send({ type: "disconnect" })).ok, false);
  assert.ok(stored.connection);
  global.fetch = async () => new Response(null, { status: 204 });
  assert.equal((await send({ type: "disconnect" })).ok, true);
  assert.equal(stored.connection, undefined);
});

test("does not inspect WhatsApp or query leads before accepting terms", async () => {
  stored.connection.termsAccepted = false;
  for (const type of ["snapshot", "resolve", "lead"]) {
    assert.equal((await send({ type, tabId: 1, contextKey: contextKey(projection), leadId: 1 })).error, "terms_required");
  }
  assert.equal(requests.length, 0);
});

test("an authorization URL alone cannot exchange the grant without the Chrome callback code", async () => {
  delete stored.connection;
  temporary.pairing = { origin, verifier: "v".repeat(43), until: Date.now() + 60000 };
  assert.deepEqual(await send({ type: "pair" }), { ok: true, data: { state: "pending" } });
  assert.equal(requests.length, 0);
});

test("login uses the configured Unitymob and exchanges only the signed Chrome callback", async () => {
  delete stored.connection;
  chrome.identity = {
    getRedirectURL: path => `https://${identity.id}.chromiumapp.org/${path}`,
    async launchWebAuthFlow({ url, interactive }) {
      const login = new URL(url);
      assert.equal(login.origin, origin);
      assert.equal(interactive, true);
      return `${this.getRedirectURL("unitymob")}?${new URLSearchParams({ state: login.searchParams.get("challenge"), login_token: "signed-code" })}`;
    }
  };
  global.fetch = async (url, options) => {
    assert.equal(url, `${origin}/api/v1/browser_extension/session`);
    assert.equal(JSON.parse(options.body).login_token, "signed-code");
    return json({ token: "t".repeat(43), expires_at: validConnection().expires_at });
  };
  assert.deepEqual(await send({ type: "connect", origin: "https://evil.test" }), { ok: true, data: { state: "connected" } });
  assert.equal(stored.connection.termsAccepted, false);
});

test("login discards a callback for another state before any exchange", async () => {
  delete stored.connection;
  chrome.identity = {
    getRedirectURL: path => `https://${identity.id}.chromiumapp.org/${path}`,
    async launchWebAuthFlow() { return `${this.getRedirectURL("unitymob")}?state=wrong&login_token=code`; }
  };
  assert.equal((await send({ type: "connect" })).ok, false);
  assert.equal(requests.length, 0);
  assert.equal(stored.connection, undefined);
  assert.equal(temporary.pairing, undefined);
});

const noteRequest = () => ({ type: "create_note", tabId: 1, contextKey: contextKey(projection), leadId: 7,
  phone: projection.phone, confirmed: true, payload: { body: "Preferência por varanda" } });

test("writes only from a confirmed individual chat and rejects mismatched contact before POST", async () => {
  for (const request of [{ ...noteRequest(), confirmed: false }, { ...noteRequest(), phone: "+5511777777777" },
    { ...noteRequest(), contextKey: "stale" }]) {
    assert.equal((await send(request)).ok, false);
  }
  stored.connection.termsAccepted = false;
  assert.equal((await send(noteRequest())).error, "terms_required");
  assert.equal(requests.length, 0);
});

test("a timed out write reuses its key across retries and concurrent panels without storing note text", async () => {
  let firstKey;
  global.fetch = async (url, options) => {
    requests.push({ url, options });
    const body = JSON.parse(options.body);
    assert.equal(url, `${origin}/api/v1/browser_extension/leads/7/notes`);
    if (!firstKey) { firstKey = body.request_key; throw new TypeError("network error"); }
    assert.equal(body.request_key, firstKey);
    return json({ lead_id: 7, note_id: 8 });
  };
  assert.equal((await send(noteRequest())).ok, false);
  assert.equal(JSON.stringify(stored.writeAttempts).includes("varanda"), false);
  const results = await Promise.all([send(noteRequest()), send(noteRequest())]);
  assert.deepEqual(results.map(result => result.data.note_id), [8, 8]);
  assert.equal(requests.length, 3);
});

test("a successful write reports the original lead even when the chat changes in flight", async () => {
  global.fetch = async () => { projection.chatId = "other@lid"; return json({ lead_id: 7, note_id: 8 }); };
  assert.deepEqual(await send(noteRequest()), { ok: true, data: { lead_id: 7, note_id: 8 } });
});

test("business validation or permission denial does not disconnect the user", async () => {
  for (const [status, error] of [[422, "invalid_fields"], [403, "permission_denied"], [403, "terms_required"]]) {
    global.fetch = async () => json({ error }, status);
    assert.equal((await send(noteRequest())).error, error);
    assert.ok(stored.connection);
  }
});

test("write bodies discard arbitrary owner, tenant, routing and contact metadata", async () => {
  const request = noteRequest();
  request.payload = { body: "Nota", tenant_id: 999, admin_user_id: 999, contact_kind: "whatsapp" };
  await send(request);
  assert.deepEqual(JSON.parse(requests[0].options.body).note, { body: "Nota" });
});


test("installation enables the global panel and previously disabled tabs", async () => {
  const options = [];
  chrome.sidePanel.setPanelBehavior = async () => {};
  chrome.sidePanel.setOptions = async value => { options.push(value); };
  chrome.tabs.query = async () => [{ id: 1, url: "https://web.whatsapp.com/" }, { id: 2, url: "https://youtube.com/" }];
  await installed();
  assert.deepEqual(options, [{ path: "panel.html", enabled: true }, { tabId: 1, path: "panel.html", enabled: true }, { tabId: 2, path: "panel.html", enabled: true }]);
  tabUpdated(1, { url: "https://youtube.com/" }, { id: 1, url: "https://youtube.com/" });
  assert.deepEqual(options.at(-1), { tabId: 1, path: "panel.html", enabled: true });
});


test("login survives a fresh worker with cleared session storage, and still revalidates with the CRM", async () => {
  const connection = { ...stored.connection };
  temporary = {};
  await import(`../src/background.js?restart=${Date.now()}`);
  global.fetch = async (url, options) => {
    requests.push({ url, options });
    return json({ capabilities: { read_leads: true } });
  };
  assert.equal((await send({ type: "me" })).ok, true);
  assert.equal(requests[0].options.headers.Authorization, `Bearer ${connection.token}`);
  assert.deepEqual(stored.connection, connection);
  assert.equal(temporary.connection, undefined);
});

test("expired persisted login is removed without extending its lifetime", async () => {
  stored.connection.expires_at = new Date(Date.now() - 1000).toISOString();
  stored.writeAttempts = { old: { key: "retry" } };
  assert.deepEqual(await send({ type: "me" }), { ok: false, error: "not_connected" });
  assert.equal(stored.connection, undefined);
  assert.equal(stored.writeAttempts, undefined);
  assert.equal(requests.length, 0);
});

test("revoked persisted login and its retry keys are removed", async () => {
  stored.writeAttempts = { old: { key: "retry" } };
  global.fetch = async () => json({}, 401);
  assert.equal((await send({ type: "me" })).ok, false);
  assert.equal(stored.connection, undefined);
  assert.equal(stored.writeAttempts, undefined);
});

test("agenda and labels use confirmed writes, fixed paths and stripped payloads", async () => {
  for (const [type, path, key, payload] of [
    ["create_appointment", "appointments", "appointment", { title: "Visita", kind: "visita", starts_at: "2026-12-01T12:00:00Z", ends_at: "", location: "Recepção" }],
    ["set_labels", "labels", "labels", { ids: "1,2" }],
    ["link_properties", "properties", "properties", { ids: "1,2" }],
    ["change_status", "status", "status", { stage_id: "3", expected_stage_id: "2" }]
  ]) {
    const message = { type, tabId: 1, contextKey: contextKey(projection), leadId: 15, phone: projection.phone, payload: { ...payload, tenant_id: "999", admin_user_id: "999" } };
    assert.equal((await send(message)).ok, false);
    const before = requests.length;
    assert.equal((await send({ ...message, confirmed: true })).ok, true);
    assert.equal(requests.length, before + 1);
    assert.equal(requests.at(-1).url, `${origin}/api/v1/browser_extension/leads/15/${path}`);
    const body = JSON.parse(requests.at(-1).options.body);
    assert.deepEqual(body[key], payload);
    assert.match(body.request_key, /^[0-9a-f-]{36}$/);
  }
});

test("property search is scoped to the selected lead and rejects arbitrary filters", async () => {
  const message = {type: "search_properties", tabId: 1, contextKey: contextKey(projection), leadId: 15, query: "Centro", purpose: "locacao"};
  assert.equal((await send({...message, purpose: "all"})).ok, false);
  assert.equal((await send(message)).ok, true);
  assert.equal(requests.at(-1).url, `${origin}/api/v1/browser_extension/leads/15/properties/search`);
  assert.deepEqual(JSON.parse(requests.at(-1).options.body), {q: "Centro", purpose: "locacao"});
});

test("property sharing requires confirmation and rejects foreign property links", async () => {
  const message = {type: "send_properties", tabId: 1, contextKey: contextKey(projection), leadId: 1, ids: [7], phone: projection.phone};
  assert.equal((await send(message)).ok, false);
  global.fetch = async () => json({properties: [{id: 7, public_path: "https://evil.test"}]});
  assert.equal((await send({...message, confirmed: true})).ok, false);
  assert.equal((await send({...message, confirmed: true, phone: "+5511000000000"})).ok, false);
});

test("contact history sends only allowed fields to the dedicated confirmed endpoint", async () => {
  const message = {...noteRequest(), type: "create_contact", payload: {body: "Resumo", contact_kind: "ligacao", contact_result: "nao_respondeu", tenant_id: 99}};
  assert.equal((await send({...message, confirmed: false})).ok, false);
  assert.equal(requests.length, 0);
  assert.equal((await send(message)).ok, true);
  assert.equal(requests[0].url, `${origin}/api/v1/browser_extension/leads/7/contacts`);
  assert.deepEqual(JSON.parse(requests[0].options.body).contact, {body: "Resumo", contact_kind: "ligacao", contact_result: "nao_respondeu"});
});
