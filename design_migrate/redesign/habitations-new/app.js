/* ============================================================
   Redesign — Cadastro de imóvel — dinâmicas simuladas
   Reproduz os comportamentos do habitation-form Stimulus + afins:
   tabs, tipo→categoria, status→suspensão, empreendimento→autofill,
   CEP, calculadora de aluguel, chips, máscaras, attribute-manager.
   ============================================================ */

/* ---------- Data ---------- */
const CATEGORIES = {
  apartamentos: ["Apartamento", "Cobertura", "Loft", "Studio"],
  comerciais_industriais: ["Sala Comercial", "Loja", "Prédio Comercial", "Galpão", "Galpão Industrial", "Área", "Casa comercial", "Ponto Comercial"],
  empreendimento: ["Empreendimento"],
  imoveis_residenciais: ["Casa", "Casa em Condomínio", "Sobrado", "Rural", "Condomínio", "Chácara", "Sítio"],
  terrenos: ["Terreno", "Terreno em Condomínio", "Área", "Terreno Comercial", "Terreno Industrial"],
};
const DEVELOPMENTS = {
  "EMP-1001": { nome: "Residencial Marina", proprietor: "3", captador: "10", delivery: "2026-12-01", profile: "Alto padrão",
    address: { streetType: "Avenida", street: "Av. Beira Mar", number: "1500", uf: "SC", zip: "88015-700", neighborhood: "Centro", city: "São Paulo" } },
  "EMP-1002": { nome: "Edifício Aurora", proprietor: "2", captador: "11", delivery: "2025-06-15", profile: "Médio padrão",
    address: { streetType: "Rua", street: "Rua das Flores", number: "320", uf: "SP", zip: "01310-100", neighborhood: "Jardins", city: "São Paulo" } },
  "EMP-1003": { nome: "Condomínio Vista Verde", proprietor: "1", captador: "10", delivery: "2027-03-01", profile: "Econômico",
    address: { streetType: "Rua", street: "Rua Verde", number: "45", uf: "MG", zip: "30140-071", neighborhood: "Vila Nova", city: "Belo Horizonte" } },
};
const FEATURES = ["Ar condicionado", "Armários planejados", "Closet", "Cozinha americana", "Despensa", "Escritório", "Lareira", "Lavabo", "Mobiliado", "Piso porcelanato", "Sacada gourmet", "Varanda"];
const INFRA = ["Piscina", "Academia", "Salão de festas", "Playground", "Churrasqueira", "Quadra esportiva", "Sauna", "Espaço gourmet", "Portaria 24h", "Elevador", "Gerador", "Bicicletário"];
const BADGES = ["Vista para o mar", "Reformado", "Pronto para morar", "Aceita pet", "Andar alto", "Documentação ok", "Oportunidade"];
const CEP_DB = { seed: { streetType: "Avenida", street: "Av. Paulista", number: "", uf: "SP", neighborhood: "Centro", city: "São Paulo" } };

const TABS = [
  { id: "general", icon: "house-door", label: "Base", desc: "Identificação, vínculo e endereço" },
  { id: "features", icon: "rulers", label: "Estrutura", desc: "Dimensões e atributos" },
  { id: "infra", icon: "building", label: "Empreendimento", desc: "Edifício e lazer" },
  { id: "comercial", icon: "briefcase", label: "Comercial", desc: "Valores, negociação e contatos" },
  { id: "seo", icon: "globe2", label: "Publicação", desc: "Site, portais e SEO" },
  { id: "media", icon: "images", label: "Mídia", desc: "Fotos, vídeos e tour" },
  { id: "documents", icon: "folder2", label: "Documentos", desc: "Fichas e autorizações" },
];
// completion state (simulated): general & features start "success", seo warning until Site flag on
const tabState = { general: "success", features: "success", infra: "neutral", comercial: "neutral", seo: "warning", media: "neutral", documents: "neutral" };
// pending-validation counts per tab (red sinalizador badge). Cleared as fields are filled.
const tabErrors = { general: 0, features: 0, infra: 0, comercial: 2, seo: 0, media: 0, documents: 0 };

