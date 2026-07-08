/* ============================================================
   Redesign — Nova regra de distribuição — dinâmicas simuladas
   Vanilla JS reproducing the Stimulus behaviors of the real screen:
   distribution-rule, team-rules, meta-rules, ax-aside, ax-modal.
   ============================================================ */

/* ---------- Fake data (stands in for @all_agents, @meta_structure, Store.active) ---------- */
const AGENTS = [
  { id: 1, name: "Ana Beatriz Souza", email: "ana.souza@imob.com" },
  { id: 2, name: "Carlos Mendes", email: "carlos.mendes@imob.com" },
  { id: 3, name: "Débora Lima", email: "debora.lima@imob.com" },
  { id: 4, name: "Eduardo Rocha", email: "eduardo.rocha@imob.com" },
  { id: 5, name: "Fernanda Alves", email: "fernanda.alves@imob.com" },
  { id: 6, name: "Gustavo Pereira", email: "gustavo.pereira@imob.com" },
];

const META_PAGES = [
  { id: "p1", name: "Imobiliária Zona Sul" },
  { id: "p2", name: "Lançamentos Premium" },
  { id: "p3", name: "Aluguel Rápido" },
];
const META_FORMS = {
  p1: [{ id: "f1", name: "Formulário — Apartamentos" }, { id: "f2", name: "Formulário — Casas" }],
  p2: [{ id: "f3", name: "Interesse — Lançamento Marina" }, { id: "f4", name: "VIP — Cobertura" }],
  p3: [{ id: "f5", name: "Locação — 2 quartos" }],
};
const STORES = [
  { id: "s1", name: "Loja Centro" },
  { id: "s2", name: "Loja Zona Sul" },
  { id: "s3", name: "Loja Norte" },
];

const DAY_LABELS = { mon: "Segunda", tue: "Terça", wed: "Quarta", thu: "Quinta", fri: "Sexta", sat: "Sábado", sun: "Domingo" };

/* ============================================================
   Toggle chips — reflect checkbox state + optional section control
   ============================================================ */
function initToggles() {
  document.querySelectorAll("[data-toggle]").forEach((chip) => {
    const input = chip.querySelector('input[type="checkbox"]');
    const sync = () => chip.classList.toggle("is-checked", input.checked);
    sync();
    chip.addEventListener("click", (e) => {
      if (e.target.closest("a")) return;
      e.preventDefault();
      if (chip.classList.contains("is-disabled")) return;

      // Channel guard: block activating an unconfigured channel
      if (chip.dataset.channel && chip.dataset.configured === "false" && !input.checked) {
        openChannelModal(chip);
        return;
      }

      input.checked = !input.checked;
      sync();

      // Controls a collapsible section
      const target = chip.dataset.controls;
      if (target) {
        const el = document.getElementById(target);
        if (el) el.classList.toggle("hidden", !input.checked);
      }
      // Meta "Conectado" badge
      if (chip.dataset.summary === "meta") {
        document.getElementById("metaBadge").classList.toggle("hidden", !input.checked);
      }
      // Clear webhook error when re-enabling
      if (chip.dataset.controls === "notifyWebhookSection" && input.checked) {
        document.getElementById("notifyWebhookError").classList.add("hidden");
      }
      updateSummary();
    });
  });
}

/* ============================================================
   Multiselect (tom-select simulation)
   ============================================================ */
