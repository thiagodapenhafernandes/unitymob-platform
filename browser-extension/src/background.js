import { readWhatsAppContext, sendPropertyMessage, contextKey, validateContext } from "./context.js";
import { isWhatsAppTab, allowedOrigin, isPanelSender, createPairing, leadId } from "./security.js";
import { openFromToolbar, openWhatsApp, configurePanel } from "./launcher.js";
import { crmOrigin, crmOrigins, discoveryOrigin } from "./config.js";

const storageReady = Promise.all([
  chrome.storage.local.setAccessLevel({ accessLevel: "TRUSTED_CONTEXTS" }),
  chrome.storage.session.setAccessLevel({ accessLevel: "TRUSTED_CONTEXTS" })
]);
async function configurePanels() {
  await chrome.sidePanel.setPanelBehavior({ openPanelOnActionClick: false });
  await chrome.sidePanel.setOptions({ enabled: false });
  for (const tab of await chrome.tabs.query({})) await configurePanel(tab).catch(() => {});
}
chrome.runtime.onInstalled.addListener(configurePanels);
chrome.runtime.onStartup.addListener(configurePanels);
chrome.tabs.onUpdated.addListener((id, change, tab) => {
  if (change.url || change.status === "complete") void configurePanel(tab).catch(() => {});
});
chrome.action.onClicked.addListener(tab => { openFromToolbar(tab).catch(() => {}); });

// Pairing is single-use. Multiple open panels must share one exchange at a time.
let authenticationQueue = Promise.resolve();
let writeQueue = Promise.resolve();

async function activeWhatsAppTab(tabId) {
  if (!Number.isInteger(tabId)) throw new Error("no_whatsapp");
  const tab = await chrome.tabs.get(tabId);
  if (!tab.active || !isWhatsAppTab(tab)) throw new Error("no_whatsapp");
  return tab;
}

async function snapshot(tabId) {
  await activeWhatsAppTab(tabId);
  // Native request/response avoids an arbitrary-method bridge in the page DOM.
  const results = await chrome.scripting.executeScript({ target: { tabId }, world: "MAIN", func: readWhatsAppContext });
  const result = validateContext(results.find(item => item.frameId === 0)?.result);
  if (result.state === "loading") {
    await chrome.scripting.executeScript({ target: { tabId }, world: "MAIN", files: ["vendor/wppconnect-wa.js"] });
  }
  await activeWhatsAppTab(tabId);
  return { ...result, tabId };
}