/* ---------- Tabs ---------- */
let activeTab = "general";
function buildTabs() {
  const nav = document.getElementById("tabsNav");
  const rail = document.getElementById("asideRail");
  nav.innerHTML = "";
  rail.innerHTML = "";
  TABS.forEach((t) => {
    const err = tabErrors[t.id] || 0;
    const tone = err > 0 ? "danger" : tabState[t.id];
    let ind;
    if (err > 0) ind = `<span class="tab-error" title="${err} campo(s) com pendência">${err}</span>`;
    else if (tone === "success") ind = `<i class="bi bi-check-circle-fill tabs-nav__ind tabs-nav__ind--success" title="Completo"></i>`;
    else if (tone === "warning") ind = `<i class="bi bi-exclamation-circle-fill tabs-nav__ind tabs-nav__ind--warning" title="Atenção"></i>`;
    else ind = `<span class="tabs-nav__ind--neutral" title="Vazio"></span>`;

    const btn = document.createElement("button");
    btn.className = "tabs-nav__item" + (t.id === activeTab ? " active" : "");
    btn.innerHTML = `
      <span class="tabs-nav__icon"><i class="bi bi-${t.icon}"></i></span>
      <span class="tabs-nav__copy"><strong>${t.label}</strong><span>${t.desc}</span></span>
      <span class="tabs-nav__status">${ind}</span>`;
    btn.addEventListener("click", () => showTab(t.id));
    nav.appendChild(btn);

    const r = document.createElement("button");
    r.className = "aside-rail__item" + (t.id === activeTab ? " active" : "");
    r.title = t.label + (err > 0 ? ` — ${err} pendência(s)` : "");
    r.innerHTML = `<i class="bi bi-${t.icon}"></i>${err > 0 ? `<span class="tab-error">${err}</span>` : ""}`;
    r.addEventListener("click", () => showTab(t.id));
    rail.appendChild(r);
  });
  updateProgress();
}
function showTab(id) {
  activeTab = id;
  document.querySelectorAll(".tab-pane").forEach((p) => p.classList.toggle("active", p.id === `tab-${id}`));
  buildTabs();
  document.querySelector(".workspace-main").scrollTo?.({ top: 0 });
  window.scrollTo({ top: 0, behavior: "smooth" });
}
function updateProgress() {
  const done = TABS.filter((t) => tabState[t.id] === "success").length;
  document.getElementById("progCount").textContent = done;
  document.getElementById("progBar").style.width = Math.round((done / TABS.length) * 100) + "%";
}

/* ---------- Aside collapse (right editor) + explorer (left) ---------- */
document.getElementById("asideToggle").addEventListener("click", () =>
  document.getElementById("editorAside").classList.toggle("collapsed")
);
document.getElementById("explorerToggle").addEventListener("click", () =>
  document.getElementById("explorer").classList.toggle("collapsed")
);

/* ---------- Toggle chips ---------- */
function initToggles() {
  document.querySelectorAll("[data-toggle]").forEach((chip) => {
    const input = chip.querySelector('input[type="checkbox"]');
    const sync = () => chip.classList.toggle("is-checked", input.checked);
    sync();
    chip.addEventListener("click", (e) => {
      e.preventDefault();
      if (chip.classList.contains("is-disabled")) return;
      input.checked = !input.checked;
      sync();
      // "Site" flag → seo tab success
      if (chip.querySelector("span:last-child")?.textContent.trim() === "Site") {
        tabState.seo = input.checked ? "success" : "warning";
        buildTabs();
      }
      // portal toggle → expand sub
      if (chip.hasAttribute("data-portal-toggle")) {
        chip.closest("[data-portal]").classList.toggle("is-on", input.checked);
      }
    });
  });
}

/* ---------- Collapsible sections ---------- */
function initSections() {
  document.querySelectorAll("[data-section-toggle]").forEach((head) => {
    head.addEventListener("click", (e) => {
      if (e.target.closest("[data-toggle]") || e.target.closest("button")) return;
      head.closest("[data-section]").classList.toggle("is-collapsed");
    });
  });
}

/* ---------- Cadastro type → categoria + tipo + unitOnly + label ---------- */
function fillCategories(typeKey, keepValue) {
  const sel = document.getElementById("categorySelect");
  const cats = CATEGORIES[typeKey] || [];
  const cur = keepValue ? sel.value : null;
  sel.innerHTML = '<option value="">Selecione...</option>';
  cats.forEach((c) => { const o = new Option(c, c); sel.add(o); });
  if (typeKey === "empreendimento") sel.value = "Empreendimento";
  else if (cur && cats.includes(cur)) sel.value = cur;
}
function applyCadastroType() {
  const typeKey = document.querySelector('input[name="cadastro_type"]:checked').value;
  fillCategories(typeKey, true);
  // unitOnly fields hidden for empreendimento
  const isEmp = typeKey === "empreendimento";
  document.querySelectorAll("[data-unit-only]").forEach((el) => el.classList.toggle("hidden", isEmp));
  document.getElementById("devNameLabel").textContent = isEmp ? "Nome do empreendimento" : "Nome do condomínio";
}
function initCadastroType() {
  document.getElementById("cadastroType").addEventListener("change", applyCadastroType);
  fillCategories("apartamentos");
}

