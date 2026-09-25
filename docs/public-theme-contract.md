# Contrato de temas do site público (v1)

> Meta confirmada (2026-09-24): **Opção A** — um HTML canônico, N folhas CSS por
> tema, cada tema não-global amarrado à(s) conta(s) via `tenant_slugs`, `default`
> como fallback universal. Layout atual de Salute/Conexão preservado como verdade
> visual; referência de restore em
> `/Users/thiagodap.fernandes/worksapces/public-layout-backup-20260924-fptc/`.

## Hooks semânticos (aditivos, sem risco visual)

Classes de *papel* no markup público. Temas novos estilizam estas classes;
nunca markup novo, helpers ou branches por chave:

| Hook | Onde |
| --- | --- |
| `ps-topbar` / `ps-brand` / `ps-nav` | `shared/_header` |
| `ps-hero` | `home/_hero` |
| `ps-card` / `ps-card-body` / `ps-price` | `habitations/_card` |
| `ps-footer` | `shared/_footer` |

Âncoras existentes mantidas: classe `public-site-theme--<chave>` e
`data-public-site-theme` no `<body>`, folha via `Tenant#public_site_stylesheet`.

## Paleta como API

O layout público emite no `:root`: `--color-primary`, `--color-secondary`,
`--color-accent`, `--color-hero-button`, `--color-hero-button-text`.
Temas referenciam essas vars em vez de cores fixas — a aba Paleta continua
valendo em qualquer tema.

## Adicionar um tema

Soltar `<chave>.css` em `app/assets/stylesheets/public_site_themes/`.
`Tenant.public_site_theme_definitions` descobre o arquivo (rótulo humanizado
quando fora de `PUBLIC_SITE_THEME_METADATA`) e o `select` da aba Modelo visual
passa a oferecê-lo, respeitando `available_public_site_themes`. Salvar usa o
fluxo existente (`PublicIdentitiesController#update_theme!`).

## Escopo por tenant

Todo tema não-global declara `tenant_slugs` em `PUBLIC_SITE_THEME_METADATA`:
o tema só aparece no `select` das contas listadas. Amarração atual:

| Tema | `tenant_slugs` |
| --- | --- |
| `saluteimoveis`, `salute_luxury` | `salute` |
| `conexaoimobiliaria` | `conexao` |
| `default` | global (fallback de todas as contas) |

A conta também enxerga o tema inferido pelo nome e o que já está em uso, então
renomear a conta nunca esconde o tema atual. `salute_luxury` é variante com
shell próprio (`public_theme/luxury_shell`, classes `sl-*`); os demais temas
estilizam os hooks `ps-*` do markup compartilhado.

## Fora do contrato (futuro)

Portar o luxury do `unitymob-crm` (composers + controller + fontes) como
consumidor deste contrato; convenção de prefixo por tenant para liberar temas
fora do trio conhecido.

## Contrato v2 — classes como API, HTML livre por tema

Mesmas classes, partials podendo variar: cada estrutura HTML alternativa deve
satisfazer `spec/support/contract/shared_property_card_examples.rb` (redução de
venda, redução de locação, sem redução). Nova partial = novo `describe` com
`it_behaves_like "contrato do card público"`.

Ganchos obrigatórios do card (`public-theme-property-card`, variante como
sufixo `--<chave>`): `__media`, `__gallery`/`__gallery-frame`, `__placeholder`,
`__badges`, `__discount-tag`, `__tag`, `__favorite`, `__price-wrap`,
`__previous-price`, `__price-label`, `__price`, `__body`, `__development`,
`__location`, `__specs`, `__whatsapp`, `__opportunity`/`__opportunity--rent`
(`OPORTUNIDADE` venda, `LOCAÇÃO COM PREÇO REDUZIDO` locação); `data-*` de
`marketing-tracker`, `lead-capture` (`data-require-lead-form`) e favorito.

Disciplina de CSS de tema: só seletor plano por classe — sem `>`, `nth-child`
ou posição no DOM. Criar tema: `rails g public_theme <chave>
--label="Rótulo" --tenant-slugs=conta1,conta2` (sem slugs = global).

## Fase 1 — inventário classes legadas × ganchos (2026-09-24)