async function crmFetch(origin, path, { token, body, method = "GET" } = {}) {
  allowedOrigin(origin, discoveryOrigin ? [origin] : crmOrigins);
  if (discoveryOrigin && !origin.startsWith("https://")) throw new Error("invalid_origin");
  const response = await fetch(`${origin}/api/v1/browser_extension/${path}`, {
    method, credentials: "omit", redirect: "error", cache: "no-store", signal: AbortSignal.timeout(10000),
    headers: { Accept: "application/json", "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    ...(body ? { body: JSON.stringify(body) } : {})
  });
  if (!response.ok) {
    const body = await response.json().catch(() => ({}));
    const known = ["terms_required", "permission_denied", "invalid_fields", "request_conflict", "account_mismatch", "lead_changed"];
    throw new Error(known.includes(body.error) ? body.error : `http_${response.status}`);
  }
  if (response.status === 204) return null;
  if (!response.headers.get("content-type")?.includes("application/json")) throw new Error("invalid_response");
  return response.json();
}

async function session() {
  await storageReady;
  const { connection } = await chrome.storage.local.get("connection");
  if (!connection || (discoveryOrigin ? connection.directory !== discoveryOrigin : !crmOrigins.includes(connection.origin)) || !Number.isFinite(Date.parse(connection.expires_at)) || Date.parse(connection.expires_at) <= Date.now()) {
    await chrome.storage.local.remove(["connection", "writeAttempts"]);
    throw new Error("not_connected");
  }
  return connection;
}

async function authenticatedFetch(connection, path, options = {}) {
  try {
    const result = await crmFetch(connection.origin, path, { ...connection, ...options });
    if ((await session()).token !== connection.token) throw new Error("context_changed");
    return result;
  } catch (error) {
    const { connection: current } = await chrome.storage.local.get("connection");
    if (["http_401", "http_403"].includes(error.message) && current?.token === connection.token) {
      await chrome.storage.local.remove(["connection", "writeAttempts"]);
    }
    throw error;
  }
}

async function discoveryFetch(path, body) {
  if (!discoveryOrigin) throw new Error("invalid_request");
  const response = await fetch(`${discoveryOrigin}/discovery/v2/${path}`, {
    method: "POST", credentials: "omit", redirect: "error", cache: "no-store", signal: AbortSignal.timeout(15000),
    headers: { "Content-Type": "application/json", Accept: "application/json" }, body: JSON.stringify(body)
  });
  if (!response.ok) throw new Error(response.status === 429 ? "discovery_rate_limited" : response.status === 422 ? "invalid_code" : "discovery_unavailable");
  return response.json();
}

async function handle(message) {
  await storageReady;
  switch (message.type) {
    case "discovery_start": {
      await chrome.storage.session.remove("discovery");
      const email = message.email?.trim().toLowerCase();
      if (typeof email !== "string" || email.length > 254) throw new Error("invalid_fields");
      const result = await discoveryFetch("challenges", { email });
      if (!/^[A-Za-z0-9_-]{43}$/.test(result.challenge)) throw new Error("invalid_response");
      await chrome.storage.session.set({ discovery: { challenge: result.challenge, until: Date.now() + 600000 } });
      return { state: "code_sent" };
    }
    case "discovery_verify": {
      const { discovery } = await chrome.storage.session.get("discovery");
      if (!discovery?.challenge || discovery.until <= Date.now()) throw new Error("pairing_expired");
      if (!/^\d{6}$/.test(message.code)) throw new Error("invalid_code");
      const result = await discoveryFetch("verify", { challenge: discovery.challenge, code: message.code });
      if (!Array.isArray(result.accounts) || result.accounts.length > 50 || typeof result.email !== "string") throw new Error("invalid_response");
      const accounts = result.accounts.map(account => {
        const origin = allowedOrigin(account.origin, [account.origin]);
        if (!origin.startsWith("https://") || !Number.isSafeInteger(account.id) || !/^\d+$/.test(account.tenant_id) || typeof account.instance_id !== "string" || typeof account.name !== "string") throw new Error("invalid_response");
        return { id: account.id, origin, tenant_id: account.tenant_id, instance_id: account.instance_id, name: account.name.slice(0, 200) };
      });
      await chrome.storage.session.set({ discovery: { accounts, email: result.email, until: Date.now() + 600000 } });
      return { accounts };
    }
    case "snapshot": {
      const connection = await session();
      if (!connection.termsAccepted) throw new Error("terms_required");
      return snapshot(message.tabId);
    }
    case "open_whatsapp": {
      const window = await chrome.windows.getLastFocused();
      await openWhatsApp(window.id);
      return { state: "opened" };
    }
    case "connect": {
      const { connection } = await chrome.storage.local.get("connection");
      if (connection) throw new Error("already_connected");
      let origin = allowedOrigin(crmOrigin, crmOrigins);
      let target = null, email = null;
      if (discoveryOrigin) {
        const { discovery } = await chrome.storage.session.get("discovery");
        target = discovery?.until > Date.now() && discovery.accounts?.find(account => account.id === message.accountId);
        if (!target) throw new Error("pairing_expired");
        origin = target.origin; email = discovery.email;
      }
      if (!(await chrome.permissions.contains({ origins: [`${origin}/*`] }))) throw new Error("permission_required");
      const pairing = { ...await createPairing(), origin, target, email, until: Date.now() + 5 * 60_000 };
      await chrome.storage.session.set({ pairing });
      try {
        const callback = await chrome.identity.launchWebAuthFlow({ interactive: true,
          url: `${origin}/admin/browser_extension_connections/new?${new URLSearchParams({ challenge: pairing.challenge, extension_id: chrome.runtime.id })}` });
        const result = new URL(callback);
        const expected = new URL(chrome.identity.getRedirectURL("unitymob"));
        if (result.origin !== expected.origin || result.pathname !== expected.pathname || result.searchParams.get("state") !== pairing.challenge || !result.searchParams.get("login_token")) {
          throw new Error("invalid_callback");
        }
        if (pairing.target && result.searchParams.get("issuer") !== origin) throw new Error("account_mismatch");
        await chrome.storage.session.set({ pairing: { ...pairing, code: result.searchParams.get("login_token") } });
        return handle({ type: "pair" });
      } catch (error) {
        await chrome.storage.session.remove("pairing");
        throw error;
      }
    }
    case "pair": {
      const { pairing } = await chrome.storage.session.get("pairing");
      const { connection } = await chrome.storage.local.get("connection");
      if (!pairing && connection) return { state: "connected" };
      if (!pairing || pairing.until <= Date.now()) {
        await chrome.storage.session.remove("pairing");
        throw new Error("pairing_expired");
      }
      if (!pairing.code) return { state: "pending" };
      const result = await crmFetch(pairing.origin, "session", { method: "POST", body: { verifier: pairing.verifier, login_token: pairing.code, extension_id: chrome.runtime.id, ...(pairing.target ? { expected_tenant_id: pairing.target.tenant_id, expected_email: pairing.email, expected_instance_id: pairing.target.instance_id, issuer: pairing.origin } : {}) } });
      if (result.state === "pending") return result;
      if (!/^[A-Za-z0-9_-]{43}$/.test(result.token) || !Number.isFinite(Date.parse(result.expires_at))) throw new Error("invalid_response");
      if (pairing.target && (result.tenant_id !== pairing.target.tenant_id || result.instance_id !== pairing.target.instance_id || result.login_email !== pairing.email)) throw new Error("account_mismatch");
      await chrome.storage.local.set({ connection: { directory: discoveryOrigin, origin: pairing.origin, token: result.token, expires_at: result.expires_at, termsAccepted: false, account: pairing.target } });
      await chrome.storage.session.remove(["pairing", "discovery"]);
      return { state: "connected" };
    }
    case "me": {
      const connection = await session();
      const result = await authenticatedFetch(connection, "session");
      await chrome.storage.local.set({ connection: { ...connection, termsAccepted: result.capabilities.read_leads === true } });
      return { ...result, origin: connection.origin };
    }
    case "accept_terms": {
      const connection = await session();
      const result = await authenticatedFetch(connection, "session/terms", { method: "POST", body: { accepted: message.accepted === true, version: message.version, digest: message.digest } });
      await chrome.storage.local.set({ connection: { ...connection, termsAccepted: true } });
      return result;
    }
    case "send_properties": {
      const connection = await session();
      if (!connection.termsAccepted) throw new Error("terms_required");
      const context = await snapshot(message.tabId);
      if (context.state !== "ready" || contextKey(context) !== message.contextKey) throw new Error("context_changed");
      if (message.confirmed !== true || !context.phone || context.phone.replace(/\D/g, "") !== String(message.phone).replace(/\D/g, "")) throw new Error("context_changed");
      if (!Array.isArray(message.ids) || !message.ids.length || message.ids.length > 20) throw new Error("invalid_fields");
      const result = await authenticatedFetch(connection, `leads/${leadId(message.leadId)}`);
      const properties = message.ids.map(id => result.properties.find(property => String(property.id) === String(id)));
      if (properties.some(property => !property?.public_path || !/^\/imovel\/[A-Za-z0-9_%_-]+$/.test(property.public_path))) throw new Error("invalid_fields");
      if (contextKey(await snapshot(message.tabId)) !== message.contextKey) throw new Error("context_changed");
      const publicOrigin = new URL(result.public_origin || connection.origin);
      if (publicOrigin.protocol !== "https:" || publicOrigin.username || publicOrigin.password || publicOrigin.pathname !== "/" || publicOrigin.search || publicOrigin.hash) throw new Error("invalid_fields");
      const text = properties.map(property => `${property.code} · ${property.title}\n${[property.neighborhood, property.city].filter(Boolean).join(" · ")}\n${publicOrigin.origin}${property.public_path}`).join("\n\n");
      const prepared = await chrome.scripting.executeScript({target: {tabId: message.tabId}, world: "MAIN", func: sendPropertyMessage, args: [context, text]});
      const response = prepared.find(item => item.frameId === 0)?.result;
      if (!response?.sent) throw new Error(response?.error || "send_unconfirmed");
      return response;
    }
    case "resolve":
    case "lead":
    case "search_properties": {
      if (!(await session()).termsAccepted) throw new Error("terms_required");
      const context = await snapshot(message.tabId);
      if (context.state !== "ready" || contextKey(context) !== message.contextKey) throw new Error("context_changed");
      const connection = await session();
      let result;
      if (message.type === "resolve") {
        const phone = message.phone || context.phone;
        if (typeof phone !== "string" || !/^\+?\d[\d ()-]{6,38}$/.test(phone)) throw new Error("invalid_phone");
        result = await authenticatedFetch(connection, "leads/resolve", { method: "POST", body: { contact_phone: phone } });
      } else if (message.type === "search_properties") {
        if (typeof message.query !== "string" || message.query.length > 100 || !["venda", "locacao"].includes(message.purpose)) throw new Error("invalid_fields");
        result = await authenticatedFetch(connection, `leads/${leadId(message.leadId)}/properties/search`, {method: "POST", body: {q: message.query, purpose: message.purpose, ...Object.fromEntries(["min_price", "max_price", "suites", "bedrooms", "parking", "category", "quick"].filter(key => message.filters?.[key] != null).map(key => [key, String(message.filters[key])]))}});
      } else {
        result = await authenticatedFetch(connection, `leads/${leadId(message.leadId)}`);
      }
      if (contextKey(await snapshot(message.tabId)) !== message.contextKey) throw new Error("context_changed");
      return result;
    }
    case "create_lead":
    case "create_note":
    case "create_task":
    case "create_appointment":
    case "set_labels":
    case "unlink_property":
    case "link_properties":
    case "change_status": {
      const connection = await session();
      if (!connection.termsAccepted) throw new Error("terms_required");
      if (message.confirmed !== true) throw new Error("invalid_fields");
      const context = await snapshot(message.tabId);
      if (context.state !== "ready" || contextKey(context) !== message.contextKey) throw new Error("context_changed");
      if (typeof message.phone !== "string" || !/^\+?\d[\d ()-]{6,38}$/.test(message.phone)) throw new Error("invalid_phone");
      if (context.phone && context.phone.replace(/\D/g, "") !== message.phone.replace(/\D/g, "")) throw new Error("context_changed");
      const definitions = {
        create_lead: { path: "leads", key: "lead", fields: ["name", "email"] },
        create_note: { suffix: "notes", key: "note", fields: ["body"] },
        create_task: { suffix: "tasks", key: "task", fields: ["title", "kind", "priority", "due_at"] },
        create_appointment: { suffix: "appointments", key: "appointment", fields: ["title", "kind", "starts_at", "ends_at", "location"] },
        set_labels: { suffix: "labels", key: "labels", fields: ["ids"] },
        unlink_property: { suffix: "properties/remove", key: "property", fields: ["id"] },
        link_properties: { suffix: "properties", key: "properties", fields: ["ids"] },
        change_status: { suffix: "status", key: "status", fields: ["stage_id", "expected_stage_id"] }
      };
      const operation = definitions[message.type];
      operation.path ||= `leads/${leadId(message.leadId)}/${operation.suffix}`;
      const payload = Object.fromEntries(operation.fields.map(field => [field, message.payload?.[field]]));
      if (Object.values(payload).some(value => typeof value !== "string" || value.length > 5000)) throw new Error("invalid_fields");
      const body = { confirmed: true, contact_phone: message.phone, [operation.key]: payload };
      // Persist retry keys with the login so reloads cannot duplicate an uncertain write.
      // Only hashes and random keys are stored, never note text.
      const fingerprint = [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(
        JSON.stringify([connection.token, message.contextKey, operation.path, body]))))].map(byte => byte.toString(16).padStart(2, "0")).join("");
      const { writeAttempts = {} } = await chrome.storage.local.get("writeAttempts");
      for (const [key, value] of Object.entries(writeAttempts)) {
        if (value.expiresAt <= Date.now()) delete writeAttempts[key];
      }
      if (!writeAttempts[fingerprint]) {
        if (Object.keys(writeAttempts).length >= 100) throw new Error("unavailable");
        writeAttempts[fingerprint] = { key: crypto.randomUUID(), expiresAt: Date.parse(connection.expires_at) };
        await chrome.storage.local.set({ writeAttempts });
      }
      body.request_key = writeAttempts[fingerprint].key;
      // Recheck after storage/crypto awaits, immediately before the mutation.
      if (contextKey(await snapshot(message.tabId)) !== message.contextKey) throw new Error("context_changed");
      const result = await authenticatedFetch(connection, operation.path, { method: "POST", body });
      writeAttempts[fingerprint].expiresAt = Date.now() + 30000;
      await chrome.storage.local.set({ writeAttempts });
      return result;
    }
    case "disconnect": {
      const connection = await session();
      // Leave local data until the user knows server-side revocation succeeded.
      await authenticatedFetch(connection, "session", { method: "DELETE" });
      await chrome.storage.local.remove(["connection", "writeAttempts"]);
      await chrome.storage.session.remove(["pairing", "discovery"]);
      return { state: "disconnected" };
    }
    default: throw new Error("invalid_request");
  }
}

chrome.runtime.onMessage.addListener((message, sender, respond) => {
  if (!isPanelSender(sender, chrome.runtime)) return false;
  const authenticationChange = ["discovery_start", "discovery_verify", "connect", "pair", "disconnect", "accept_terms", "me"].includes(message?.type);
  const writing = ["create_lead", "create_note", "create_task", "create_appointment", "set_labels", "link_properties", "unlink_property", "change_status", "send_properties"].includes(message?.type);
  const operation = authenticationChange ? authenticationQueue.then(() => handle(message)) :
    writing ? writeQueue.then(() => handle(message)) : handle(message);
  if (writing) writeQueue = operation.catch(() => {});
  if (authenticationChange) authenticationQueue = operation.catch(() => {});
  operation.then(data => respond({ ok: true, data })).catch(error => {
    const code = error.message;
    const safe = /^(discovery_rate_limited|discovery_unavailable|invalid_code|account_mismatch|http_\d{3}|not_connected|pairing_expired|context_changed|invalid_phone|no_whatsapp|permission_required|terms_required|invalid_fields|permission_denied|request_conflict)$/.test(code) ? code : "unavailable";
    respond({ ok: false, error: safe });
  });
  return true;
});