/* ---------- Status → suspension reason ---------- */
function initStatus() {
  const sel = document.getElementById("statusSelect");
  sel.addEventListener("change", () => {
    const norm = sel.value.normalize("NFD").replace(/[\u0300-\u036f]/g, "").trim().toLowerCase();
    document.getElementById("suspensionField").classList.toggle("hidden", norm !== "suspenso");
  });
}

/* ---------- Development → autofill ---------- */
function initDevelopment() {
  const sel = document.getElementById("developmentSelect");
  sel.addEventListener("change", () => {
    const code = sel.value;
    const data = DEVELOPMENTS[code];
    const nameField = document.getElementById("developmentName");
    const notice = document.getElementById("devLinkNotice");
    if (!code || !data) {
      nameField.readOnly = false;
      notice.classList.add("hidden");
      return;
    }
    nameField.value = data.nome;
    nameField.readOnly = true;
    notice.classList.remove("hidden");
    notice.querySelector("span").innerHTML = `Vínculo ativo: <strong>${data.nome}</strong>`;
    setVal("proprietorSelect", data.proprietor);
    setVal("captadorSelect", data.captador);
    setVal("deliveryDate", data.delivery);
    setVal("constructionProfile", data.profile);
    // address (only when blank)
    fillAddress(data.address, true);
  });
}
function setVal(id, v) { const el = document.getElementById(id); if (el && v != null) el.value = v; }
function fillAddress(addr, onlyBlank) {
  const map = { streetType: "streetType", street: "street", number: "streetNumber", uf: "stateSelect", zip: "zipCode", neighborhood: "neighborhood", city: "citySelect" };
  Object.entries(map).forEach(([k, id]) => {
    const el = document.getElementById(id);
    if (!el || addr[k] == null) return;
    if (onlyBlank && String(el.value || "").trim() !== "") return;
    // add option if select doesn't have it
    if (el.tagName === "SELECT" && !Array.from(el.options).some((o) => o.value === addr[k])) el.add(new Option(addr[k], addr[k]));
    el.value = addr[k];
  });
}

/* ---------- CEP search (simulated) ---------- */
function initCep() {
  document.getElementById("cepSearch").addEventListener("click", () => {
    const btn = document.getElementById("cepSearch");
    const orig = btn.innerHTML;
    btn.innerHTML = '<i class="bi bi-arrow-repeat"></i>';
    setTimeout(() => {
      fillAddress(CEP_DB.seed, false);
      btn.innerHTML = '<i class="bi bi-check2"></i>';
      setTimeout(() => (btn.innerHTML = orig), 900);
    }, 600);
  });
}

/* ---------- Rent calculator ---------- */
function parseCurrency(v) { return parseFloat((v || "").replace(/\./g, "").replace(",", ".")) || 0; }
function fmtCurrency(n) { return n.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 }); }
function initRentCalc() {
  const scope = document.querySelector("[data-rent-calc]");
  if (!scope) return;
  const total = document.querySelector('[data-rent="total"]');
  const calc = () => {
    const rent = parseCurrency(scope.querySelector('[data-rent="rent"]').value);
    const condo = parseCurrency(scope.querySelector('[data-rent="condo"]').value);
    const iptu = parseCurrency(scope.querySelector('[data-rent="iptu"]').value);
    total.value = fmtCurrency(rent + condo + iptu);
  };
  scope.querySelectorAll('[data-rent="rent"],[data-rent="condo"],[data-rent="iptu"]').forEach((el) =>
    el.addEventListener("input", calc)
  );
}

/* ---------- Currency & phone masks ---------- */
function initMasks() {
  document.querySelectorAll('[data-mask="currency"]').forEach((el) => {
    el.addEventListener("input", () => {
      let digits = el.value.replace(/\D/g, "");
      if (!digits) { el.value = ""; return; }
      const n = parseInt(digits, 10) / 100;
      el.value = fmtCurrency(n);
    });
  });
  document.querySelectorAll('[data-mask="phone"]').forEach((el) => {
    el.addEventListener("input", () => {
      let d = el.value.replace(/\D/g, "").slice(0, 11);
      if (d.length > 6) el.value = `(${d.slice(0,2)}) ${d.slice(2,7)}-${d.slice(7)}`;
      else if (d.length > 2) el.value = `(${d.slice(0,2)}) ${d.slice(2)}`;
      else el.value = d;
    });
  });
  document.querySelectorAll('[data-mask="cep"]').forEach((el) => {
    el.addEventListener("input", () => {
      let d = el.value.replace(/\D/g, "").slice(0, 8);
      el.value = d.length > 5 ? `${d.slice(0,5)}-${d.slice(5)}` : d;
    });
  });
}

