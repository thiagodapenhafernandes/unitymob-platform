# Contrato de temas do site público

Regra de trabalho resumida em `AGENTS.md` (seção "Site público e temas"). Este
documento é a referência completa. Última revisão: 2026-09-27.

## Regra de todos os temas (existentes e futuros)

- Ajuste, correção ou desenvolvimento em qualquer tela, componente, CSS ou
  comportamento do site público cobre **todos** os temas de
  `app/assets/stylesheets/public_site_themes/`, cada um na sua identidade
  visual. Nunca só o tema do pedido.
- O que existe num tema e falta em outro é replicado na mesma entrega. Cada
  entrega traz o veredito por tema: ajustado, ou já coberto sem mudança.
- Vale para temas futuros: tema novo entra no padrão com o próprio CSS. Nada
  de condição ou trava que funcione só para os temas atuais (`if tema == ...`
  no markup compartilhado).
- Garantia automática: `spec/requests/public_themes_contract_spec.rb` percorre
  `Tenant::PUBLIC_SITE_THEMES` (as folhas do diretório) e confere home, página
  do imóvel e empreendimentos em cada tema, inclusive nos criados depois.

## Modelo: um HTML por componente, classes como API

- Cada componente vive uma vez em `app/views/public_theme/components/` e emite
  classes `public-theme-<componente>` + `__elemento` + a variante como sufixo
  `--<variante>`.
- **Variante** é a família visual do tema, definida em
  `Tenant::PUBLIC_SITE_THEME_METADATA[:variant]`:
  - `default` — temas `default`, `saluteimoveis`, `conexaoimobiliaria` e todo
    tema novo gerado;
  - `salute-luxury` — tema `salute_luxury`.
- `theme_component(:nome)` resolve o partial do tema (ou o do `default`) e
  passa `variant:`. Tema com desenho próprio registra partials em
  `[:components]`, mas emite **as mesmas classes**.
- Apelidos de tema (`.sl-*`) só existem no CSS do tema, agrupados no seletor.
  Nunca no HTML de componente compartilhado.

## Onde fica o CSS

| Camada | Arquivo | Carrega | Regra de escopo |
| --- | --- | --- | --- |
| Variante `default` | `app/assets/stylesheets/components/_public_theme_*.scss` e `_public_global_search_drawer.scss` (no `application.css`) | Em **todas** as páginas, de todos os temas | Sempre com `--default` no seletor; senão vaza para o luxury. Conferido pelo spec de contrato. |
| Comum a todos os temas | Mesmos arquivos, em bloco comentado como comum | Todas | Só estrutura/comportamento (ex.: cascata de abertura do menu, alinhamento de `__actions`). Aparência nunca. |
| Pele de um tema | `app/assets/stylesheets/public_site_themes/<chave>.css` | Só com o tema ativo | Pode usar as classes do contrato direto. Temas da variante `default` escopam em `[data-public-site-theme="<chave>"]` (atributo do `<body>`). |

Paleta da conta no `:root` (aba Paleta vale em qualquer tema):
`--color-primary`, `--color-secondary`, `--color-accent`,
`--color-hero-button`, `--color-hero-button-text`. Temas usam essas variáveis
em vez de cores fixas.

Seletores: planos por classe do contrato. Nada de `>` ou posição no DOM para
dar aparência a componente (o HTML pode variar por tema). `nth-child` só para
escalonar animação de itens de lista.

## Componentes do contrato

