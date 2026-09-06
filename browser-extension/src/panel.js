import { crmOrigin, discoveryOrigin } from "./config.js";
import { contextKey } from "./context.js";
import { isWhatsAppTab } from "./security.js";

const $ = id => document.getElementById(id);
let context = null;
let selectedLead = null;
let resolvedPhone = null;
let saving = false;
let me = null;
let revision = 0;
let refreshing = false;
let lastSessionCheck = 0;
let pairing = false;
let checkingSession = false;
let lastPairCheck = 0;
let discoveryStep = "email";
$("discovery-email-field").hidden = !discoveryOrigin;
$("discovery-email").required = !!discoveryOrigin;
const ready = () => me?.capabilities?.read_leads === true;

const errors = {
  account_mismatch: "O login pertence a outra conta ou usuário. Entre no CRM com o e-mail confirmado e a imobiliária escolhida.",
  invalid_code: "Código inválido ou expirado. Confira o código ou solicite outro.",
  discovery_rate_limited: "Muitas tentativas. Aguarde alguns minutos antes de tentar novamente.",
  discovery_unavailable: "Não foi possível localizar suas contas agora. Tente novamente em instantes.",
  permission_denied: "Você não tem permissão para esta ação.",
  invalid_fields: "Confira os campos e o contato. A tarefa precisa ter data futura.",
  request_conflict: "Esta tentativa tem dados diferentes. Atualize o painel antes de continuar.",
  terms_required: "Leia e aceite os termos para começar.",
  not_connected: "Entre na sua conta para continuar.",
  http_401: "Sua conexão expirou. Conecte novamente.",
  http_403: "O acesso não está disponível para esta conta ou dispositivo.",
  http_404: "Este lead não está mais disponível para você.",
  http_410: "A autorização expirou. Inicie uma nova conexão.",
  http_429: "Muitas consultas. Aguarde um momento antes de tentar novamente.",
  pairing_expired: "A autorização expirou. Clique em Entrar na Unitymob para tentar novamente.",
  context_changed: "A conversa mudou. Confira o contato antes de continuar.",
  invalid_phone: "Confira o telefone, incluindo DDD e código do país.",
  no_whatsapp: "Abra o WhatsApp Web para consultar o atendimento.",
  unavailable: "Não foi possível consultar agora. Tente atualizar."
};

async function request(type, data = {}) {
  const result = await chrome.runtime.sendMessage({ type, ...data });
  if (!result?.ok) throw new Error(result?.error || "unavailable");
  return result.data;
}

function clearLead() {
  selectedLead = null; resolvedPhone = null;
  $("match-explanation").hidden = true;
  $("lead-context").textContent = "";
  for (const id of ["create-lead", "note", "task"]) {
    $(`${id}-panel`).hidden = true; $(`${id}-panel`).open = false;
    $(`${id}-form`).reset();
  }
  $("lead-panel").hidden = true;
  for (const id of ["candidates", "properties", "tasks", "notes", "appointments", "labels", "proposals", "lead-name", "lead-status"]) $(id).replaceChildren();
  $("open-lead").removeAttribute("href");
}

function clearContext() {
  revision++; context = null; clearLead(); $("search-form").hidden = true; $("phone").value = "";
}

function feedback(error) {
  $("feedback").textContent = errors[error.message] || errors.unavailable;
  if (["not_connected", "http_401", "http_403", "http_410"].includes(error.message)) {
    me = null; clearContext(); renderAccount();
  }
  if (error.message === "context_changed") clearContext();
  if (error.message === "terms_required") void refreshSession(true);
}

function renderAccount() {
  $("connect-form").hidden = !!me || (!!discoveryOrigin && discoveryStep !== "email");
  $("discovery-code-form").hidden = !!me || discoveryStep !== "code";
  $("discovery-accounts").hidden = !!me || discoveryStep !== "accounts";
  $("discovery-restart").hidden = !!me || !discoveryOrigin || discoveryStep === "email";
  $("connect-form").querySelector("button").disabled = pairing;
  $("account").hidden = !me;
  $("login-panel").hidden = !!me;
  if (!me) closeAccountMenu();
  $("account-title").textContent = me ? "Sua conta" : "Entrar na Unitymob";
  $("terms-panel").hidden = !me || ready();
  $("chat-panel").hidden = !ready();
  $("terms-text").textContent = me?.terms?.text || "";
  $("tenant").textContent = me?.tenant?.name || "";
  $("user").textContent = me?.user?.name || "";
  $("connection-status").textContent = me ? (ready() ? "Atendimento conectado. As ações disponíveis seguem suas permissões." : "Login concluído. Leia e aceite os termos para começar.") :
    (pairing ? "Conclua o login na janela da Unitymob. Os termos aparecerão aqui." : "Entre na sua conta para consultar seus leads.");
  if (me) $("connections").href = `${me.origin}/admin/browser_extension_connections`;
  else $("connections").removeAttribute("href");
}

