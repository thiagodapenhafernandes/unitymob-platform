# Admin CRM — UI kit

Interactive recreation of the **Unitymob** admin CRM. Reproduces the real `.ax-*` shell and four core workspaces. Composes the design-system components (`Button`, `Badge`, `MetricCard`, `NavLink`, `ContextPin`, `LeadLabelChip`, `SearchInput`, …) from `window.UnitymobDesignSystem_2a309d`.

## Run
Open `index.html`. Click sidebar items to switch workspaces. Four are fully built; the rest render a labelled placeholder.

## Files
- `index.html` — entry; loads `styles.css`, `shell.css`, the DS bundle, React/Babel, then the screens + `App.jsx`.
- `shell.css` — the fixed shell chrome (navbar 48px, context bar 40px, sidebar 236px) + board/panel helpers, copied from production `admin_tailwind.css`.
- `App.jsx` — shell (navbar, context bar with breadcrumb + entity pins, sidebar nav) and the screen router (`window.UM_App`).
- `DashboardScreen.jsx` — operational cockpit: command header, 4 KPI tiles, leads chart, conversion funnel, pendências, top-broker table.
- `LeadsScreen.jsx` — kanban funnel (Novos → Em atendimento → Proposta → Fechado) with draggable-style lead cards.
- `WhatsAppScreen.jsx` — 3-pane atendimento inbox: conversation list, chat thread, entity context panel.
- `ImoveisScreen.jsx` — property catalog: toolbar, quick-filter chips, dense table with status badges & config icons, pagination.

## Fidelity notes
- Language is pt-BR throughout — this is a Brazilian real-estate platform.
- Layout is intentionally **dense** (13px base, 30px controls, 5–6px radii). Do not loosen it.
- Icons are Bootstrap Icons (`bi bi-*`), loaded via the design system's `fonts.css`.
- The primary is the platform default `#365f8f`; in production it is white-labelled per tenant via `--admin-primary`.