| Componente | Partial | Classe raiz | Observação |
| --- | --- | --- | --- |
| Shell | `public_theme/_luxury_shell` (luxury) / `layouts/_default_shell` | `public-theme-shell--salute-luxury` (a variante `default` não tem wrapper) | Luxury: header, menu e rodapé na própria pele |
| Header | `components/_site_header` / `layouts/_header` | `public-theme-header--<variante>` | Botão ☰ dispara `public-navigation:open` |
| Menu em tela cheia | `components/_navigation_overlay` | `public-theme-navigation-overlay--<variante>` | Catálogo com contagens (`PublicSite::CatalogNavigation`), links do admin, contato real, foto (`HomeSetting#navigation_menu_image` ou hero). Controller `navigation-overlay` |
| Filtro global | `components/_filter_trigger`, `_filter_drawer` | `public-theme-filter-fab--<variante>`, `public-theme-filter-drawer--<variante>` | Detalhe abaixo |
| Busca do hero | `components/_search_form` | `public-theme-search--<variante>` | Combobox compartilhado |
| Cabeçalho de página | `components/_page_head` | `public-theme-page-head--<variante>` | Páginas internas (ex.: `/empreendimentos`) |
| Cabeçalho de seção | `components/_section_head` | `public-theme-section__head--<variante>` | Todas as seções da home |
| Seção da home | `home/index`, `home/_blog_section`, `home/_video_properties_section` | `public-theme-home-section--<variante>` (+ `--alt` alternado) | Botão "Ver todos": `public-theme-section__cta--<variante>` |
| Card de imóvel | `shared/tailwind/_property_card` / `components/_property_card` | família `public-theme-property-card__*` | Ganchos obrigatórios abaixo |
| Card de empreendimento | `shared/tailwind/_development_card` | `public-theme-dev-card--<variante>` | Home e `/empreendimentos` |
| Paginação | `components/_pagination` (todos os temas) | `public-theme-pagination--<variante>` | `<nav>` com `aria-label`; só aparece com mais de uma página |
| Listagem de empreendimentos | `empreendimentos/index` | `public-theme-developments--<variante>` | Filtros próprios; esconde o filtro global |
| Simulador de financiamento | `components/_financing_simulator` | `public-theme-financing-simulator--<variante>` (+ `--property` no imóvel) | Recurso por conta (Perfil público). `/simulador` e bloco no imóvel à venda; SAC e Price no navegador (controller `financing-simulator`); taxa do Banco Central (`Financing::CentralBankRate`, séries 20774/20773/20772) ou própria; botão abre a captura de lead com os valores |
| Página do imóvel | `components/_property_gallery`, `_info`, `_contact_box`, `_map`, `_amenities`, `_development`, `_city_links` | `public-theme-property-*--<variante>`, `public-theme-city-links--<variante>` | Nome do empreendimento só com opção da conta ligada |
| Empreendimento | `components/_development_*` | `public-theme-development-*--<variante>` | |
| Rodapé | `components/_site_footer` / `layouts/_footer` | `public-theme-site-footer--<variante>` | |

Cobertura: `spec/requests/public_themes_contract_spec.rb` (todos os temas),
`spec/views/public_theme/*_contract_spec.rb` e `spec/support/contract/`
(superfícies), `spec/lib/public_filter_class_contract_spec.rb` (filtro).

### Card de imóvel — ganchos obrigatórios

`__media`, `__gallery`/`__gallery-frame`, `__placeholder`, `__badges`,
`__discount-tag`, `__tag`, `__favorite`, `__price-wrap`, `__previous-price`,
`__price-label`, `__price`, `__body`, `__development`, `__location`, `__specs`,
`__whatsapp`, `__opportunity`/`__opportunity--rent` (`OPORTUNIDADE` venda,
`LOCAÇÃO COM PREÇO REDUZIDO` locação); `data-*` de `marketing-tracker`,
`lead-capture` (`data-require-lead-form`) e favorito. Partial nova de card =
novo `describe` com `it_behaves_like "contrato do card público"`.

### Filtro global (FAB + drawer)

| Peça | Classes |
| --- | --- |
| FAB | `public-theme-filter-fab`, `--<variante>`, `__icon`, `__divider`, `__label`; estados `--visible`, `--hero`, `--fading`, `--measuring` |
| Drawer | `public-theme-filter-drawer`, `--<variante>`, `.open`; `__scrim`, `__panel`, `__media`, `__image`, `__grade`, `__ghost`, `__logo`, `__copy`, `__eyebrow`, `__headline`, `__rule`, `__body`, `__close`, `__close-icon`, `__title`, `__title-accent`, `__form`, `__actions`, `__clear`, `__submit`, `__submit-icon` |
| Campos | `__field`, `__label`, `__input`, `__grid`, `__grid--3`, `__search`, `__suggestions`, `__segment`, `__segment-option`, `__range`, `__range-track`, `__range-fill`, `__range-lo`, `__range-hi`, `__range-values`, `__range-value`, `__pills`, `__pill`, `__quick`, `__chip`, `__chip-icon`, `__quick-input`, `__toggles`, `__toggle`, `__toggle-label`, `__toggle-input`, `__toggle-track` |
| Combobox | `public-theme-combobox`, `.open`; `__trigger`, `__field`, `__tags`, `__tag`, `__tag-label`, `__tag-remove`, `__count`, `__input`, `__caret`, `__panel`, `__option` (`.active`, `.selected`), `__label`, `__hint`, `__check`, `__empty` |

Estados de checkbox com `:has()` no próprio item. Controllers `filter-drawer`,
`combobox` e `autocomplete`. Quartos/Suítes/Vagas: 1, 2, 3 = exato
(`bedrooms`/`suites`/`parking`); 4+ = mínimo (`min_*`). Foto do painel:
`HomeSetting#filter_panel_background`.