/* ---------- Chip grids (features / infra) ---------- */
const chipData = { featuresGrid: [...FEATURES], infraGrid: [...INFRA] };
const chipSelected = { featuresGrid: new Set(), infraGrid: new Set() };
function renderChipGrid(id) {
  const grid = document.getElementById(id);
  grid.innerHTML = "";
  chipData[id].forEach((item) => {
    const label = document.createElement("label");
    label.className = "chip-card" + (chipSelected[id].has(item) ? " is-checked" : "");
    label.innerHTML = `<input type="checkbox" ${chipSelected[id].has(item) ? "checked" : ""}><span title="${item}">${item}</span>`;
    label.addEventListener("click", (e) => {
      e.preventDefault();
      if (chipSelected[id].has(item)) chipSelected[id].delete(item); else chipSelected[id].add(item);
      renderChipGrid(id);
    });
    grid.appendChild(label);
  });
}

/* ---------- Multiselect ---------- */
class MultiSelect {
  constructor(wrap, opts) {
    this.wrap = wrap; this.options = opts.options || []; this.creatable = opts.creatable || false;
    this.placeholder = opts.placeholder || "Selecione..."; this.selected = []; this.render();
  }
  setOptions(o) { this.options = o; this.render(); }
  render() {
    this.wrap.innerHTML = "";
    const box = document.createElement("div"); box.className = "multiselect";
    this.selected.forEach((item) => {
      const tag = document.createElement("span"); tag.className = "ms-tag"; tag.innerHTML = `<span>${item}</span>`;
      const x = document.createElement("button"); x.type = "button"; x.innerHTML = '<i class="bi bi-x"></i>';
      x.addEventListener("click", (e) => { e.stopPropagation(); this.remove(item); });
      tag.appendChild(x); box.appendChild(tag);
    });
    const input = document.createElement("input"); input.className = "ms-input";
    input.placeholder = this.selected.length ? "" : this.placeholder; this.input = input; box.appendChild(input);
    this.wrap.appendChild(box);
    box.addEventListener("click", () => { input.focus(); this.openMenu(); });
    input.addEventListener("focus", () => this.openMenu());
    input.addEventListener("input", () => this.openMenu());
    input.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && this.creatable && input.value.trim()) { e.preventDefault(); this.add(input.value.trim()); input.value = ""; }
      if (e.key === "Backspace" && !input.value && this.selected.length) this.remove(this.selected[this.selected.length - 1]);
    });
    document.addEventListener("click", (e) => { if (!this.wrap.contains(e.target)) this.closeMenu(); });
  }
  openMenu() {
    this.closeMenu();
    const q = (this.input.value || "").toLowerCase();
    const avail = this.options.filter((o) => !this.selected.includes(o) && o.toLowerCase().includes(q));
    const menu = document.createElement("div"); menu.className = "ms-menu";
    if (!avail.length && !(this.creatable && this.input.value.trim())) {
      const e = document.createElement("div"); e.className = "ms-option is-empty"; e.textContent = "Nenhuma opção"; menu.appendChild(e);
    }
    avail.forEach((o) => {
      const opt = document.createElement("div"); opt.className = "ms-option"; opt.textContent = o;
      opt.addEventListener("click", (e) => { e.stopPropagation(); this.add(o); this.input.value = ""; this.input.focus(); });
      menu.appendChild(opt);
    });
    if (this.creatable && this.input.value.trim() && !avail.includes(this.input.value.trim())) {
      const opt = document.createElement("div"); opt.className = "ms-option"; opt.innerHTML = `<i class="bi bi-plus-lg"></i> Adicionar "${this.input.value.trim()}"`;
      opt.addEventListener("click", (e) => { e.stopPropagation(); this.add(this.input.value.trim()); this.input.value = ""; this.input.focus(); });
      menu.appendChild(opt);
    }
    this.wrap.appendChild(menu); this.menu = menu;
  }
  closeMenu() { if (this.menu) { this.menu.remove(); this.menu = null; } }
  add(item) { if (!this.selected.includes(item)) { this.selected.push(item); this.render(); this.closeMenu(); } }
  remove(item) { this.selected = this.selected.filter((s) => s !== item); this.render(); }
}
const msRegistry = {};

