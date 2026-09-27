# Contrato de temas do site público (v1)

> Meta confirmada (2026-09-24): **Opção A** — um HTML canônico, N folhas CSS por
> tema, cada tema não-global amarrado à(s) conta(s) via `tenant_slugs`, `default`
> como fallback universal. Layout atual de Salute/Conexão preservado como verdade
> visual; referência de restore em
> `/Users/thiagodap.fernandes/worksapces/public-layout-backup-20260924-fptc/`.
>
> **Superada pelo Contrato v2 (mesmo dia, seção abaixo): HTML livre por tema,
> classes como API.** A Opção A vale só como histórico; a regra vigente é:
> partial próprio por tema via `theme_component`, mesmos nomes de classes e
> `data-*`, fallback para o `default`. Nada aqui autoriza markup novo com
> ganchos fora do contrato.

## Hooks semânticos (aditivos, sem risco visual)

Classes de *papel* no markup público. Temas novos estilizam estas classes;
partial próprio por tema é via `theme_component` (mantendo os ganchos do
contrato) — nunca ganchos novos fora do contrato nem branches por chave no
markup compartilhado:

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

Conclusões (histórico da fase — contrato construído no v2 e na Fase 5 acima): seeds `ps-*`/`public-theme-*` não eram consumidos por nenhuma folha; Conexão sem header/footer próprios e sem faixa OPORTUNIDADE (fase 3); detalhe e hero da Conexão já tinham famílias BEM vivas candidatas a ganchos canônicos.

## Fase 5 — variante luxury formalizada (2026-09-24)

O luxury mantém markup próprio (decisão 1); o contrato dele é emitir as
classes canônicas abaixo. Cobertura em `spec/views/public_theme/*_contract_spec.rb`
e `spec/views/public_theme/luxury_*_spec.rb`.

| Superfície | Markup luxury | Classes canônicas obrigatórias |
|---|---|---|
| Shell | `_luxury_shell` | `public-theme-shell`, `public-theme-shell--salute-luxury` |
| Header | `components/_site_header` | `public-theme-header`, `public-theme-header--<variante>`, `__container`, `__brand`, `__logo`, `__phone`, `__nav`, `__bar`, `__actions`, `__mobile` |
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

## Filtro global (FAB + drawer) — 2026-09-25

Um único HTML para todos os temas (`theme_component(:filter_trigger)` e
`theme_component(:filter_panel)` apontam para os mesmos componentes); cada tema
só estiliza a própria variante. O HTML emite **apenas** as classes abaixo —
apelidos de tema (ex.: `.sl-*`) só podem aparecer agrupados no seletor do CSS
do tema, nunca no markup. Garantido por `spec/lib/public_filter_class_contract_spec.rb`.

| Peça | Arquivo | Classes |
| --- | --- | --- |
| FAB | `public_theme/components/_filter_trigger` | `public-theme-filter-fab`, `--<variante>`, `__icon`, `__divider`, `__label`; estados `--visible`, `--hero`, `--fading`, `--measuring` |
| Drawer | `public_theme/components/_filter_drawer` | `public-theme-filter-drawer`, `--<variante>`, `.open`; `__scrim`, `__panel`, `__media`, `__image`, `__grade`, `__ghost`, `__logo`, `__copy`, `__eyebrow`, `__headline`, `__rule`, `__body`, `__close`, `__close-icon`, `__title`, `__title-accent`, `__form`, `__actions`, `__clear`, `__submit`, `__submit-icon` |
| Campos | idem | `__field`, `__label`, `__input`, `__grid`, `__grid--3`, `__search`, `__suggestions`, `__segment`, `__segment-option`, `__range`, `__range-track`, `__range-fill`, `__range-lo`, `__range-hi`, `__range-values`, `__range-value`, `__pills`, `__pill`, `__quick`, `__chip`, `__chip-icon`, `__quick-input`, `__toggles`, `__toggle`, `__toggle-label`, `__toggle-input`, `__toggle-track` |
| Combobox | drawer + busca do hero luxury | `public-theme-combobox`, `.open`; `__trigger`, `__field`, `__tags`, `__tag`, `__tag-label`, `__tag-remove`, `__count`, `__input`, `__caret`, `__panel`, `__option` (`.active`, `.selected`), `__label`, `__hint`, `__check`, `__empty` |

Estados de checkbox usam `:has()` no próprio item (`__chip:has(__quick-input:checked)`,
`__toggle:has(__toggle-input:checked)`), sem depender de irmão (`+`).

Comportamento: controllers `filter-drawer` (abrir/fechar, faixas, pills,
finalidade, reset), `combobox` (selects múltiplos) e `autocomplete` (sugestões
da busca livre). O wrapper `shared/_global_property_search_drawer` fica dentro do
shell do tema, porque o luxury controla o FAB (visibilidade/hero enxuto).

Estilo por tema: variante `default` (default, saluteimoveis, conexaoimobiliaria)
em `components/_public_global_search_drawer.scss`, com a paleta da conta
(`--color-primary`/`--color-accent`); `salute-luxury` em `salute_luxury.css`.
Tema novo: estilizar `.public-theme-filter-drawer--<variante>` e
`.public-theme-filter-fab--<variante>` e registrar os dois componentes.

Quartos/Suítes/Vagas: 1, 2, 3 = quantidade exata (`bedrooms`/`suites`/`parking`);
4+ = mínimo (`min_*`).

## Regra de todos os temas (existentes e futuros)

Ajuste, correção ou desenvolvimento em template do site público cobre **todos**
os temas da pasta `public_site_themes/`, nunca só o do chamado. Cada entrega
traz veredito explícito por tema: corrigido ou "já legível, sem mudança".
Motivo: com HTML livre por tema, nada se propaga sozinho — o que corrige num
variant não corrige nos outros.

A regra vale para temas futuros: tema novo entra no padrão estabelecido, com
seu próprio CSS, sem travas só para os atuais.

## Novo tema (checklist)

1. Criar `<chave>.css` em `app/assets/stylesheets/public_site_themes/` via
   `rails g public_theme <chave> --label="Rótulo" --tenant-slugs=conta1,conta2`
   (sem slugs = global). Escopo no CSS sempre via
   `data-public-site-theme="<chave>"` no body.
2. Registrar os componentes em `Tenant::PUBLIC_SITE_THEME_METADATA` (só o que
   diverge; o resto herda do `default` via `theme_component`).
3. Declarar `tenant_slugs` para amarrar às contas (fora isso o tema não aparece
   no `select` de Modelo visual).
4. Emitir os ganchos do contrato em cada partial próprio (tabelas acima; detalhe
   em `spec/support/contract/`) e cobrir com `it_behaves_like` por superfície em
   `spec/views/public_theme/`.
5. Contas novas nascem no tema `default` (`Tenant#public_site_theme_key` cai para
   `DEFAULT_PUBLIC_SITE_THEME` quando vazio) — nenhum passo extra é preciso.
