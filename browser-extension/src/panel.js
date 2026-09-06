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
  lead_changed: "O status mudou no CRM. Atualize o atendimento antes de tentar novamente.",
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

function showLeadIdentity(visible) {
  $("lead-identity").hidden = !visible;
  $("chat-status").hidden = visible;
}

function clearLead() {
  $("property-category").replaceChildren(new Option("Todas as categorias", ""));
  $("property-quick-options").replaceChildren();
  $("property-quick").value = "";
  propertySelection.clear(); clearPropertySearch();
  showLeadIdentity(false);
  selectedLead = null; resolvedPhone = null;
  $("match-explanation").hidden = true;
  $("lead-context").textContent = "";
  for (const id of ["create-lead", "note", "task", "appointment", "label", "property", "status"]) {
    $(`${id}-panel`).hidden = true; $(`${id}-panel`).open = false;
    $(`${id}-form`).reset();
  }
  $("lead-panel").hidden = true;
  for (const id of ["candidates", "properties", "tasks", "notes", "appointments", "labels", "lead-name", "lead-status"]) $(id).replaceChildren();
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
  const hour = new Date().getHours();
  $("greeting").textContent = me ? (hour < 12 ? "Bom dia," : hour < 18 ? "Boa tarde," : "Boa noite,") : "Seu atendimento, junto da conversa.";
  $("welcome-name").textContent = me?.user?.name || "Unitymob";
  $("account-avatar").textContent = (me?.user?.name || "U").trim().split(/\s+/).slice(0, 2).map(word => Array.from(word)[0]).join("").toLocaleUpperCase("pt-BR");
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
  for (const [kind, capability, add] of [["appointment", "create_appointments", "add-appointments"], ["label", "manage_labels", "add-labels"]]) {
    $(`${kind}-panel`).hidden = !me.capabilities[capability];
    $(add).hidden = !me.capabilities[capability];
    $(`${kind}-contact`).textContent = `${result.lead.name} · ${resolvedPhone}`;
  }
  $("note-panel").hidden = !me.capabilities.create_notes;
  $("task-panel").hidden = !me.capabilities.create_tasks;
  $("add-task").hidden = !me.capabilities.create_tasks;
  $("add-note").hidden = !me.capabilities.create_notes;
  $("actions-help").textContent = me.capabilities.create_notes || me.capabilities.create_tasks || me.capabilities.create_appointments || me.capabilities.manage_labels ? "" : "Seu perfil permite apenas consultar este atendimento. Alterações dependem das permissões do CRM.";
  for (const id of ["note-contact", "task-contact"]) $(id).textContent = `${result.lead.name} · ${resolvedPhone}`;
  $("create-lead-panel").hidden = true;
  $("property-panel").hidden = !me.capabilities.link_properties;
  $("add-properties").hidden = !me.capabilities.link_properties;
  $("property-contact").textContent = `${result.lead.name} · ${resolvedPhone}`;
  $("property-category").replaceChildren(new Option("Todas as categorias", ""), ...(result.property_categories || []).map(category => new Option(category, category)));
  $("property-quick-options").replaceChildren();
  for (const [key, label] of Object.entries(result.property_quick_filters || {})) {
    const button = document.createElement("button"); button.type = "button"; button.className = "ax-label-chip"; button.textContent = label; button.setAttribute("aria-pressed", "false");
    button.onclick = () => {
      $("property-quick").value = $("property-quick").value === key ? "" : key;
      for (const chip of $("property-quick-options").children) chip.setAttribute("aria-pressed", String(chip === button && $("property-quick").value === key));
      $("property-quick").dispatchEvent(new Event("input"));
    };
    $("property-quick-options").append(button);
  }
  propertySelection.clear(); clearPropertySearch();
  showLeadIdentity(true);
  $("match-explanation").hidden = true;
  $("lead-reference").textContent = `Lead #${result.lead.id}`;
  $("lead-avatar").textContent = String(result.lead.name || "?").trim().split(/\s+/).filter(Boolean).slice(0, 2).map(word => Array.from(word)[0]).join("").toLocaleUpperCase("pt-BR");
  $("lead-phone").textContent = resolvedPhone ? `+${resolvedPhone.replace(/\D/g, "")}` : "Telefone não informado";
  $("lead-name").textContent = result.lead.name;
  $("lead-status").textContent = result.lead.status;
  $("status-panel").hidden = !me.capabilities.change_status;
  $("change-status").hidden = !me.capabilities.change_status;
  $("status-contact").textContent = `${result.lead.name} · ${resolvedPhone}`;
  $("status-stage").replaceChildren(new Option("Selecione o novo status", ""));
  for (const stage of result.status_options || []) {
    if (String(stage.id) !== String(result.lead.stage_id)) $("status-stage").append(new Option(stage.name, String(stage.id)));
  }
  $("change-status").disabled = $("status-stage").options.length === 1;
  $("change-status").title = $("change-status").disabled ? "Nenhuma próxima etapa disponível para seu perfil." : "Alterar status do lead";
  $("lead-context").textContent = [me.tenant.name, result.lead.owner_name ? `Responsável: ${result.lead.owner_name}` : "Sem responsável"].join(" · ");
  $("lead-context").title = leadContext(result.lead);
  $("open-lead").href = `${me.origin}/admin/leads/${result.lead.id}`;
  for (const key of ["appointments", "labels"]) {
    $(`${key}-count`).textContent = result[`${key}_count`] ?? result[key]?.length ?? 0;
  }
  $("attempts-count").textContent = result.unsuccessful_attempts ?? 0;
  renderRecords("appointments", (result.appointments || []).map(a => ({ title: a.title, meta: [a.kind, formatDate(a.starts_at)].join(" · ") })), "Nada agendado.");
  renderLabelChoices(result.label_catalog || [], result.labels || []);
  $("properties").replaceChildren();
  for (const property of result.properties) {
    const row = document.createElement("div"); row.className = "ax-property-interest ax-property-interest--detail";
    const check = document.createElement("input"); check.type = "checkbox"; check.value = property.id; check.disabled = !property.public_path; check.title = property.public_path ? "Selecionar para enviar" : "Imóvel sem link público disponível para envio";
    const title = document.createElement("strong"); title.className = "ax-property-interest__title"; title.textContent = `${property.code} · ${property.card_title || property.title}`; title.title = title.textContent;
    const specs = document.createElement("div"); specs.className = "ax-property-interest__specs";
    for (const [icon, value, label] of [["M5 21V3h14v18M2 21h20M15 12h1", property.bedrooms, "Dorm."], ["M8 14a4 4 0 1 1 0-8 4 4 0 0 1 0 8Zm4-4h10m-3 0v3m-3-3v2", property.suites, "Suítes"], ["m5 6-2 7v6h3v-3h12v3h3v-6l-2-7ZM3 12h18M6 14h2m8 0h2", property.parking, "Vagas"], ["M4 9V4h5m11 11v5h-5M4 4l6 6m10 10-6-6", property.area == null ? null : Number(property.area).toLocaleString("pt-BR", {minimumFractionDigits: 1, maximumFractionDigits: 1}), "m²"]]) {
      const chip = document.createElement("span");
      const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg"); svg.setAttribute("viewBox", "0 0 24 24"); svg.setAttribute("fill", "none"); svg.setAttribute("stroke", "currentColor"); svg.setAttribute("stroke-width", "1.6"); svg.setAttribute("aria-hidden", "true");
      const path = document.createElementNS("http://www.w3.org/2000/svg", "path"); path.setAttribute("d", icon); svg.append(path);
      chip.append(svg, document.createTextNode(`${value ?? "—"} ${label}`)); chip.title = `${value ?? "Não informado"} ${label}`; specs.append(chip);
    }
    const money = value => value == null ? "—" : new Intl.NumberFormat("pt-BR", {style: "currency", currency: "BRL", maximumFractionDigits: value === 0 ? 0 : 2}).format(Number(value) / 100);
    const financial = document.createElement("div"); financial.className = "ax-property-interest__financial";
    for (const [tag, text] of [["strong", `${money(property.price_cents)}${property.rental ? "/mês" : ""}`], ["span", `Cond. ${money(property.condo_cents)}`], ["span", `IPTU ${money(property.iptu_cents)}`]]) {
      const part = document.createElement(tag); part.textContent = text; part.title = text; financial.append(part);
    }
    check.setAttribute("aria-label", `Selecionar ${property.code} para enviar`);
    row.append(check, title, specs, financial);
    if (property.removable && me.capabilities.link_properties) {
      const remove = document.createElement("button"); remove.type = "button"; remove.className = "ax-property-interest__remove"; remove.textContent = "×";
      remove.setAttribute("aria-label", `Remover ${property.code} dos interesses`);
      remove.onclick = async () => {
        if (saving) return;
        const version = revision; saving = true; remove.disabled = true;
        try {
          const saved = await request("unlink_property", {tabId: context.tabId, contextKey: contextKey(context), leadId: selectedLead.id, phone: resolvedPhone, confirmed: true, payload: {id: String(property.id)}});
          if (version === revision) await loadLead(saved.lead_id);
        } catch (error) { if (version === revision) feedback(error); }
        finally { saving = false; remove.disabled = false; }
      };
      row.append(remove);
    }
    $("properties").append(row);
  }
  if (!result.properties.length) $("properties").textContent = "Nenhum imóvel de interesse.";
  $("share-properties").hidden = !result.properties.some(property => property.public_path);
  $("share-properties").disabled = true;
  $("properties").onchange = () => { $("share-properties").disabled = saving || !$("properties").querySelector("input:checked"); };
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

let propertySearchVersion = 0;
let propertySearchTimer;
const propertySelection = new Map();
const propertyFilterKeys = ["min_price", "max_price", "suites", "bedrooms", "parking", "category", "quick"];
// Match the desktop currency-mask: values in whole reais, grouping while typing.
for (const key of ["min_price", "max_price"]) $(`property-${key}`).addEventListener("input", event => {
  const digits = event.target.value.replace(/\D/g, "").slice(0, 12);
  event.target.value = digits ? new Intl.NumberFormat("pt-BR", {maximumFractionDigits: 0}).format(Number(digits)) : "";
});
function clearPropertySearch() {
  clearTimeout(propertySearchTimer);
  propertySearchVersion++;
  $("property-form").hidden = true; $("property-options").replaceChildren(); $("property-search-feedback").textContent = "";
}
for (const id of ["property-query", "property-purpose", ...propertyFilterKeys.map(key => `property-${key}`)]) $(id).addEventListener("input", () => {
  clearPropertySearch();
  propertySearchTimer = setTimeout(() => $("property-search-form").requestSubmit(), 300);
});
$("property-search-form").addEventListener("submit", async event => {
  event.preventDefault();
  if (!selectedLead || !ready() || saving || context?.state !== "ready") return;
  clearPropertySearch(); const searchVersion = propertySearchVersion; const version = revision;
  $("property-search-feedback").textContent = "Buscando imóveis…";
  try {
    const result = await request("search_properties", {tabId: context.tabId, contextKey: contextKey(context), leadId: selectedLead.id,
      query: $("property-query").value.trim(), purpose: $("property-purpose").value, filters: Object.fromEntries(propertyFilterKeys.map(key => [key, ["min_price", "max_price"].includes(key) ? $(`property-${key}`).value.replace(/\D/g, "") : $(`property-${key}`).value]))});
    if (version !== revision || searchVersion !== propertySearchVersion) return;
    for (const property of result.properties) {
      const option = document.createElement("label"); option.className = "ax-property-option";
      const input = document.createElement("input"); input.type = "checkbox"; input.name = "property_ids"; input.value = property.id; input.disabled = property.linked; input.checked = property.linked || propertySelection.has(String(property.id));
      input.onchange = () => { if (input.checked && propertySelection.size >= 20) { input.checked = false; $("property-search-feedback").textContent = "Relacione até 20 imóveis por vez."; return; } if (input.checked) propertySelection.set(String(property.id), property); else propertySelection.delete(String(property.id)); $("property-selection-count").textContent = `${propertySelection.size} selecionado(s)`; };
      const title = document.createElement("strong"); title.textContent = [property.code, property.title].filter(Boolean).join(" · ");
      const meta = document.createElement("span"); meta.className = "ax-workspace-muted";
      const price = new Intl.NumberFormat("pt-BR", {style: "currency", currency: "BRL"}).format(Number(property.price_cents) / 100);
      meta.textContent = [property.neighborhood, property.city, price, property.linked ? "Já relacionado" : ""].filter(Boolean).join(" · ");
      option.append(input, title, meta); $("property-options").append(option);
    }
    $("property-form").hidden = !result.properties.some(property => !property.linked) && propertySelection.size === 0;
    $("property-selection-count").textContent = `${propertySelection.size} selecionado(s)`;
    $("property-search-feedback").textContent = !result.properties.length ? "Nenhum imóvel encontrado." : result.properties.every(property => property.linked) ? "Os imóveis encontrados já estão relacionados." : result.more ? "Mostrando 20 imóveis. Refine a busca para encontrar outros." : "Selecione os imóveis que deseja relacionar.";
  } catch (error) { if (version === revision && searchVersion === propertySearchVersion) { $("property-search-feedback").textContent = "Não foi possível buscar os imóveis."; feedback(error); } }
});

function labelChip(label) {
  const chip = document.createElement("span"); chip.className = "ax-label-chip";
  const colors = {red: "#ef4444", amber: "#d97706", green: "#059669", cyan: "#0891b2", purple: "#7c3aed", gray: "#64748b"};
  chip.style.setProperty("--label-color", colors[label.color] || (/^#[0-9a-f]{6}$/i.test(label.color) ? label.color : colors.gray));
  chip.textContent = label.name; return chip;
}
function renderLabelChoices(catalog, assigned) {
  const selected = new Set(assigned.map(label => String(label.id)));
  $("labels").replaceChildren(); $("label-options").replaceChildren();
  for (const label of assigned) $("labels").append(labelChip(label));
  if (!assigned.length) $("labels").textContent = "Nenhuma etiqueta aplicada.";
  for (const label of catalog) {
    const option = document.createElement("label"); option.className = "ax-label-option";
    const input = document.createElement("input"); input.type = "checkbox"; input.name = "label_ids"; input.value = label.id; input.checked = selected.has(String(label.id));
    option.append(input, labelChip(label)); $("label-options").append(option);
  }
  if (!catalog.length) $("label-options").textContent = "Seu catálogo de etiquetas está vazio. Cadastre as etiquetas no CRM.";
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

function toggleDisclosure(panel, open = !panel.open) {
  panel.getAnimations().forEach(animation => animation.cancel());
  const start = panel.getBoundingClientRect().height;
  if (open) panel.open = true;
  const summary = panel.querySelector(":scope > summary");
  const end = open ? panel.getBoundingClientRect().height : (summary?.hidden ? 0 : summary?.getBoundingClientRect().height || 0);
  if (matchMedia("(prefers-reduced-motion: reduce)").matches) { panel.open = open; return; }
  const animation = panel.animate([{height: `${start}px`, opacity: open ? 0.6 : 1}, {height: `${end}px`, opacity: open ? 1 : 0.6}], {duration: 180, easing: "ease-out"});
  panel.style.overflow = "hidden";
  animation.onfinish = () => { panel.open = open; panel.style.overflow = ""; };
  animation.oncancel = () => { panel.style.overflow = ""; };
}
for (const panel of document.querySelectorAll("details")) {
  panel.addEventListener("toggle", () => { if (!panel.open) panel.getAnimations().forEach(animation => animation.cancel()); });
  const summary = panel.querySelector(":scope > summary");
  if (summary && !summary.hidden) summary.addEventListener("click", event => { event.preventDefault(); toggleDisclosure(panel); });
}
for (const [button, kind] of [["add-task", "task"], ["add-note", "note"], ["add-appointments", "appointment"], ["add-labels", "label"], ["add-properties", "property"], ["change-status", "status"]]) {
  const control = $(button), panel = $(`${kind}-panel`);
  const label = control.getAttribute("aria-label") || control.textContent;
  control.setAttribute("aria-controls", panel.id);
  control.setAttribute("aria-expanded", "false");
  panel.addEventListener("toggle", () => {
    control.setAttribute("aria-expanded", String(panel.open));
    control.setAttribute("aria-label", panel.open ? "Fechar formulário" : label);
    if (button !== "change-status") control.textContent = panel.open ? "−" : "＋";
  });
  control.addEventListener("click", () => {
    if (kind === "property" && !panel.open) panel.querySelector(".ax-property-filters").open = true;
    toggleDisclosure(panel);
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

function clearSelected() { propertySelection.clear(); clearPropertySearch(); showLeadIdentity(false); selectedLead = null; for (const id of ["note", "task", "appointment", "label", "property", "status"]) { $(`${id}-form`).reset(); $(`${id}-panel`).open = false; } $("lead-panel").hidden = true; $("open-lead").removeAttribute("href"); }

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
        const accountChanged = JSON.stringify(me) !== JSON.stringify(next);
        if (!me || me.origin !== next.origin || me.user.id !== next.user.id || me.tenant.id !== next.tenant.id || ready() !== next.capabilities.read_leads) {
          clearContext(); $("terms-accepted").checked = false; $("accept-terms").disabled = true;
        }
        me = next;
        if (accountChanged) renderAccount();
      } catch (error) { if (["not_connected", "http_401", "http_403"].includes(error.message)) { me = null; clearContext(); renderAccount(); } else if (force) feedback(error); }
    }
    if (!me) renderAccount();
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
    if (!force && context?.state === "ready" && ["changed", "loading", "unavailable"].includes(next.state)) return;
    if (!force && next.state === "ready" && next.account === context?.account && next.chatId === context?.chatId && context?.phone && !next.phone) return;
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
  } catch (error) { if (force) feedback(error); }
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
document.addEventListener("visibilitychange", () => { if (!document.hidden) refresh(); });
chrome.tabs.onActivated.addListener(() => refresh());
chrome.tabs.onUpdated.addListener((id, change) => { if (context?.tabId === id && (change.url || change.status === "loading")) { clearContext(); refresh(); } });
setInterval(() => refresh(), 2500);
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


for (const [formId, type] of [["create-lead-form", "create_lead"], ["note-form", "create_note"], ["task-form", "create_task"], ["appointment-form", "create_appointment"], ["label-form", "set_labels"], ["property-form", "link_properties"], ["status-form", "change_status"]]) {
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
      type === "change_status" ? { stage_id: $("status-stage").value, expected_stage_id: String(target.stage_id || "") } :
      type === "link_properties" ? { ids: [...propertySelection.keys()].sort().join(",") } :
      type === "set_labels" ? { ids: [...$("label-options").querySelectorAll("input:checked")].map(input => input.value).sort().join(",") } :
      type === "create_appointment" ? { title: $("appointment-title").value.trim(), kind: $("appointment-kind").value,
        starts_at: new Date($("appointment-start").value).toISOString(), ends_at: $("appointment-end").value ? new Date($("appointment-end").value).toISOString() : "", location: $("appointment-location").value.trim() } :
      { title: $("task-title").value.trim(), kind: $("task-kind").value, priority: $("task-priority").value, due_at: new Date($("task-due").value).toISOString() };
    if (type === "link_properties" && !payload.ids) { $("feedback").textContent = "Selecione pelo menos um imóvel."; return; }
    saving = true;
    for (const control of form.elements) control.disabled = true;
    $("feedback").textContent = "Salvando…";
    try {
      const result = await request(type, { tabId: context.tabId, contextKey: contextKey(context), leadId: target?.id,
        phone, confirmed: true, payload });
      if (version !== revision) return;
      form.reset(); form.closest("details").open = false;
      if (type === "create_lead") $("candidates").replaceChildren();
      $("feedback").textContent = type === "create_lead" ? "Lead criado." : type === "create_note" ? "Nota interna salva." : type === "create_appointment" ? "Compromisso agendado." : type === "set_labels" ? "Etiquetas atualizadas." : type === "link_properties" ? "Imóveis relacionados." : type === "change_status" ? "Status atualizado." : "Tarefa agendada.";
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

$("share-properties").addEventListener("click", async () => {
  if (!selectedLead || !ready() || saving) return;
  const checked = [...$("properties").querySelectorAll("input:checked")];
  if (!checked.length || !window.confirm(`Enviar agora para ${context.name || selectedLead.name} (${resolvedPhone})?\n\n${checked.map(input => input.closest(".ax-property-interest").querySelector("strong").textContent).join("\n")}`)) return;
  const version = revision;
  saving = true; $("share-properties").disabled = true;
  $("share-properties").textContent = "Enviando…"; $("share-properties").setAttribute("aria-busy", "true");
  try {
    await request("send_properties", {tabId: context.tabId, contextKey: contextKey(context), leadId: selectedLead.id, confirmed: true, phone: resolvedPhone,
      ids: [...$("properties").querySelectorAll("input:checked")].map(input => input.value)});
    if (version === revision) $("feedback").textContent = "Imóveis enviados para a conversa.";
  } catch (error) {
    if (version === revision) $("feedback").textContent = "Não foi possível confirmar o envio. Confira a conversa antes de tentar novamente.";
  }
  finally {
    saving = false; $("share-properties").disabled = !$("properties").querySelector("input:checked");
    $("share-properties").textContent = "Enviar selecionados no WhatsApp"; $("share-properties").removeAttribute("aria-busy");
  }
});