/* ---------- Radio pill groups (portais) ---------- */
function initRadios() {
  document.querySelectorAll("[data-radio]").forEach((row) => {
    row.querySelectorAll(".radio-pill").forEach((pill) => {
      pill.addEventListener("click", () => {
        row.querySelectorAll(".radio-pill").forEach((p) => p.classList.remove("is-active"));
        pill.classList.add("is-active");
      });
    });
  });
}

/* ---------- Modals ---------- */
function initModals() {
  document.querySelectorAll("[data-open-modal]").forEach((b) => b.addEventListener("click", () => document.getElementById(b.dataset.openModal).classList.add("is-open")));
  document.querySelectorAll("[data-close-modal]").forEach((b) => b.addEventListener("click", () => b.closest(".modal-overlay").classList.remove("is-open")));
  document.querySelectorAll(".modal-overlay").forEach((o) => o.addEventListener("click", (e) => { if (e.target === o) o.classList.remove("is-open"); }));
  document.addEventListener("keydown", (e) => { if (e.key === "Escape") document.querySelectorAll(".modal-overlay.is-open").forEach((o) => o.classList.remove("is-open")); });
}

/* ---------- Attribute manager (chip grids + multiselects) ---------- */
let attrCtx = null;
function initAttrManager() {
  document.querySelectorAll("[data-attr-manager]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const title = btn.dataset.attrManager;
      document.getElementById("attrModalTitle").textContent = "Gerenciar " + title;
      if (btn.dataset.target) attrCtx = { kind: "chip", key: btn.dataset.target };
      else if (btn.dataset.multiselectTarget) attrCtx = { kind: "ms", key: btn.dataset.multiselectTarget };
      renderAttrList();
      document.getElementById("attrModal").classList.add("is-open");
    });
  });
  document.getElementById("attrAdd").addEventListener("click", addAttr);
  document.getElementById("attrInput").addEventListener("keydown", (e) => { if (e.key === "Enter") { e.preventDefault(); addAttr(); } });
}
function currentAttrItems() {
  if (attrCtx.kind === "chip") return chipData[attrCtx.key];
  return msRegistry[attrCtx.key].options;
}
function renderAttrList() {
  const list = document.getElementById("attrList");
  list.innerHTML = "";
  currentAttrItems().forEach((item, i) => {
    const li = document.createElement("li"); li.className = "attr-item";
    li.innerHTML = `<span>${item}</span>`;
    const del = document.createElement("button"); del.className = "ax-btn ax-btn--ghost ax-btn--sm ax-text-danger"; del.innerHTML = '<i class="bi bi-trash"></i>';
    del.addEventListener("click", () => { currentAttrItems().splice(i, 1); syncAttr(); renderAttrList(); });
    li.appendChild(del); list.appendChild(li);
  });
}
function addAttr() {
  const input = document.getElementById("attrInput");
  const v = input.value.trim();
  if (!v || currentAttrItems().includes(v)) return;
  currentAttrItems().push(v); input.value = ""; syncAttr(); renderAttrList();
}
function syncAttr() {
  if (attrCtx.kind === "chip") renderChipGrid(attrCtx.key);
  else msRegistry[attrCtx.key].setOptions(msRegistry[attrCtx.key].options);
}

/* ---------- Save button ---------- */
document.getElementById("saveBtn").addEventListener("click", () => {
  const btn = document.getElementById("saveBtn");
  const orig = btn.innerHTML;
  btn.innerHTML = '<i class="bi bi-check-circle"></i><span>Salvo ✓</span>';
  setTimeout(() => (btn.innerHTML = orig), 1600);
});

/* ---------- Boot ---------- */
document.addEventListener("DOMContentLoaded", () => {
  buildTabs();
  initToggles();
  initSections();
  initCadastroType();
  applyCadastroType();
  initStatus();
  initDevelopment();
  initCep();
  initRentCalc();
  initMasks();
  initRadios();
  initModals();
  renderChipGrid("featuresGrid");
  renderChipGrid("infraGrid");
  msRegistry.imediacoes = new MultiSelect(document.querySelector('[data-multiselect="imediacoes"]'), { options: ["Próximo ao metrô", "Perto de escola", "Área comercial", "Praça", "Parque"], creatable: true, placeholder: "Selecione ou digite..." });
  msRegistry.badges = new MultiSelect(document.querySelector('[data-multiselect="badges"]'), { options: [...BADGES], placeholder: "Selecione..." });
  msRegistry.keywords = new MultiSelect(document.querySelector('[data-multiselect="keywords"]'), { creatable: true, placeholder: "Digite e Enter..." });
  initAttrManager();
});
