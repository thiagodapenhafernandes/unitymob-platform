import { mountPropertyCatalog } from "./property-catalog.js";
import { mountWorkspaceTabs } from "./workspace-tabs.js";
import { crmOrigin, discoveryOrigin } from "./config.js";
import { contextKey, shouldReloadContext } from "./context.js";
import { isWhatsAppTab } from "./security.js";

const $ = id => document.getElementById(id);
mountWorkspaceTabs(document.getElementById("workspace-panel"), chrome.storage.local);
const editedForms = new Set();
for (const form of document.querySelectorAll("#workspace-panel form")) {
  form.addEventListener("input", () => editedForms.add(form));
  form.addEventListener("change", () => editedForms.add(form));
  form.addEventListener("reset", () => editedForms.delete(form));
}
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
  invalid_email: "Informe um e-mail válido, como nome@empresa.com.br. Confira se não há espaços ou erros de digitação.",
  code_send_failed: "Não conseguimos enviar o código agora. Tente novamente mais tarde.",
  discovery_connection_failed: "Não conseguimos acessar o serviço de login. Confira sua conexão e tente novamente.",
  already_connected: "Há uma conexão anterior salva. Clique em Encerrar conexão anterior para iniciar um novo login.",
  login_cancelled: "O login foi cancelado. Clique em Entrar novamente e conclua o acesso na janela da imobiliária.",
  login_window_failed: "O Chrome não conseguiu abrir ou concluir a janela de login. Abra o sistema da imobiliária no navegador, confira seu acesso e tente novamente.",
  invalid_callback: "O sistema não retornou uma autorização válida para a extensão. Inicie o login novamente.",
  permission_required: "Autorize o acesso da extensão ao domínio da imobiliária para continuar.",
  lead_changed: "O status mudou no CRM. Atualize o atendimento antes de tentar novamente.",
  account_mismatch: "O login pertence a outra conta ou usuário. Entre no CRM com o e-mail confirmado e a imobiliária escolhida.",
  invalid_code: "Código incorreto, expirado ou já utilizado. Confira os 6 dígitos do último e-mail ou solicite um novo código.",
  discovery_rate_limited: "Muitas tentativas. Aguarde 10 minutos antes de solicitar outro código.",
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
  $("contact-history").hidden = !visible;
  $("workspace-panel").dispatchEvent(new CustomEvent("workspace:lead-state", { detail: visible }));
  $("lead-identity").hidden = !visible;
  $("chat-status").hidden = visible;
}

function clearLead() {
  propertySelection.clear(); clearPropertySearch();
  propertyCatalog.reset();
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
  $("open-lead").hidden = true; $("open-lead").removeAttribute("href");
}

function clearContext() {
  revision++; context = null; closePropertyGallery(); editedForms.clear(); clearLead(); $("search-form").hidden = true; $("phone").value = "";
}