class MultiSelect {
  constructor(wrap, opts) {
    this.wrap = wrap;
    this.options = opts.options || [];
    this.creatable = opts.creatable || false;
    this.placeholder = opts.placeholder || "Selecione...";
    this.onChange = opts.onChange || (() => {});
    this.selected = [];
    this.render();
    this.menuOpen = false;
  }
  setOptions(options) {
    this.options = options;
    // drop selected no longer valid
    this.selected = this.selected.filter((s) => options.find((o) => o.id === s.id) || this.creatable);
    this.render();
    this.onChange(this.selected);
  }
  render() {
    this.wrap.innerHTML = "";
    const box = document.createElement("div");
    box.className = "multiselect";
    this.selected.forEach((item) => {
      const tag = document.createElement("span");
      tag.className = "ms-tag";
      tag.innerHTML = `<span>${item.name}</span>`;
      const x = document.createElement("button");
      x.type = "button";
      x.innerHTML = '<i class="bi bi-x"></i>';
      x.addEventListener("click", (e) => { e.stopPropagation(); this.remove(item.id); });
      tag.appendChild(x);
      box.appendChild(tag);
    });
    const input = document.createElement("input");
    input.className = "ms-input";
    input.placeholder = this.selected.length ? "" : this.placeholder;
    this.input = input;
    box.appendChild(input);
    this.wrap.appendChild(box);

    box.addEventListener("click", () => { input.focus(); this.openMenu(); });
    input.addEventListener("focus", () => this.openMenu());
    input.addEventListener("input", () => this.openMenu());
    input.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && this.creatable && input.value.trim()) {
        e.preventDefault();
        this.add({ id: input.value.trim(), name: input.value.trim() });
        input.value = "";
      }
      if (e.key === "Backspace" && !input.value && this.selected.length) {
        this.remove(this.selected[this.selected.length - 1].id);
      }
    });
    document.addEventListener("click", (e) => {
      if (!this.wrap.contains(e.target)) this.closeMenu();
    });
  }
  openMenu() {
    this.closeMenu();
    const q = (this.input.value || "").toLowerCase();
    const avail = this.options.filter((o) => !this.selected.find((s) => s.id === o.id) && o.name.toLowerCase().includes(q));
    const menu = document.createElement("div");
    menu.className = "ms-menu";
    if (!avail.length && !(this.creatable && this.input.value.trim())) {
      const empty = document.createElement("div");
      empty.className = "ms-option is-empty";
      empty.textContent = this.options.length ? "Nenhuma opção" : "Selecione uma página primeiro";
      menu.appendChild(empty);
    }
    avail.forEach((o) => {
      const opt = document.createElement("div");
      opt.className = "ms-option";
      opt.textContent = o.name;
      opt.addEventListener("click", (e) => { e.stopPropagation(); this.add(o); this.input.value = ""; this.input.focus(); });
      menu.appendChild(opt);
    });
    if (this.creatable && this.input.value.trim() && !avail.find((o) => o.name === this.input.value.trim())) {
      const opt = document.createElement("div");
      opt.className = "ms-option";
      opt.innerHTML = `<i class="bi bi-plus-lg"></i> Adicionar "${this.input.value.trim()}"`;
      opt.addEventListener("click", (e) => { e.stopPropagation(); this.add({ id: this.input.value.trim(), name: this.input.value.trim() }); this.input.value = ""; this.input.focus(); });
      menu.appendChild(opt);
    }
    this.wrap.appendChild(menu);
    this.menu = menu;
  }
  closeMenu() { if (this.menu) { this.menu.remove(); this.menu = null; } }
  add(item) {
    if (this.selected.find((s) => s.id === item.id)) return;
    this.selected.push(item);
    this.render();
    this.closeMenu();
    this.onChange(this.selected);
  }
  remove(id) {
    this.selected = this.selected.filter((s) => s.id !== id);
    this.render();
    this.onChange(this.selected);
  }
}

/* ============================================================
   Team queue — add/remove/reorder agents, mode-driven fields
   ============================================================ */