async function loadLead(id) {
  const version = revision;
  try {
    await fetchLead(id, version);
  } catch (error) { if (version === revision) feedback(error); }
}

async function fetchLead(id, version) {
  const current = context;
  const result = await request("lead", { tabId: current.tabId, contextKey: contextKey(current), leadId: id });
  if (version !== revision || !me) return;
  selectedLead = result.lead;
  $("note-panel").hidden = !me.capabilities.create_notes;
  $("task-panel").hidden = !me.capabilities.create_tasks;
  $("action-task").hidden = !me.capabilities.create_tasks;
  $("add-task").hidden = !me.capabilities.create_tasks;
  $("add-note").hidden = !me.capabilities.create_notes;
  $("actions-help").textContent = me.capabilities.create_notes || me.capabilities.create_tasks ? "" : "Seu perfil permite apenas consultar este atendimento. Alterações dependem das permissões do CRM.";
  for (const id of ["note-contact", "task-contact"]) $(id).textContent = `${result.lead.name} · ${resolvedPhone}`;
  $("create-lead-panel").hidden = true;
  $("lead-name").textContent = result.lead.name;
  $("lead-status").textContent = result.lead.status;
  $("lead-context").textContent = `${me.tenant.name} · ${leadContext(result.lead)}`;
  $("open-lead").href = `${me.origin}/admin/leads/${result.lead.id}`;
  const fullLead = $("open-lead").href;
  for (const [key, anchor] of [["agenda", "agenda"], ["labels", "etiquetas"], ["proposals", "propostas"], ["closed", ""], ["archive", ""]]) {
    $(`action-${key}`).href = `${fullLead}${anchor ? `#lead-desktop-${anchor}` : ""}`;
  }
  for (const [key, anchor] of [["appointments", "agenda"], ["labels", "etiquetas"], ["proposals", "propostas"]]) {
    $(`add-${key}`).href = `${fullLead}#lead-desktop-${anchor}`;
    $(`${key}-count`).textContent = result[`${key}_count`] ?? result[key]?.length ?? 0;
    $(`shortcut-${key}`).textContent = $(`${key}-count`).textContent;
  }
  $("shortcut-tasks").textContent = result.tasks_count ?? result.tasks.length;
  $("attempts-count").textContent = result.unsuccessful_attempts ?? 0;
  renderRecords("appointments", (result.appointments || []).map(a => ({ title: a.title, meta: [a.kind, formatDate(a.starts_at)].join(" · ") })), "Nada agendado.");
  renderRecords("labels", (result.labels || []).map(l => ({ title: l.name })), "Nenhuma etiqueta aplicada.");
  renderRecords("proposals", (result.proposals || []).map(p => ({ title: `Proposta #${p.id}`, meta: [p.status, formatDate(p.created_at)].join(" · ") })), "Nenhuma proposta.");
  renderRecords("properties", result.properties.map(p => ({ title: [p.code, p.title].filter(Boolean).join(" · "), meta: [p.city, p.neighborhood].filter(Boolean).join(" · ") })), "Nenhum imóvel vinculado.");
  renderRecords("tasks", result.tasks.map(t => ({ title: t.title, meta: [t.kind, t.priority && `Prioridade ${t.priority.toLowerCase()}`].filter(Boolean).join(" · "), body: t.due_at ? formatDate(t.due_at) : "Sem prazo definido" })), "Nenhuma tarefa pendente.");
  renderRecords("notes", (result.notes || []).map(n => ({ title: n.kind || "Anotação interna", meta: [formatDate(n.created_at), n.author].filter(Boolean).join(" · "), body: n.body })), "Nenhuma anotação registrada.");
  $("tasks-count").textContent = result.tasks_count ?? result.tasks.length;
  $("notes-count").textContent = result.notes_count ?? result.notes?.length ?? 0;
  $("properties-count").textContent = result.properties.length;
  $("lead-panel").hidden = false;
}