Levantado por inspeção das 4 folhas e das views que elas estilizam.

| Superfície | Views padrão (classes vivas) | Conexão (125 seletores) | Salute/default (6) | Luxury (471, markup próprio) |
|---|---|---|---|---|
| Card | `shared/tailwind/_property_card` (`.public-property-card`, `.card-swiper`) + canônico (`ps-card`, `__opportunity`) | cobre `.public-property-card`/`.card-swiper`; **não estiliza `__opportunity`** | aliases de token | canônico, faixa escondida |
| Hero | `home/_hero` (`.hero-title`, `.hero-*`, `ps-hero`) + `shared/_search_hero_imobill` (`.hero-search`) | cobre `.hero-*` | aliases de token | próprio |
| Detalhe | `habitations/*` (`.public-habitations-show__*` ~30) | cobre integral | aliases de token | próprio |
| Header/nav/footer | seeds `ps-topbar`, `ps-nav`, `ps-brand`, `ps-footer` emitidos, **zero CSS mirando** | **sem seletores** (herda base) | aliases de token | próprio |
| Tokens | `public-theme-primary/accent/surface/border` emitidos | usa próprios | remap p/ brand | próprios |

Conclusões: seeds `ps-*`/`public-theme-*` não são consumidos por nenhuma folha (contrato a construir na fase 2); Conexão sem header/footer próprios e sem faixa OPORTUNIDADE (fase 3); detalhe e hero da Conexão já têm famílias BEM vivas candidatas a ganchos canônicos.

## Fase 5 — variante luxury formalizada (2026-09-24)

O luxury mantém markup próprio (decisão 1); o contrato dele é emitir as
classes canônicas abaixo. Cobertura em `spec/views/public_theme/*_contract_spec.rb`
e `spec/views/public_theme/luxury_*_spec.rb`.

| Superfície | Markup luxury | Classes canônicas obrigatórias |
|---|---|---|
| Shell | `_luxury_shell` | `public-theme-shell`, `public-theme-shell--salute-luxury` |
| Header | `components/_site_header` | `public-theme-header`, `public-theme-header--<variante>`, `__container`, `__brand`, `__logo`, `__nav`, `__bar`, `__actions`, `__mobile` |
| Footer | `components/_site_footer` | `public-theme-site-footer`, `public-theme-site-footer--<variante>` |
| Hero (home) | `components/_hero` + `_luxury_home_hero` | `public-theme-hero`, `public-theme-hero--<variante>`, `__title`, `__lead`, `__search`, `__overlay`, `__background` |
| Listagem | `components/_property_grid` | `public-theme-property-grid`, `public-theme-property-grid--<variante>` |
| Card | `components/_property_card` | família `public-theme-property-card__*` + `__opportunity` (presente mesmo escondida via `display: none` no CSS luxury) |
| Detalhe | `components/_property_gallery|_info|_contact_box|_map` | `public-theme-property-gallery|info|contact-box|map` + `--<variante>` |
| Empreendimento | `components/_development_*` + `_luxury_development_body` | `public-theme-development-about|features|location|units` + `--<variante>` |

Back-end sem nome próprio: `LuxuryThemeHelper` (`luxury_theme?`,
`luxury_nav_items`, `luxury_logo`); `salute_luxury` vive só como chave do
tema, label e `salute_luxury.css`.

## Fase 6 — validação e QA por conta (2026-09-24)

Automático (verde): `rspec spec/views spec/helpers` — 158 exemplos, 0
falhas; `rails zeitwerk:check` — All is good. Cobre contratos das 7
superfícies, gating por conta (`tenant_site_layout_spec`) e regressão das
views/helpers tocados.

Manual (pendente do dono, contra o backup
`/Users/thiagodap.fernandes/worksapces/public-layout-backup-20260924-fptc/`):

- [ ] Salute tema padrão: home, busca, detalhe, empreendimento
- [ ] Salute luxury: home, busca, detalhe, empreendimento (visual intacto)
- [ ] Conexão: busca com imóvel de preço reduzido (faixa OPORTUNIDADE pill
      dourada), detalhe, header 1430px, hero-search em pill
- [ ] Default: regressão básica