function feedback(error) {
  $("reset-connection").hidden = error.message !== "already_connected";
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
  $("connect-form").querySelector("button").textContent = discoveryOrigin ? "Enviar código por e-mail" : "Entrar na Unitymob";
  $("discovery-restart").textContent = discoveryStep === "accounts" ? "Usar outro e-mail" : "Corrigir e-mail ou solicitar novo código";
  $("discovery-restart").disabled = pairing;
  $("discovery-accounts").querySelectorAll("button").forEach(button => { button.disabled = pairing; });
  $("connection-status").hidden = !me && discoveryStep === "accounts" && !pairing;
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
  $("note-panel").hidden = !me.capabilities.create_notes || !result.contact_options;
  $("task-panel").hidden = !me.capabilities.create_tasks;
  $("add-task").hidden = !me.capabilities.create_tasks;
  $("add-note").hidden = !me.capabilities.create_notes || !result.contact_options;
  renderContactOptions(result.contact_options);
  $("actions-help").textContent = me.capabilities.create_notes || me.capabilities.create_tasks || me.capabilities.create_appointments || me.capabilities.manage_labels || me.capabilities.link_properties || me.capabilities.change_status ? "" : "Seu perfil permite apenas consultar este atendimento. Alterações dependem das permissões do CRM.";
  for (const id of ["note-contact", "task-contact"]) $(id).textContent = `${result.lead.name} · ${resolvedPhone}`;
  $("create-lead-panel").hidden = true;
  $("property-panel").hidden = !me.capabilities.link_properties;
  $("add-properties").hidden = !me.capabilities.link_properties;
  $("property-contact").textContent = `${result.lead.name} · ${resolvedPhone}`;
  propertySelection.clear(); clearPropertySearch();
  propertyCatalog.reset();
  queueMicrotask(() => { if(selectedLead) propertyCatalog.activate(); });
  showLeadIdentity(true);
  $("match-explanation").hidden = true;
  $("lead-reference").textContent = `Lead #${result.lead.id}`;
  $("lead-avatar").textContent = String(result.lead.name || "?").trim().split(/\s+/).filter(Boolean).slice(0, 2).map(word => Array.from(word)[0]).join("").toLocaleUpperCase("pt-BR");
  $("lead-phone").textContent = resolvedPhone ? `+${resolvedPhone.replace(/\D/g, "")}` : "Telefone não informado";
  $("lead-name").textContent = result.lead.name;
  $("lead-status").textContent = result.lead.status;
  $("lead-status").dataset.tone = ({"Em Atendimento": "success", "Concluido": "success", "Novo": "info", "Aguardando Aceite": "warning", "Represado": "warning", "Descartado": "danger"})[result.lead.status] || "neutral";
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
  $("open-lead").hidden = false; $("open-lead").href = `${me.origin}/admin/leads/${result.lead.id}`;
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
    check.setAttribute("aria-label", `Selecionar ${property.code} para enviar`);
    const content = propertyCardContent(property);
    const photos = (property.photo_urls || []).filter(url => { try { return ["https:", "http:"].includes(new URL(url).protocol); } catch { return false; } });
    if (photos.length) {
      const link = document.createElement("button"); link.type = "button"; link.className = "ax-property-photos"; link.textContent = "Ver fotos";
      link.setAttribute("aria-label", `Ver fotos de ${property.code} · ${property.card_title || property.title}`);
      link.onclick = () => openPropertyGallery(photos, `${property.code} · ${property.card_title || property.title}`);
      content[0].append(link); content[0].classList.add("ax-property-interest__title--photos");
    }
    row.append(check, ...content);
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
  renderRecords("notes", (result.notes || []).map(n => ({ title: n.kind || "Anotação interna", meta: [n.result, formatDate(n.created_at), n.author].filter(Boolean).join(" · "), body: n.body })), "Nenhum contato registrado.");
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
const propertyCatalog = mountPropertyCatalog({search: () => $("property-search-form").requestSubmit(), clearSelection: () => propertySelection.clear()});
function clearPropertySearch() {
  clearTimeout(propertySearchTimer);
  propertySearchVersion++;
  $("property-form").hidden = true; $("property-options").replaceChildren(); $("property-search-feedback").textContent = "";
}
$("property-search-form").addEventListener("submit", async event => {
  event.preventDefault();
  if (!selectedLead || !ready() || saving || context?.state !== "ready") return;
  const criteria = propertyCatalog.criteria();
  if(criteria.page === 1) clearPropertySearch();
  const searchVersion = ++propertySearchVersion; const version = revision;
  propertyCatalog.loading();
  $("property-search-feedback").textContent = "Buscando imóveis…";
  try {
    const result = await request("search_properties", {tabId: context.tabId, contextKey: contextKey(context), leadId: selectedLead.id,
      ...criteria});
    if (version !== revision || searchVersion !== propertySearchVersion) return;
    propertyCatalog.update(result);
    const available = result.properties;
    for (const property of available) {
      const option = document.createElement("label"); option.className = "pc-card";
      const input = document.createElement("input"); input.type = "checkbox"; input.name = "property_ids"; input.value = property.id; input.checked = propertySelection.has(String(property.id)); input.disabled = !!property.linked || !me?.capabilities?.link_properties; input.dataset.locked = String(input.disabled);
      input.onchange = () => { if (input.checked && propertySelection.size >= 20) { input.checked = false; $("property-search-feedback").textContent = "Relacione até 20 imóveis por vez."; return; } if (input.checked) propertySelection.set(String(property.id), property); else propertySelection.delete(String(property.id)); $("property-selection-count").textContent = `${propertySelection.size} selecionado(s)`; };
      input.setAttribute("aria-label", `Selecionar ${property.code} · ${property.card_title || property.title}`);
      const imageUrl = property.photo_urls?.[0];
      if(typeof imageUrl === "string" && /^https:\/\//.test(imageUrl)) { const image=document.createElement("img"); image.src=imageUrl; image.alt=property.card_title || property.title; image.loading="lazy"; image.referrerPolicy="no-referrer"; image.onerror=()=>image.remove(); option.append(image); }
      const body=document.createElement("div"); body.className="pc-card-body"; body.append(...propertyCardContent(property, true));
      const selection=document.createElement("span");selection.className="pc-pick";selection.append(input,document.createTextNode(property.linked?"Já relacionado ao lead":"Selecionar imóvel"));body.append(selection);option.append(body);$("property-options").append(option);
    }
    $("property-form").hidden = !available.length && propertySelection.size === 0;
    $("property-form").querySelector('.ax-confirmation').hidden = !me.capabilities.link_properties;
    $("property-form").querySelector('button[type="submit"]').hidden = !me.capabilities.link_properties;
    $("property-selection-count").textContent = `${propertySelection.size} selecionado(s)`;
    $("property-search-feedback").textContent = !available.length ? "Nenhum imóvel disponível para adicionar com estes filtros." : result.more ? "Há mais imóveis. Use Carregar mais imóveis para continuar." : `${available.length} imóvel(is) disponível(is). Selecione para relacionar.`;
  } catch (error) { if (version === revision && searchVersion === propertySearchVersion) { propertyCatalog.failed(); $("property-search-feedback").textContent = "Não foi possível buscar os imóveis. Confira os filtros e tente novamente."; feedback(error); } }
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
for (const [button, kind] of [["add-task", "task"], ["add-note", "note"], ["add-appointments", "appointment"], ["add-labels", "label"], ["change-status", "status"]]) {
  const control = $(button), panel = $(`${kind}-panel`);
  const label = control.getAttribute("aria-label") || control.textContent;
  if (button !== "change-status") control.innerHTML = '<i class="bi bi-plus-lg" aria-hidden="true"></i>';
  control.setAttribute("aria-controls", panel.id);
  control.setAttribute("aria-expanded", "false");
  panel.addEventListener("toggle", () => {
    control.setAttribute("aria-expanded", String(panel.open));
    control.setAttribute("aria-label", panel.open ? "Fechar formulário" : label);
    if (button !== "change-status") control.innerHTML = `<i class="bi bi-${panel.open ? "dash-lg" : "plus-lg"}" aria-hidden="true"></i>`;
  });
  control.addEventListener("click", () => {
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

function clearSelected() { propertyCatalog.reset(); propertySelection.clear(); clearPropertySearch(); showLeadIdentity(false); selectedLead = null; for (const id of ["note", "task", "appointment", "label", "property", "status"]) { $(`${id}-form`).reset(); $(`${id}-panel`).open = false; } $("lead-panel").hidden = true; $("open-lead").hidden = true; $("open-lead").removeAttribute("href"); }

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
    const editing = saving || editedForms.size > 0 || !!document.activeElement?.closest("form");
    if (force && !changed && editing) $("feedback").textContent = "Seu preenchimento foi mantido. Conclua a edição antes de atualizar.";
    if (shouldReloadContext(changed, force, editing)) {
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
    if (!(await chrome.permissions.request({ origins: [`${origin}/*`] }).catch(() => { throw new Error("permission_required"); }))) throw new Error("permission_required");
    pairing = true; renderAccount(); $("feedback").textContent = "";
    await request("connect", account ? { accountId: account.id } : {});
    pairing = false; lastSessionCheck = 0; await refreshSession(true);
  } catch (error) { pairing = false; renderAccount(); feedback(error); }
}
$("discovery-email").addEventListener("input", event => event.target.setCustomValidity(""));
$("discovery-email").addEventListener("invalid", event => {
  event.target.setCustomValidity(errors.invalid_email);
  $("feedback").textContent = errors.invalid_email;
});
$("connect-form").addEventListener("submit", async event => {
  event.preventDefault();
  if (!discoveryOrigin) return connectAccount();
  const button = event.currentTarget.querySelector("button"); button.disabled = true;
  button.textContent = "Enviando código…"; button.setAttribute("aria-busy", "true"); $("feedback").textContent = "";
  try {
    await request("discovery_start", { email: $("discovery-email").value });
    $("discovery-sent-to").textContent = `Código enviado para ${$("discovery-email").value.trim().toLowerCase()}.`;
    discoveryStep = "code"; $("discovery-code-form").reset(); renderAccount(); $("discovery-code").focus();
  } catch (error) { feedback(error); }
  finally { button.disabled = false; button.removeAttribute("aria-busy"); button.textContent = "Enviar código por e-mail"; }
});
$("discovery-code-form").addEventListener("submit", async event => {
  event.preventDefault();
  const button = event.currentTarget.querySelector("button"); button.disabled = true;
  button.textContent = "Confirmando código…"; button.setAttribute("aria-busy", "true"); $("feedback").textContent = "";
  try {
    const result = await request("discovery_verify", { code: $("discovery-code").value });
    $("feedback").textContent = "";
    discoveryStep = "accounts"; $("discovery-accounts").replaceChildren();
    const text = document.createElement("p"); text.textContent = result.accounts.length ? (result.accounts.length === 1 ? "Conta encontrada. Continue para entrar:" : "Escolha a imobiliária em que deseja entrar:") : "Não encontramos uma conta ativa vinculada a este e-mail. Use outro e-mail ou peça ao administrador da imobiliária para conferir seu cadastro.";
    $("discovery-accounts").append(text);
    for (const account of result.accounts) {
      const card = document.createElement("div"); card.className = "ax-operational-panel";
      const body = document.createElement("div"); body.className = "ax-operational-panel__body ax-record-list";
      const name = document.createElement("strong"); name.textContent = account.name;
      const domain = document.createElement("small"); domain.textContent = new URL(account.origin).hostname;
      const choice = document.createElement("button"); choice.type = "button"; choice.className = "ax-btn ax-btn--primary";
      choice.textContent = `Entrar em ${account.name}`;
      choice.addEventListener("click", () => connectAccount(account));
      body.append(name, domain, choice); card.append(body); $("discovery-accounts").append(card);
    }
    renderAccount();
  } catch (error) { feedback(error); }
  finally { button.disabled = false; button.removeAttribute("aria-busy"); button.textContent = "Confirmar e-mail"; }
});
$("discovery-restart").addEventListener("click", () => { discoveryStep = "email"; renderAccount(); });
for (const id of ["disconnect", "switch-account", "reset-connection"]) {
  $(id).addEventListener("click", async () => {
    try { await request("disconnect"); $("reset-connection").hidden = true; $("feedback").textContent = ""; me = null; discoveryStep = "email"; clearContext(); renderAccount(); }
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


function renderContactOptions(options) {
  for (const [id, entries, placeholder] of [["contact-kind", options?.kinds, null], ["contact-result", options?.results, "Selecione o resultado..."]]) {
    const select = $(id), previous = select.value;
    select.replaceChildren();
    if (placeholder) select.add(new Option(placeholder, ""));
    for (const [value, label] of Object.entries(entries || {})) select.add(new Option(label, value));
    if ([...select.options].some(option => option.value === previous)) select.value = previous;
  }
  $("contact-kind").dataset.attemptKinds = JSON.stringify(options?.attempt_kinds || []);
  syncContactResult();
}
function syncContactResult() {
  const operational = JSON.parse($("contact-kind").dataset.attemptKinds || "[]").includes($("contact-kind").value);
  $("contact-result-field").hidden = !operational;
  $("contact-result").required = operational;
  $("contact-result").disabled = !operational;
  if (!operational) $("contact-result").value = "";
}
$("contact-kind").addEventListener("change", syncContactResult);
$("note-form").addEventListener("reset", () => queueMicrotask(syncContactResult));

for (const [formId, type] of [["create-lead-form", "create_lead"], ["note-form", "create_contact"], ["task-form", "create_task"], ["appointment-form", "create_appointment"], ["label-form", "set_labels"], ["property-form", "link_properties"], ["status-form", "change_status"]]) {
  $(formId).addEventListener("submit", async event => {
    event.preventDefault();
    if (saving || !ready() || context?.state !== "ready" || !resolvedPhone) return;
    if (type !== "create_lead" && !selectedLead) return;
    const version = revision;
    const target = selectedLead;
    const phone = resolvedPhone;
    const form = event.currentTarget;
    const payload = type === "create_lead" ? { name: $("new-lead-name").value.trim(), email: $("new-lead-email").value.trim() } :
      type === "create_contact" ? { body: $("note-body").value.trim(), contact_kind: $("contact-kind").value, contact_result: $("contact-result").value } :
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
      form.reset(); if(form.closest("details")) form.closest("details").open = false;
      if (type === "create_lead") $("candidates").replaceChildren();
      $("feedback").textContent = type === "create_lead" ? "Lead criado." : type === "create_contact" ? "Contato registrado." : type === "create_appointment" ? "Compromisso agendado." : type === "set_labels" ? "Etiquetas atualizadas." : type === "link_properties" ? "Imóveis relacionados." : type === "change_status" ? "Status atualizado." : "Tarefa agendada.";
      await loadLead(result.lead_id);
    } catch (error) {
      if (version === revision) {
        if (errors[error.message]) feedback(error);
        else $("feedback").textContent = "Não foi possível confirmar o salvamento. Tente novamente com os mesmos dados; a tentativa será recuperada sem duplicar.";
      }
    } finally {
      saving = false;
      for (const control of form.elements) control.disabled = control.dataset.locked === "true";
      if (type === "create_contact") syncContactResult();
      if (version === revision && selectedLead) propertyCatalog.activate();
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

function propertyCardContent(property, catalog = false) {
    const title = document.createElement("strong"); title.className = catalog ? "pc-title" : "ax-property-interest__title"; title.textContent = `${property.code} · ${property.card_title || property.title}`; title.title = title.textContent;
    const specs = document.createElement("div"); specs.className = catalog ? "pc-specs" : "ax-property-interest__specs";
    for (const [value, label] of [[property.bedrooms, "Dorm."], [property.suites, "Suítes"], [property.parking, "Vagas"], [property.area == null ? null : Number(property.area).toLocaleString("pt-BR", {minimumFractionDigits: 1, maximumFractionDigits: 1}), "m²"]]) {
      const chip = document.createElement("span");
      const glyph = document.createElement("i"); glyph.className = `bi bi-${({"Dorm.": "door-open", "Suítes": "key", "Vagas": "car-front", "m²": "arrows-angle-expand"})[label]}`; glyph.setAttribute("aria-hidden", "true");
      chip.append(glyph, document.createTextNode(`${value ?? "—"} ${label}`)); chip.title = `${value ?? "Não informado"} ${label}`; specs.append(chip);
    }
    const money = value => value == null ? "—" : new Intl.NumberFormat("pt-BR", {style: "currency", currency: "BRL", maximumFractionDigits: value === 0 ? 0 : 2}).format(Number(value) / 100);
    const financial = document.createElement("div"); financial.className = "ax-property-interest__financial";
    for (const [tag, text] of [["strong", `${money(property.price_cents)}${property.rental ? "/mês" : ""}`], ["span", `Cond. ${money(property.condo_cents)}`], ["span", `IPTU ${money(property.iptu_cents)}`]]) {
      const part = document.createElement(tag); part.textContent = text; part.title = text; financial.append(part);
    }
    const location = document.createElement("span"); location.className = catalog ? "pc-location" : "ax-property-interest__location";
    const pin = document.createElement("i"); pin.className = "bi bi-geo-alt"; pin.setAttribute("aria-hidden", "true");
    location.append(pin, document.createTextNode([property.neighborhood, property.city].filter(Boolean).join(" · ") || "Localização não informada")); location.title = location.textContent;
    if(catalog) {
      financial.className="pc-financial";
      financial.replaceChildren();
      const label=document.createElement("small");label.textContent="VALOR DO IMÓVEL";
      const price=document.createElement("strong");price.textContent=`${money(property.price_cents)}${property.rental?"/mês":""}`;
      const costs=document.createElement("div");
      for(const [name,value] of [["Condomínio",property.condo_cents],["IPTU",property.iptu_cents]]){const item=document.createElement("span");item.textContent=name;const amount=document.createElement("b");amount.textContent=money(value);item.append(amount);costs.append(item);}
      financial.append(label,price,costs);
      const purpose=document.createElement("small");purpose.className="pc-kind";purpose.textContent=property.rental?"LOCAÇÃO":"VENDA";
      const owner=document.createElement("span");owner.className="pc-location";owner.textContent=property.owner?`Captador: ${property.owner}`:"";
      return [title,purpose,location,owner,specs,financial];
    }
    return [title, location, specs, financial];
}

let propertyGallery;
function closePropertyGallery() { if (propertyGallery?.open) propertyGallery.close(); }
function openPropertyGallery(photos, title) {
  propertyGallery?.remove();
  const dialog = document.createElement("dialog"); propertyGallery = dialog; dialog.className = "ax-property-gallery";
  const heading = document.createElement("strong"); heading.id = "property-gallery-title"; heading.textContent = title;
  dialog.setAttribute("aria-labelledby", heading.id);
  const close = document.createElement("button"); close.type = "button"; close.textContent = "Fechar"; close.onclick = () => dialog.close();
  let image = document.createElement("img"); image.style.visibility = "hidden";
  const feedback = document.createElement("p"); feedback.setAttribute("role", "status");
  const nav = document.createElement("div"); const prev = document.createElement("button"), next = document.createElement("button"), count = document.createElement("span");
  prev.type = next.type = "button"; prev.textContent = "Anterior"; next.textContent = "Próxima"; count.setAttribute("aria-live", "polite");
  let index = 0, requestId = 0;
  const render = async () => {
    const currentRequest = ++requestId, requestedIndex = index;
    feedback.textContent = "Carregando foto…";
    dialog.setAttribute("aria-busy", "true");
    prev.disabled = index === 0; next.disabled = index === photos.length - 1;
    const incoming = new Image(); incoming.referrerPolicy = "no-referrer";
    incoming.alt = `${title} — foto ${requestedIndex + 1}`;
    incoming.src = photos[requestedIndex];
    try {
      await incoming.decode();
      if (currentRequest !== requestId || !dialog.open) return;
      image.replaceWith(incoming); image = incoming;
      if (!matchMedia("(prefers-reduced-motion: reduce)").matches) image.animate([{opacity: .5}, {opacity: 1}], {duration: 180, easing: "ease-out"});
      count.textContent = `${requestedIndex + 1} / ${photos.length}`;
      feedback.textContent = "";
    } catch {
      if (currentRequest !== requestId || !dialog.open) return;
      feedback.textContent = "Não foi possível carregar esta foto. Tente a próxima.";
    } finally {
      if (currentRequest === requestId) dialog.removeAttribute("aria-busy");
    }
  };
  dialog.addEventListener("close", () => { requestId++; });
  prev.onclick = () => { if (index > 0) { index--; render(); } }; next.onclick = () => { if (index < photos.length - 1) { index++; render(); } };
  dialog.addEventListener("keydown", event => { if (event.key === "ArrowLeft") { event.preventDefault(); prev.click(); } if (event.key === "ArrowRight") { event.preventDefault(); next.click(); } });
  nav.append(prev, count, next); dialog.append(heading, close, image, feedback, nav); document.body.append(dialog); dialog.showModal(); render();
}