function formatDate(value) {
  return new Date(value).toLocaleString("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" });
}

function renderRecords(id, records, empty) {
  $(id).replaceChildren();
  if (!records.length) {
    const message = document.createElement("p"); message.className = "ax-workspace-muted"; message.textContent = empty; $(id).append(message);
  }
  for (const record of records) {
    const card = document.createElement("article"); card.className = `ax-workspace-record${id === "tasks" ? " ax-workspace-record--task" : ""}`;
    for (const [tag, value, className] of [["strong", record.title, ""], ["span", record.meta, "ax-workspace-muted"], ["p", record.body, "ax-workspace-record__body"]]) {
      if (!value) continue;
      const item = document.createElement(tag); item.className = className; item.textContent = value; card.append(item);
    }
    $(id).append(card);
  }
  if (records.length === 20) {
    const hint = document.createElement("p"); hint.className = "ax-workspace-muted"; hint.textContent = "Mostrando até 20 registros. Consulte os demais na ficha completa."; $(id).append(hint);
  }
}

for (const [button, kind] of [["action-task", "task"], ["add-task", "task"], ["add-note", "note"]]) {
  $(button).addEventListener("click", () => {
    const panel = $(`${kind}-panel`); panel.open = true;
    panel.scrollIntoView({ block: "nearest" }); panel.querySelector("input, textarea").focus();
  });
}

async function resolve(phone) {
  if (!ready() || context?.state !== "ready") return;
  const version = ++revision;
  clearLead();
  try {
    const result = await request("resolve", { tabId: context.tabId, contextKey: contextKey(context), phone });
    if (version !== revision) return;
    resolvedPhone = result.contact_phone || phone;
    $("match-explanation").hidden = !result.leads.length;
    $("match-explanation").textContent = `Atendimentos em ${me.tenant.name}.`;
    if (!result.leads.length) {
      $("create-lead-panel").hidden = !me.capabilities.create_leads;
      $("create-contact").textContent = resolvedPhone;
      if (phone.replace(/\D/g, "") === context.phone?.replace(/\D/g, "")) {
        $("new-lead-name").value = context.name || "";
      }
      $("candidates").textContent = "Nenhum lead acessível encontrado para este telefone.";
    } else if (result.leads.length === 1) {
      await loadLead(result.leads[0].id);
    } else {
      $("candidates").textContent = result.more ? "Há mais de dez atendimentos. Consulte a ficha na Unitymob se necessário." : "Escolha um lead abaixo para consultar a ficha, registrar notas e agendar tarefas:";
      for (const lead of result.leads) {
        const button = document.createElement("button"); button.className = "ax-btn"; button.type = "button";
        button.textContent = `${lead.name} · ${lead.status} · #${lead.id} — ${leadContext(lead)}`;
        button.addEventListener("click", () => { revision++; clearSelected(); loadLead(lead.id); });
        $("candidates").append(button);
      }
    }
  } catch (error) { if (version === revision) feedback(error); }
}

function clearSelected() { selectedLead = null; for (const id of ["note", "task"]) { $(`${id}-form`).reset(); $(`${id}-panel`).open = false; } $("lead-panel").hidden = true; $("open-lead").removeAttribute("href"); }

async function refreshSession(force = false) {
  if (checkingSession) return;
  checkingSession = true;
  try {
    if (!me && (pairing || force) && Date.now() - lastPairCheck > 5000) {
      lastPairCheck = Date.now();
      try {
        pairing = (await request("pair")).state === "pending";
        if (!pairing) lastSessionCheck = 0;
      } catch (error) { if (pairing) feedback(error); pairing = false; }
    }
    if (force || Date.now() - lastSessionCheck > 15_000) {
      lastSessionCheck = Date.now();
      try {
        const next = await request("me");
        if (!me || me.origin !== next.origin || me.user.id !== next.user.id || me.tenant.id !== next.tenant.id || ready() !== next.capabilities.read_leads) {
          clearContext(); $("terms-accepted").checked = false; $("accept-terms").disabled = true;
        }
        me = next;
      } catch (error) { if (me || error.message !== "not_connected") feedback(error); me = null; clearContext(); }
    }
    renderAccount();
  } finally { checkingSession = false; }
}

