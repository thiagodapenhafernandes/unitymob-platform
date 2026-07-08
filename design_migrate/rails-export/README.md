# Mapa de refinamento — Design System → codebase `unitymob-crm`

> **Leia isto antes de "migrar" qualquer coisa.** Seu app **já consome o design
> system de forma nativa**. Não existe migração de componente a fazer — existe
> **aplicar refinamentos** nos lugares certos. Este doc diz onde é cada lugar.

## O que seu app já tem (não recrie)

| Camada | Onde vive no `unitymob-crm` |
|---|---|
| **Estilos `.ax-*`** (fonte) | `app/assets/stylesheets/admin_tailwind.css` — 24k linhas, CSS puro + Tailwind, **white-label** via `--admin-primary` + `color-mix`. |
| **Estilos `.ax-*`** (build) | `app/assets/builds/admin_tailwind.css` — gerado; **nunca edite à mão**. |
| **Helpers de marcação** | `app/helpers/admin/ui_helper.rb` — ~60 helpers `ax_*` (`ax_button`, `ax_badge`, `ax_metric_card`, `ax_field`, `ax_switch_field`, `ax_empty_state`, …). |
| **Partials dos helpers** | `app/views/admin/shared/ui/_*.html.erb` (`_badge`, `_metric_card`, `_field`, `_switch_field`, …). |
| **Ícones** | Bootstrap Icons já via `<link>` no `app/views/layouts/admin.html.erb`. |
| **Tema por tenant** | `<style>` no `<head>` do layout injeta `--admin-primary`, `--admin-surface`, etc. de `LayoutSetting`. |

> ⛔ **Não instale o `rails-export/unitymob-ds.css` no app.** Ele fixa `#365f8f` e
> redefine `.ax-*`, o que **quebraria o white-label**. Aquele arquivo serve só pra
> **mocks/protótipos estáticos** fora do Rails (ver seção final).

---

## Onde aplicar um refinamento (o mapa)

Um refinamento vindo do design system cai em **1 de 3 lugares**. Decida pelo tipo:

### A. Mudou a APARÊNCIA (cor, borda, espaçamento, sombra, tamanho)
→ edite o bloco `.ax-*` correspondente na **fonte** `admin_tailwind.css`, depois
**recompile** (ver abaixo). Linhas atuais dos blocos principais:

| Componente (DS) | Bloco na fonte `admin_tailwind.css` |
|---|---|
| `Button` / `IconButton` | `.ax-btn` — **linha ~114** (+ `.ax-btn--primary/ghost/danger/…`) |
| `Card` | `.ax-card` — **linha ~205** |
| `MetricCard` | `.ax-stat-value` / `.ax-stat-label` — **linha ~211** |
| tabela | `.ax-table` — **linha ~268** |
| `Badge` | `.ax-badge` — **linha ~288** |
| `Input`/`Select`/`Textarea`/`SearchInput` | `.ax-input, .ax-select, .ax-textarea` — **linha ~300** |
| `Alert` | `.ax-alert` — **linha ~312** |
| `Switch` | `.ax-switch` — **linha ~380** |
| `EmptyState` | `.ax-empty` — **linha ~550** |
| `Menu` | `.ax-menu` — **linha ~590** |
| `LeadLabelChip` | `.lead-label-chip` — **linha ~709** |
| `ContextPin` | `.ax-context-pin` — **linha ~845** |
| `NavLink` | `.ax-nav__link` — **linha ~3852** |

### B. Mudou a ESTRUTURA / marcação (novo slot, atributo, ordem de elementos)
→ edite o **helper** em `app/helpers/admin/ui_helper.rb` e/ou o **partial** em
`app/views/admin/shared/ui/`. Mapa DS → helper:

| Componente (DS) | Helper (`Admin::UiHelper`) | Partial |
|---|---|---|
| `Button` | `ax_button(label, url=nil, variant:, size:, icon:)` | inline (`button_tag`/`link_to`) |
| `IconButton` | `ax_icon_button(label:, icon:, url:)` | via `ax_button` |
| `Badge` | `ax_badge(label, tone:, dot:)` | `_badge` |
| `MetricCard` | `ax_metric_card(label:, value:, badge:, hint:, progress:)` | `_metric_card` |
| `Field` | `ax_field(label:, hint:, error:)` + `ax_text_field` / `ax_select_field` / … | `_field`, `_text_field`, … |
| `Switch` | `ax_switch_field(label:, form:, method:, checked:)` | `_switch_field` |
| `EmptyState` | `ax_empty_state(title:, description:, icon:, action:)` | `_empty_state` |
| `Alert` | `ax_inline_notice(tone:, icon:)` | `_inline_notice` |
| ícone | `ax_icon(name)` → `<i class="bi bi-name">` | inline |

> ⚠️ **Assinaturas diferem do design system React.** O `ax_button` do app é
> `ax_button(label, url, variant: :secondary, …)` — `url` é **posicional** e a
> variante padrão é `:secondary` (não `:default`). Sempre confira a assinatura
> real no helper antes de aplicar.

### C. Mudou um TOKEN de cor/tipografia/espaçamento
→ **não** troque hex solto. Ajuste o token. Cuidado com a diferença de nomes:

| Token no design system (este projeto) | Equivalente no app | Observação |
|---|---|---|
| `--primary` `#365f8f` | `--admin-primary` | **White-label** — injetado por tenant no `<head>`. Não fixe hex. |
| `--primary-hover` | `--admin-primary-hover` | app deriva com `color-mix(... 86%, #000)`. |
| `--primary-soft` / `--primary-softer` | `--admin-primary-soft` / `--admin-primary-softer` | derivados por `color-mix`. |
| `--primary-ring` | `--admin-primary-ring` | idem. |
| `--surface` / `--surface-header` / `--workspace-bg` | `--admin-surface` / `--admin-surface-header` / `--admin-workspace-bg` | injetados por tenant. |
| `--ink` | `--admin-ink` | injetado por tenant. |
| bordas/campos (`--line`, `--field-border`) | `--ab-line`, `--ax-field-border` | derivados de `--admin-ink`/`--admin-surface`. |
| entidade (`--entity-property`…) | hex fixos no `.ax-context-pin--*` | ok manter literal (`#ff7043`, `#128c7e`…). |

**Regra:** valores derivados da primária **nunca** são hardcoded no app — são
`color-mix` sobre `--admin-primary`. Se o refinamento muda um desses, mude a
**fórmula do `color-mix`**, não um hex.

---

## Recompilar o CSS depois de editar `admin_tailwind.css`

O `Procfile.dev` roda `bin/rails dartsass:watch` (site público, SCSS). O
`admin_tailwind.css` é buildado pelo **tailwindcss-rails** com
`config/admin_tailwind.config.js`. Rode o build do Tailwind admin (o comando exato
depende dos seus rake tasks / `bin/dev`; procure o task que gera
`app/assets/builds/admin_tailwind.css`) e confirme que o build foi atualizado
antes de commitar. **Só edite a fonte, nunca o `builds/`.**

---

## Checklist por refinamento

1. Classificar: é **A** (aparência), **B** (marcação) ou **C** (token)?
2. Editar **só** o lugar do mapa. Não misturar as três numa mudança só.
3. Se mexeu no CSS fonte → **recompilar** o `admin_tailwind`.
4. Preservar 100% de `data-controller` / `data-*-target` / `data-action` (Stimulus).
5. Testar com **mais de um tenant** (ou trocar `--admin-primary`) pra garantir que
   o white-label não quebrou.

---

## `unitymob-ds.css` + `preview.html` — só pra mocks

O arquivo achatado `rails-export/unitymob-ds.css` (e o `preview.html`) existem pra
você montar **protótipos/mocks estáticos em HTML** fora do Rails — apresentações,
telas de proposta, testes rápidos de layout. Ali o white-label não importa e um
arquivo único é conveniente. **No app de produção, ignore-o** e use o
`admin_tailwind.css` + `Admin::UiHelper` que já existem.