const AgentQueue = {
  items: [], // {id, name, email, weight, el}
  listEl: null,
  init() {
    this.listEl = document.getElementById("agentList");
  },
  sync() {
    const list = this.listEl;
    list.innerHTML = "";
    if (!this.items.length) {
      list.classList.add("is-empty");
      const empty = document.createElement("div");
      empty.className = "agent-empty";
      empty.textContent = "Nenhum corretor na fila. Adicione acima para montar a distribuição.";
      list.appendChild(empty);
    } else {
      list.classList.remove("is-empty");
      this.items.forEach((it, idx) => list.appendChild(this.row(it, idx)));
    }
    document.getElementById("agentCount").textContent = this.items.length;
    applyMode(currentMode());
    updateSummary();
  },
  row(it, idx) {
    const initial = it.name.trim().charAt(0).toUpperCase();
    const row = document.createElement("div");
    row.className = "agent-item";
    row.draggable = true;
    row.dataset.id = it.id;
    row.innerHTML = `
      <span class="agent__handle" title="Arrastar para reordenar"><i class="bi bi-grip-vertical"></i></span>
      <span class="agent__avatar">${initial}</span>
      <div class="agent__main"><strong>${it.name}</strong><span>${it.email}</span></div>
      <div class="agent__actions">
        <div class="performance-field agent__weight hidden">
          <div class="input-group">
            <span class="input-group__affix">Ciclos</span>
            <input type="number" min="1" value="${it.weight || 1}" class="ax-control ax-control--sm">
          </div>
        </div>
        <div class="rotary-field hidden"><span class="badge-pos">#${idx + 1}</span></div>
        <button type="button" class="ax-ico-btn" title="Remover"><i class="bi bi-trash"></i></button>
      </div>`;
    row.querySelector(".ax-ico-btn").addEventListener("click", () => this.remove(it.id));
    row.querySelector('input[type="number"]')?.addEventListener("input", (e) => { it.weight = parseInt(e.target.value) || 1; });
    this.wireDrag(row);
    return row;
  },
  wireDrag(row) {
    row.addEventListener("dragstart", (e) => { row.classList.add("dragging"); e.dataTransfer.effectAllowed = "move"; });
    row.addEventListener("dragend", () => { row.classList.remove("dragging"); this.readOrder(); });
    row.addEventListener("dragover", (e) => {
      e.preventDefault();
      const dragging = this.listEl.querySelector(".dragging");
      if (!dragging || dragging === row) return;
      const rect = row.getBoundingClientRect();
      const after = e.clientY > rect.top + rect.height / 2;
      this.listEl.insertBefore(dragging, after ? row.nextSibling : row);
    });
  },
  readOrder() {
    const ids = [...this.listEl.querySelectorAll(".agent-item")].map((r) => r.dataset.id);
    this.items.sort((a, b) => ids.indexOf(String(a.id)) - ids.indexOf(String(b.id)));
    this.sync();
  },
  setFromSelection(selected) {
    // preserve existing (weights/order), add new, drop removed
    const keep = this.items.filter((it) => selected.find((s) => String(s.id) === String(it.id)));
    selected.forEach((s) => {
      if (!keep.find((it) => String(it.id) === String(s.id))) {
        keep.push({ id: s.id, name: s.name, email: s.email || "", weight: 1 });
      }
    });
    this.items = keep;
    this.sync();
  },
  remove(id) {
    this.items = this.items.filter((it) => String(it.id) !== String(id));
    // reflect back in the select
    agentSelect.selected = agentSelect.selected.filter((s) => String(s.id) !== String(id));
    agentSelect.render();
    this.sync();
  },
};

/* ============================================================
   Distribution mode
   ============================================================ */
function currentMode() {
  return document.querySelector('input[name="mode"]:checked')?.value || "rotary";
}
function applyMode(mode) {
  document.querySelectorAll(".performance-field").forEach((el) => el.classList.toggle("hidden", mode !== "performance"));
  document.querySelectorAll(".rotary-field").forEach((el) => el.classList.toggle("hidden", mode !== "rotary"));
}
function initModes() {
  document.querySelectorAll(".mode-card").forEach((card) => {
    card.addEventListener("click", (e) => {
      if (e.target.closest(".mode-info")) return;
      const input = card.querySelector("input");
      input.checked = true;
      document.querySelectorAll(".mode-card").forEach((c) => c.classList.toggle("is-selected", c === card));
      applyMode(input.value);
      updateSummary();
    });
  });
}