async function refresh(force = false) {
  if (refreshing || document.hidden) return;
  refreshing = true;
  void refreshSession(force);
  if (!ready()) { refreshing = false; return; }
  try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (!isWhatsAppTab(tab)) { clearContext(); $("chat-status").textContent = errors.no_whatsapp; $("open-whatsapp").hidden = false; return; }
    $("open-whatsapp").hidden = true;
    const version = revision;
    const next = await request("snapshot", { tabId: tab.id });
    if (version !== revision || document.hidden) return;
    const changed = next.tabId !== context?.tabId || contextKey(next) !== contextKey(context);
    if (changed || force) {
      clearContext(); context = next;
      $("search-options").open = next.state === "ready" && !next.phone;
      const states = {
        loading: "Preparando a conexão com o WhatsApp…",
        disconnected: "Conecte seu WhatsApp Web para continuar.",
        no_chat: "Selecione uma conversa individual.",
        unsupported: "Selecione uma conversa individual. Grupos e canais não são consultados.",
        incompatible: "Há uma versão incompatível da integração nesta página. Recarregue sem outras extensões de WhatsApp.",
        changed: "Atualizando a conversa…", unavailable: errors.unavailable
      };
      $("chat-status").textContent = next.state === "ready" ? ([next.name, next.phone].filter(Boolean).join(" · ") || "Telefone não disponível. Informe um número confirmado para buscar o lead.") : states[next.state];
      $("search-form").hidden = !(me && next.state === "ready");
      $("phone").value = next.phone || "";
      if (me && next.state === "ready" && next.phone) void resolve(next.phone);
    }
  } catch (error) { clearContext(); feedback(error); }
  finally { refreshing = false; }
}

async function connectAccount(account = null) {
  try {
    const origin = account?.origin || crmOrigin;
    if (!(await chrome.permissions.request({ origins: [`${origin}/*`] }))) return;
    pairing = true; renderAccount(); $("feedback").textContent = "";
    await request("connect", account ? { accountId: account.id } : {});
    pairing = false; lastSessionCheck = 0; await refreshSession(true);
  } catch (error) { pairing = false; renderAccount(); feedback(error); }
}
$("connect-form").addEventListener("submit", async event => {
  event.preventDefault();
  if (!discoveryOrigin) return connectAccount();
  const button = event.currentTarget.querySelector("button"); button.disabled = true;
  try {
    await request("discovery_start", { email: $("discovery-email").value });
    discoveryStep = "code"; $("discovery-code-form").reset(); renderAccount(); $("discovery-code").focus();
  } catch (error) { feedback(error); }
  finally { button.disabled = false; }
});
$("discovery-code-form").addEventListener("submit", async event => {
  event.preventDefault();
  const button = event.currentTarget.querySelector("button"); button.disabled = true;
  try {
    const result = await request("discovery_verify", { code: $("discovery-code").value });
    discoveryStep = "accounts"; $("discovery-accounts").replaceChildren();
    const text = document.createElement("p"); text.textContent = result.accounts.length ? (result.accounts.length === 1 ? "Sua conta foi localizada:" : "Escolha a imobiliária para este atendimento:") : "Nenhuma conta ativa encontrada. Confira o e-mail ou solicite a atualização do seu cadastro.";
    $("discovery-accounts").append(text);
    for (const account of result.accounts) {
      const choice = document.createElement("button"); choice.type = "button"; choice.className = "ax-btn";
      choice.textContent = `Entrar em ${account.name} · ${new URL(account.origin).hostname}`;
      choice.addEventListener("click", () => connectAccount(account)); $("discovery-accounts").append(choice);
    }
    renderAccount();
  } catch (error) { feedback(error); }
  finally { button.disabled = false; }
});
$("discovery-restart").addEventListener("click", () => { discoveryStep = "email"; renderAccount(); });
for (const id of ["disconnect", "switch-account"]) {
  $(id).addEventListener("click", async () => {
    try { await request("disconnect"); me = null; discoveryStep = "email"; clearContext(); renderAccount(); }
    catch (error) { feedback(error); }
  });
}
$("search-form").addEventListener("submit", event => { event.preventDefault(); resolve($("phone").value); });
$("refresh").addEventListener("click", () => { $("feedback").textContent = ""; refresh(true); });
$("open-whatsapp").addEventListener("click", () => request("open_whatsapp").catch(feedback));
document.addEventListener("visibilitychange", () => { if (document.hidden) clearContext(); else refresh(true); });
chrome.tabs.onActivated.addListener(() => { clearContext(); refresh(); });
chrome.tabs.onUpdated.addListener((id, change) => { if (context?.tabId === id && (change.url || change.status === "loading")) { clearContext(); refresh(); } });
setInterval(() => refresh(), 1500);
refresh(true);

