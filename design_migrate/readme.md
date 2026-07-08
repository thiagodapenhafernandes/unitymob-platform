# Unitymob Design System

The design system for **Unitymob** — a white-label, multi-tenant **real-estate CRM** built for Brazilian *imobiliárias* (real-estate agencies). It is tenant-neutral: the platform default primary is shown everywhere and real tenants override the brand at runtime (`--admin-primary`).

The product has two surfaces:
1. **Admin CRM** (`/admin`) — the core product and the focus of this system. A dense, corporate, "Power BI-grade" operational tool: dashboard cockpit, property catalog (*Imóveis*/*Habitations*), lead funnel (kanban), WhatsApp inbox, captações (property sourcing), distribution rules, marketing, field check-ins, integrations. Design language is the `.ax-*` component layer. UI font **Inter** (+ **Outfit** for display), **Bootstrap Icons**, cool neutral greys, single white-label primary.
2. **Field PWA** (`/field`) — a mobile app for external agents doing geolocated check-ins.

Everything below is derived from the actual product source, not invented.

## Sources
- **Codebase:** `unitymob-crm/` — a Ruby on Rails app (mounted read-only during authoring).
  - Admin design system: `app/assets/stylesheets/admin_tailwind.css` (the `.ax-*` layer), `config/admin_tailwind.config.js`, `app/views/layouts/admin.html.erb`, `app/views/admin/shared/_sidebar.html.erb`.
  - In-repo reference DS pages: `public/design-system/index.html`, `public/analytics-builder-design-system/`.
- **Brand assets:** `public/icon.png` — the Unitymob mark (copied into `assets/`).

> The reader is not assumed to have the codebase; paths are recorded for anyone who does.

---

## CONTENT FUNDAMENTALS

**Language.** Everything is **Brazilian Portuguese (pt-BR)**. Write UI copy in pt-BR. Numbers use pt-BR formatting: `R$ 1.284.000`, `68 m²`, `1.284` (dot thousands).

**Voice.** Operational, direct, professional — a tool for working agents and managers, not a marketing site. Short labels, imperative buttons: *Novo imóvel*, *Sincronizar*, *Exportar*, *Agendar visita*, *Publicar*, *Sair*. Section eyebrows are single nouns in UPPERCASE: *COCKPIT OPERACIONAL*, *FUNIL*, *CATÁLOGO*, *AQUISIÇÃO*.

**Person.** The system addresses the user by first name and time of day: *"Boa tarde, Marina"*. Otherwise it is impersonal/systemic — feature names, not "you"/"we".

**Casing.** Sentence case for body and most titles; UPPERCASE only for micro eyebrows, table headers and stat labels (with wide letter-spacing). Never all-caps a full sentence.

**Domain vocabulary (use these exact terms):**
- *Imóvel / Imóveis* — property/properties (a.k.a. *Habitation* in code). *Empreendimento* — development.
- *Lead*, *Funil de Leads* — sales funnel. *Proprietário* — property owner. *Corretor* — broker/agent. *Loja* — branch/store.
- *Captação* — property sourcing/listing intake. *Proposta* — offer. *Distribuição de Leads* — lead routing. *Atendimento* — (customer) servicing, esp. WhatsApp.
- Status words: *Publicado, Em revisão, Rascunho, Novo, Represado, Erro de sync*.

**Emoji.** Not used in the admin UI. (They appear only inside user-generated WhatsApp message content.) Do not decorate the CRM with emoji.

**Tone examples (verbatim from product):**
- Greeting subtitle: *"Campo ativo: 3 check-ins agora, 128 leads hoje."*
- Empty/paused module: *"Módulo Campo desativado — Ative somente quando a operação externa estiver em uso."*
- KPI hints: *"86 destaques · 12 empreendimentos"*, *"9 represados · 22 novos"*.

---

## VISUAL FOUNDATIONS

**Density & compaction (core principle — applies to everything).** The system is **spreadsheet-dense** — think **Excel Web / Google Sheets**: maximize useful information per screen, minimize chrome and whitespace. Prefer tight rows, compact controls, thin dividers and multi-column grids over airy, card-heavy, generously-padded layouts. Rows and cells are short (dense tables ~30–34px rows, ~6px vertical cell padding); forms pack fields into 12-column grids at tight gaps; labels are small; a screen should feel like a working grid, not a landing page. When in doubt, **compact it** — reduce padding, shrink gaps, tighten line-height, put more per row — never add breathing room for its own sake. This is a hard default for every new screen, component, table and form built for this system.

**Overall vibe.** Utilitarian, high-density, corporate. Think Power BI / an internal ops console / a spreadsheet: white panels on a cool grey workspace, hairline borders, near-flat elevation, one restrained accent color. Zero decoration for decoration's sake.

**Color.**
- A single **white-label primary** (`--primary`, default `#365f8f` — a desaturated corporate blue). In production it is injected per tenant (`--admin-primary`); everything primary-tinted derives from it via `color-mix`.
- **Cool neutral ink ramp** (`#1f2733 → #98a2b3`) and **cool surfaces** (`#ffffff`, `#f7f8fa`, `#eef2f7`). The workspace background is `#eef2f7`; panels are pure white.
- **Semantic status** pairs (bg + text) for green/amber/red/blue/purple/cyan, surfaced as badges and buttons.
- **Fixed entity accents** — every core object owns one accent used on left-border pins & kanban: Imóvel `#ff7043`, Proprietário `#365f8f`, Lead `#16a34a`, Proposta `#7c3aed`, WhatsApp `#128c7e`.
- Imagery is sparse (it's a data tool); property thumbnails are the main imagery, rendered in neutral frames.

**Type.** **Inter** for all UI (13px base), **Outfit** available for display. Compact scale (10 → 22px). Weights run heavy for a UI (`620` nav, `750` buttons, `800` headings/eyebrows). Tight tracking on headings (`-.01em`); wide caps tracking (`.055em`) on eyebrows. Tabular numerals for all metrics. Mono for codes/IDs (`COD-84213`).

**Spacing & layout.** Fixed 3-zone shell: **48px navbar / 40px context bar / 236px sidebar**, `12px` gutter. Off-grid, intentionally tight numbers (5px, 12.5px, 30px, 34px) — copy them exactly, never snap to a 4/8 grid. Controls are **30px** (buttons) / **34px** (inputs). **Density is the rule** (see the core principle above): dense tables use ~30–34px rows with ~6px cell padding, forms pack into 12-column grids at 10–14px gaps, sections stack at a 12px gutter. Favor compact/`--sm` variants and multi-column layouts; treat generous padding and single-column airy forms as off-brand.

**Borders & radii.** Hairline `1px` borders everywhere (`#e6e8eb` / `#dfe5ee`). Small radii: `5px` nav, `6px` controls, `8px` cards/panels, `10px` modals & kanban cards, `12px` kanban columns, `999px` pills. Cards = white + 1px border + `0 1px 2px` shadow (nearly flat).

**Elevation.** Minimal. `card` (`0 1px 2px /.05`) for panels, `raised` for primary buttons, `card-lift` (`0 8px 22px /.08`) only for kanban cards, `pop` (`0 8px 24px /.12`) for dropdown menus, `modal` for dialogs. No colored glows, no heavy drop shadows.

**Backgrounds.** Flat fills only — no gradients, no textures, no illustrations in the admin.

**Motion.** Fast and functional: `120ms` (fast) / `180ms` / `240ms`, easing `cubic-bezier(.2,.8,.2,1)`. Fades and small translate/scale on menus (`translateY(-4px) scale(.985)` → in). No bounces, no long or looping animation. Honors `prefers-reduced-motion`.

**States.**
- *Hover:* subtle grey fill + border darken (buttons → `#f7f8fa` + `#c4d0df`); nav rows → `#eef3f9`. Primary buttons darken (`color-mix 86% + black`).
- *Focus:* 2–3px primary ring (`0 0 0 2px var(--primary-ring)`) + border shift; never a raw outline.
- *Active/selected:* nav uses a filled tint + `inset 2px 0 0 primary` left bar. Chips/toggles use a `1.5px` inset ring in the label color. Press on chips → `scale(.97)`.
- *Disabled:* `#f5f7fa` fill, `#98a2b3` text, no shadow.

**Transparency & blur.** Used sparingly: the navbar and sticky form-action bars use `backdrop-filter: blur(8–10px)` over a ~92–96% white. Overlays are `rgba(16,24,40,.45)`.

---

## ICONOGRAPHY

- **System:** **Bootstrap Icons 1.11.3**, loaded as a web font from jsDelivr and used via `<i class="bi bi-<name>">`. This is the single, consistent icon system across the entire admin. It ships automatically with this design system (`tokens/fonts.css`).
- **Style:** outline, `1px`-ish stroke, `14–15px` in nav/buttons. Icons are muted grey (`#8490a1`) by default and take the primary color when their row/control is active.
- **Common glyphs:** `speedometer2` (Painel), `houses`/`house-door` (Imóveis), `person-badge` (Leads), `whatsapp`, `person-vcard` (Proprietários), `shop` (Lojas), `journal-plus` (Captações), `diagram-3` (Distribuição), `megaphone` (Marketing), `lightning-charge` (Automação), `buildings` (brand mark), `geo-fill` (check-ins), plus config icons `door-closed / droplet / car-front / arrows-fullscreen` on property rows.
- **No emoji, no unicode-as-icon** in the chrome. Emoji only inside user WhatsApp content.
- **Brand marks (in `assets/logos/`):** the **Unitymob chevron** — a double up-chevron in platform blue: `unitymob-mark.svg`, `unitymob-mark-white.svg` (reversed), `unitymob-appicon.svg` (white chevron on a primary rounded square) and `unitymob-icon.png` (raster). The in-product navbar lockup = the chevron mark in a primary square + the wordmark.
- **Substitutions:** none. Bootstrap Icons is the real set and is linked from its CDN, exactly as production.

---

## INDEX

**Root**
- `styles.css` — the single entry point (import this). Pure `@import` manifest.
- `readme.md` — this guide. `SKILL.md` — agent-skill front matter.

**`tokens/`** (all `@import`ed by `styles.css`)
- `fonts.css` — Inter/Outfit + Bootstrap Icons (CDN).
- `colors.css` — primary, ink, surfaces, lines, semantic status, entity accents.
- `typography.css` — families, size scale, weights, tracking.
- `spacing.css` — spacing, shell dims, control sizing, radii, elevation, motion.
- `base.css` — light reset + `.ax-app` app defaults, page title, eyebrow.
- `components.css` — the shipped `.ax-*` component classes (buttons, badges, cards, table, forms, switch, alert, menu, nav, context pin, lead label, tabs, kanban card, tooltip, empty).

**`components/`** (React primitives — `window.UnitymobDesignSystem_2a309d.<Name>`)
- `actions/` — Button, IconButton
- `forms/` — Field, Input, Select, Textarea, SearchInput, Checkbox, Switch
- `data-display/` — Badge, Card, MetricCard, Avatar, ContextPin, LeadLabelChip
- `feedback/` — Alert, Menu, EmptyState
- `navigation/` — NavLink, Tabs

**`ui_kits/`**
- `admin-crm/` — interactive admin recreation: Dashboard, Imóveis, Leads (kanban), WhatsApp inbox, + shell.

**`guidelines/`** — foundation specimen cards (Colors, Type, Spacing, Brand) shown on the Design System tab.

**`assets/`** — `logos/` (Unitymob mark) and `images/` (admin login bg, hero photo).

---

## Caveats
- The system is centered on the **admin CRM** (the actively-maintained product with a real DS). The Field PWA is represented at the token level only, not as a full UI kit.
- Fonts are loaded from **Google Fonts / jsDelivr CDNs** (Inter, Outfit, Bootstrap Icons) — exactly as production. No local binaries are bundled; a fully offline build would need self-hosted copies.
- The primary shown everywhere is the platform default `#365f8f`; real tenants override it. To re-theme, set `--primary` (and, in a live admin, `--admin-primary`).