### Layouts do hero da home (Barra e Cartão)

Além do hero Clássico (o de sempre), a Home escolhe o layout em `home_settings.hero_layout` (`classic`, `bar`, `card`).
Cada layout é um componente com HTML único em `public_theme/components/hero_<layout>.html.erb`, que usa o `components/hero`
(fundo, sobreposição) e emite as mesmas classes em todos os temas:

- `public-theme-hero-bar(--<variante>)`: `__container`, `__inner`, `__search`, `__form`, `__tabs`, `__tab`, `__field`, `__control`, `__submit`, `__detail`.
- `public-theme-hero-card(--<variante>)`: `__container`, `__inner`, `__panel`, `__tabs`, `__tab`, `__title`, `__lead`, `__modes`, `__mode`, `__filters`, `__grid`, `__field`, `__control`, `__chips`, `__chip`, `__submit`, `__ai`, `__textarea`, `__mic`, `__suggestion`, `__error`, `__footer`.
- A posição horizontal da busca (`hero_search_align`) vira o modificador `is-align-left|center|right` na raiz.
- Variante `default`: `components/_public_theme_hero_layouts.scss`; luxury: bloco "Layouts do hero" de `public_site_themes/salute_luxury.css`.
- Comportamento (abas, voz) fica no controller `hero-search`, igual para todos os temas e layouts (Clássico, Barra e Cartão).
- Buscador por voz (`components/hero_voice`, `.public-theme-hero-voice(--<variante>)`): o botão `.public-theme-hero-voice__toggle` entra como primeiro botão do grupo de finalidade (antes de Comprar) e troca o formulário de filtros por uma barra no estilo do WhatsApp — já grava, mostra a onda sonora real (Web Audio em `canvas`) e o cronômetro, e o botão de ação (`__send`, no lugar do Buscar) vira "enviar". `data-state` (idle | recording | busy | text) comanda o que aparece; sem microfone vira campo de texto. Liga/desliga em `home_settings.hero_ai_search_enabled`.
- A busca por descrição/voz fala com `POST /busca-ia`, que só devolve a URL da listagem com os filtros (nunca imóveis). Exige o recurso ligado na Home **e** a IA de busca da conta pronta.

## Temas e contas

| Tema | Variante | Contas (`tenant_slugs`) |
| --- | --- | --- |
| `default` | `default` | global — fallback de todas |
| `saluteimoveis` | `default` | `salute`, `saluteimoveis` |
| `conexaoimobiliaria` | `default` | `conexao`, `conexaoimobiliaria` |
| `salute_luxury` | `salute-luxury` | `salute`, `saluteimoveis` |

- **Conta nova nasce no `default`.** Garantido em duas camadas: `attribute
  :public_site_theme, default: "default"` no `Tenant` (vale mesmo se o padrão
  da coluna no banco estiver errado) e a migration idempotente
  `20260927090000_ensure_default_public_site_theme`. Se o nome/slug da conta
  bater com um tema cadastrado, ela nasce nele.
- A conta só vê no select de Modelo visual os temas globais, os do próprio
  `tenant_slugs`, o inferido pelo nome e o que já está em uso.
- `tenant_slugs` casa com o **slug** da conta ou com o **nome dela em forma
  compacta** ("Salute Imóveis" → `saluteimoveis`). Em produção a conta
  principal de cada servidor tem slug `default`; quem identifica a marca é o
  nome. Ao amarrar um tema a uma conta, liste os dois.

## Novo tema (checklist)

1. `rails g public_theme <chave> --label="Rótulo" --tenant-slugs=conta1,conta2`
   (sem slugs = global). Cria `public_site_themes/<chave>.css` e registra o
   tema na variante `default` com `DEFAULT_THEME_COMPONENTS`: o tema já nasce
   com todos os componentes funcionando.
2. Estilizar a pele no CSS gerado, com escopo em
   `[data-public-site-theme="<chave>"]`, mirando classes do contrato.
3. Desenho próprio de algum componente: partial novo registrado em
   `[:components]`, emitindo as mesmas classes, e (se for uma família visual
   nova) variante própria + estilos `--<variante>` para **todos** os
   componentes da tabela acima.
4. Rodar `bundle exec rspec spec/requests/public_themes_contract_spec.rb
   spec/views/public_theme spec/lib` e `npm run build:css`.

## Histórico

Opção A (2026-09-24, HTML único com hooks `ps-*`), contrato v2, fases 1 a 6 e
o port do luxury do `unitymob-crm` estão no histórico do git deste arquivo. Os
hooks `ps-*` restantes (ex.: `ps-hero` em `home/_hero`) são legado e não fazem
parte da API.