/* ============================================================
   Modals + channel guard
   ============================================================ */
function openModal(id) { document.getElementById(id)?.classList.add("is-open"); }
function closeModal(el) { el.closest(".modal-overlay")?.classList.remove("is-open"); }
function openChannelModal(chip) {
  document.getElementById("channelModalName").textContent = chip.dataset.channelLabel || "este canal";
  document.getElementById("channelModalInstructions").textContent = chip.dataset.configInstructions || "";
  document.getElementById("channelModalLink").href = chip.dataset.configPath || "#";
  openModal("channelModal");
}
function initModals() {
  document.querySelectorAll("[data-open-modal]").forEach((b) => b.addEventListener("click", () => openModal(b.dataset.openModal)));
  document.querySelectorAll("[data-close-modal]").forEach((b) => b.addEventListener("click", () => closeModal(b)));
  document.querySelectorAll(".modal-overlay").forEach((o) => o.addEventListener("click", (e) => { if (e.target === o) o.classList.remove("is-open"); }));
  document.addEventListener("keydown", (e) => { if (e.key === "Escape") document.querySelectorAll(".modal-overlay.is-open").forEach((o) => o.classList.remove("is-open")); });
}

/* ============================================================
   Aside collapse
   ============================================================ */
function initAside() {
  document.querySelectorAll("[data-aside-toggle]").forEach((b) =>
    b.addEventListener("click", () => document.getElementById("workspace").classList.toggle("aside-collapsed"))
  );
}

/* ============================================================
   Submit validation (channel guard + webhook URL required)
   ============================================================ */
function initSubmit() {
  document.getElementById("saveBtn").addEventListener("click", () => {
    // guarded channels
    for (const chip of document.querySelectorAll("[data-channel]")) {
      const input = chip.querySelector("input");
      if (input.checked && chip.dataset.configured !== "true") { openChannelModal(chip); return; }
    }
    // webhook URLs required
    const webhookChip = [...document.querySelectorAll("[data-controls='notifyWebhookSection']")][0];
    const webhookOn = webhookChip?.querySelector("input").checked;
    if (webhookOn && notifyUrlsSelect.selected.length === 0) {
      document.getElementById("notifyWebhookSection").classList.remove("hidden");
      document.getElementById("notifyWebhookError").classList.remove("hidden");
      document.getElementById("notifyWebhookError").scrollIntoView({ behavior: "smooth", block: "center" });
      return;
    }
    // success feedback (demo)
    const btn = document.getElementById("saveBtn");
    const orig = btn.innerHTML;
    btn.innerHTML = '<i class="bi bi-check-circle"></i><span>Regra válida ✓</span>';
    setTimeout(() => (btn.innerHTML = orig), 1600);
  });
}

/* ============================================================
   Schedule table
   ============================================================ */
