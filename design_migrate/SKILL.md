---
name: unitymob-design
description: Use this skill to generate well-branded interfaces and assets for Unitymob — a white-label real-estate CRM for Brazilian imobiliárias, either for production or throwaway prototypes/mocks. Contains essential design guidelines, colors, type, fonts, assets, and admin-CRM UI kit components for prototyping.
user-invocable: true
---

Read the `readme.md` file within this skill, and explore the other available files.

If creating visual artifacts (slides, mocks, throwaway prototypes, etc), copy assets out and create static HTML files for the user to view. If working on production code, you can copy assets and read the rules here to become an expert in designing with this brand.

If the user invokes this skill without any other guidance, ask them what they want to build or design, ask some questions, and act as an expert designer who outputs HTML artifacts _or_ production code, depending on the need.

## Fast facts
- **Product:** Unitymob — dense, corporate real-estate CRM (`/admin`) + field-agent PWA. Language is **Brazilian Portuguese (pt-BR)**.
- **Entry point:** link `styles.css` (a manifest of `@import`s). It pulls in all tokens, fonts (Inter, Outfit, Bootstrap Icons via CDN) and the `.ax-*` component classes.
- **Primary:** white-label, default `#365f8f`. Ink/surfaces are cool neutral greys; workspace bg `#eef2f7`, panels white.
- **Type:** Inter (13px base UI), Outfit for display. Compact, heavy weights, tabular numerals.
- **Icons:** Bootstrap Icons only — `<i class="bi bi-name">`. No emoji in the chrome.
- **Feel:** utilitarian, hairline borders, near-flat cards, small radii (5–12px), fast functional motion. Do not loosen the density or add gradients/decoration in the admin.

## What's here
- `tokens/` — colors, typography, spacing/radii/elevation/motion, base, and the shipped `.ax-*` component CSS.
- `components/` — React primitives, reachable at `window.UnitymobDesignSystem_2a309d.<Name>` after loading `_ds_bundle.js` (Button, Badge, MetricCard, NavLink, ContextPin, LeadLabelChip, Alert, Menu, form controls, …).
- `ui_kits/admin-crm/` — an interactive recreation of the admin shell and four core workspaces (Dashboard, Imóveis, Leads kanban, WhatsApp inbox). Best reference for full screens.
- `guidelines/` — foundation specimen cards. `assets/` — logos & images.

Copy assets you reference into your artifact; do not hot-link into this skill folder.