$("terms-accepted").addEventListener("change", () => { $("accept-terms").disabled = !$("terms-accepted").checked; });
$("terms-form").addEventListener("submit", async event => {
  event.preventDefault();
  if (!me || !$("terms-accepted").checked) return;
  $("accept-terms").disabled = true;
  try {
    await request("accept_terms", { accepted: true, version: me.terms.version, digest: me.terms.digest });
    lastSessionCheck = 0;
    await refreshSession(true);
    refresh(true);
  } catch (error) { feedback(error); }
  finally { $("accept-terms").disabled = !$("terms-accepted").checked; }
});


for (const [formId, type] of [["create-lead-form", "create_lead"], ["note-form", "create_note"], ["task-form", "create_task"]]) {
  $(formId).addEventListener("submit", async event => {
    event.preventDefault();
    if (saving || !ready() || context?.state !== "ready" || !resolvedPhone) return;
    if (type !== "create_lead" && !selectedLead) return;
    const version = revision;
    const target = selectedLead;
    const phone = resolvedPhone;
    const form = event.currentTarget;
    const payload = type === "create_lead" ? { name: $("new-lead-name").value.trim(), email: $("new-lead-email").value.trim() } :
      type === "create_note" ? { body: $("note-body").value.trim() } :
      { title: $("task-title").value.trim(), kind: $("task-kind").value, priority: $("task-priority").value, due_at: new Date($("task-due").value).toISOString() };
    saving = true;
    for (const control of form.elements) control.disabled = true;
    $("feedback").textContent = "Salvando…";
    try {
      const result = await request(type, { tabId: context.tabId, contextKey: contextKey(context), leadId: target?.id,
        phone, confirmed: true, payload });
      if (version !== revision) return;
      form.reset(); form.closest("details").open = false;
      if (type === "create_lead") $("candidates").replaceChildren();
      $("feedback").textContent = type === "create_lead" ? "Lead criado." : type === "create_note" ? "Nota interna salva." : "Tarefa agendada.";
      await loadLead(result.lead_id);
    } catch (error) {
      if (version === revision) {
        if (errors[error.message]) feedback(error);
        else $("feedback").textContent = "Não foi possível confirmar o salvamento. Tente novamente com os mesmos dados; a tentativa será recuperada sem duplicar.";
      }
    } finally {
      saving = false;
      for (const control of form.elements) control.disabled = false;
    }
  });
}

function closeAccountMenu() {
  $("account-menu").classList.remove("is-open");
  $("account-actions").hidden = true;
  $("account-toggle").setAttribute("aria-expanded", "false");
}
$("account-toggle").addEventListener("click", () => {
  const open = $("account-toggle").getAttribute("aria-expanded") !== "true";
  $("account-menu").classList.toggle("is-open", open);
  $("account-actions").hidden = !open;
  $("account-toggle").setAttribute("aria-expanded", String(open));
});
document.addEventListener("click", event => { if (!$("account-menu").contains(event.target)) closeAccountMenu(); });
document.addEventListener("keydown", event => { if (event.key === "Escape") { closeAccountMenu(); $("account-toggle").focus(); } });
$("connections").addEventListener("click", closeAccountMenu);
$("disconnect").addEventListener("click", closeAccountMenu);
$("version").textContent = `v${chrome.runtime.getManifest().version}`;

function leadContext(lead) {
  const date = lead.created_at ? new Date(lead.created_at).toLocaleDateString("pt-BR") : null;
  return [`Responsável: ${lead.owner_name || "Sem responsável"}`, lead.origin && `Origem: ${lead.origin}`, date && `Cadastro: ${date}`].filter(Boolean).join(" · ");
}