function initSchedule() {
  const body = document.getElementById("scheduleBody");
  Object.entries(DAY_LABELS).forEach(([day, label]) => {
    const weekend = day === "sat" || day === "sun";
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td class="day">${label}</td>
      <td class="num"><input type="checkbox" ${weekend ? "" : "checked"}></td>
      <td><input type="time" value="09:00" class="ax-control ax-control--sm"></td>
      <td><input type="time" value="18:00" class="ax-control ax-control--sm"></td>`;
    body.appendChild(tr);
  });
}

/* ============================================================
   Live summary (product-grade improvement)
   ============================================================ */
let agentSelect, notifyUrlsSelect;
function updateSummary() {
  const modeLabels = { rotary: "fila rotativa", performance: "sorteio por performance", shark_tank: "shark tank (primeiro a aceitar)" };
  const sources = [];
  if (isOn("meta")) sources.push("Meta Ads");
  if (isOn("webhook")) sources.push("Webhooks");
  if (isOn("site")) sources.push("Site");
  if (isOn("portal")) sources.push("Portais");

  const n = AgentQueue.items.length;
  const line = document.getElementById("summaryLine");
  const srcTxt = sources.length ? `<b>${sources.join(", ")}</b>` : "<b>nenhuma origem</b>";
  const agentTxt = n ? `<b>${n} corretor${n > 1 ? "es" : ""}</b>` : "<b>sem corretores</b>";
  line.innerHTML = `Leads de ${srcTxt} → ${agentTxt} em <b>${modeLabels[currentMode()]}</b>.`;

  const chips = document.getElementById("summaryChips");
  chips.innerHTML = "";
  const addChip = (icon, txt, on = true) => {
    const c = document.createElement("span");
    c.className = "summary-chip" + (on ? "" : " off");
    c.innerHTML = `<i class="bi bi-${icon}"></i> ${txt}`;
    chips.appendChild(c);
  };
  addChip("whatsapp", "WhatsApp", isChannelOn("whatsapp"));
  addChip("clock-history", isOn("represamento") ? "Bolsão ativo" : "Sem bolsão", isOn("represamento"));
  addChip("hourglass-split", isOn("pocket") ? "Pocket" : "Sem tempo limite", isOn("pocket"));
}
function isOn(summary) {
  if (summary === "represamento") return !document.getElementById("represamentoSection").classList.contains("hidden");
  if (summary === "pocket") return !document.getElementById("pocketSection").classList.contains("hidden");
  const chip = document.querySelector(`[data-summary="${summary}"]`);
  return chip ? chip.querySelector("input").checked : false;
}
function isChannelOn(ch) {
  const chip = document.querySelector(`[data-channel="${ch}"]`);
  return chip ? chip.querySelector("input").checked : false;
}

/* ============================================================
   Boot
   ============================================================ */
document.addEventListener("DOMContentLoaded", () => {
  initToggles();
  initModes();
  initModals();
  initAside();
  initSchedule();
  initSubmit();
  AgentQueue.init();

  // Multiselects
  new MultiSelect(document.querySelector('[data-multiselect="tags"]'), { creatable: true, placeholder: "Digite uma tag e tecle Enter", onChange: updateSummary });
  new MultiSelect(document.querySelector('[data-multiselect="stores"]'), { options: STORES, placeholder: "Selecione lojas (vazio = todas)" });
  notifyUrlsSelect = new MultiSelect(document.querySelector('[data-multiselect="notifyUrls"]'), { creatable: true, placeholder: "https://... e Enter" });

  // Meta pages → forms dependency
  const formsSelect = new MultiSelect(document.querySelector('[data-multiselect="forms"]'), { options: [], placeholder: "Selecione uma página primeiro", onChange: (sel) => {
    const label = document.getElementById("formCount");
    label.innerHTML = sel.length ? `<strong>${sel.length}</strong> formulário${sel.length > 1 ? "s" : ""} selecionado${sel.length > 1 ? "s" : ""}` : "Nenhum formulário selecionado";
  }});
  new MultiSelect(document.querySelector('[data-multiselect="pages"]'), { options: META_PAGES, placeholder: "Selecione páginas Meta", onChange: (sel) => {
    const forms = sel.flatMap((p) => META_FORMS[p.id] || []);
    formsSelect.setOptions(forms);
    document.getElementById("formCount").innerHTML = forms.length ? "Nenhum formulário selecionado" : "Selecione uma página primeiro";
  }});

  // Agents → queue
  agentSelect = new MultiSelect(document.querySelector('[data-multiselect="agents"]'), { options: AGENTS.map((a) => ({ id: a.id, name: a.name, email: a.email })), placeholder: "Buscar corretor...", onChange: (sel) => AgentQueue.setFromSelection(sel) });

  updateSummary();
});
