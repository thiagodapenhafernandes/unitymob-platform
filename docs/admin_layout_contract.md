# Admin Analytics Builder Design System

Este documento é a fonte de verdade e o ponto de entrada para implementar telas
do admin no padrão Analytics Builder / Dense Enterprise Workspace.

O arquivo visual de referência é:

```text
public/analytics-builder-design-system/
```

Use esse design system como referência de conceito, tokens e densidade. Não copie o
mock literalmente para todos os módulos. A aplicação Rails deve usar componentes
`ax-*` próprios, reutilizáveis, preservando comportamento, permissões, parâmetros,
submits e auditoria existentes.

## Ponto De Entrada Operacional

Antes de mexer em uma tela admin, consulte nesta ordem:

1. Este contrato.
2. `public/analytics-builder-design-system/` para direção visual e tokens.
3. `app/views/admin/shared/ui/` para partials compartilhadas.
4. `app/helpers/admin/ui_helper.rb` para helpers `ax_*`.
5. `app/javascript/controllers/ax_*.js` para comportamentos compartilhados.

Sinais de dívida visual que pedem leitura crítica antes de migrar:

```text
row, col-*, card, form-group, alert, badge, btn, form-control, d-none, style=
```

O ranking inicial por volume no estado atual aponta como próximos lotes mais
relevantes: `admin/habitations/index`, SEO (`seo_settings` e `seo_dashboard`) e
Captações. O volume não prova erro sozinho; apenas indica onde vale auditar com
mais cuidado antes de mexer.

## Objetivo

O admin deve ser um workspace operacional denso:

- muita informação útil visível;
- baixa carga cognitiva;
- controles compactos;
- hierarquia visual previsível;
- comportamento Rails preservado;
- remoção gradual de Bootstrap e código visual legado.

Não é skin sobre Bootstrap. Quando uma área já tiver equivalente `ax-*`, remova o
markup/classe/controller legado que só sustentava a interface antiga.

## Princípio De Componentização (Regra De Ouro)

Toda migração de layout segue as diretrizes deste documento **e usa componentes
reutilizáveis**. A missão é construir um design system robusto e consistente,
padronizado em componentes — não telas com markup/CSS soltos.

Regras inegociáveis:

1. **Sempre usar o componente existente** (`ax_*` helper / partial em
   `app/views/admin/shared/ui`). Antes de escrever markup, procurar o componente
   equivalente no inventário abaixo.
2. **Se o componente não existir, criar primeiro** o componente compartilhado
   (partial em `shared/ui` + helper em `Admin::UiHelper` + CSS namespeado `.ax-*`)
   e só então usar na tela. Não resolver com markup/CSS local "só nesta tela".
3. **Se o padrão visual aparece em 2+ telas, promover** para `shared/ui` antes de
   replicar.
4. **Não recriar um card/painel/coluna na mão.** Cards de conteúdo =
   `ax_operational_panel` (estilo dashboard: header `#f8fafc`, título 13px/800,
   eyebrow 10px). KPIs = `ax_metric_card`. Colunas de kanban = `ax_board` +
   `ax_board_column`. Painel genérico = `ax_panel`.
5. **Não usar hack de CSS escopado para imitar um componente.** Dois antipadrões já
   corrigidos no projeto: o token global `--ax-panel-header` (#eef2f7) é igual ao
   fundo da página e some; e a regra global `.ax-app h2 { 1.3rem }` infla títulos
   de classe única — ambos resolvidos nativamente por `ax_operational_panel` e pelo
   header escopado do board. Se um título de componente vier inflado, é
   especificidade contra `.ax-app h2/h1`: escopar com 2 classes, não baixar via
   `!important`.
6. **Ao corrigir um componente compartilhado, corrigir na origem** (partial/CSS do
   componente), beneficiando todas as telas — não duplicar a correção por tela.
7. **Sempre que puder, remover legado de Bootstrap.** A tendência é remover o
   Bootstrap 100%; `admin_compat.css` é ponte temporária, não base. Ao
   migrar/tocar numa área, trocar `row`/`col`/`card`/`form-group`/`alert`/`badge`/
   `btn`/`form-control` e markup/controllers que só sustentam o visual antigo pelos
   primitivos `ax-*`, e apagar o legado que ficou sem função — preservando
   comportamento, params, permissões, uploads e submits.

## Fonte De Tema

Tokens base vêm de `public/analytics-builder-design-system/index.html` e
`public/analytics-builder-design-system/tailwind.config.js`.

### Tokens Obrigatórios

```css
:root {
  --admin-primary: #365f8f;
  --admin-primary-fg: #ffffff;
  --admin-primary-hover: color-mix(in srgb, var(--admin-primary) 86%, #000);
  --admin-primary-soft: color-mix(in srgb, var(--admin-primary) 12%, #fff);
  --admin-primary-softer: color-mix(in srgb, var(--admin-primary) 7%, #fff);
  --admin-primary-ring: color-mix(in srgb, var(--admin-primary) 35%, #fff);

  --ab-page: #eef2f7;
  --ab-panel: #fbfcfe;
  --ab-panel-soft: #f4f7fb;
  --ab-panel-header: #eef2f7;
  --ab-line: #d8dee8;
  --ab-line-soft: #e7ebf2;
  --ab-ink: #202a37;
  --ab-muted: #657386;

  --ab-field-border: #cfd8e5;
  --ab-field-hover: #b8c5d6;
  --ab-field-focus: #7f96b5;
  --ab-control-bg: #ffffff;
  --ab-control-hover: #f8fafc;

  --ax-shell-gutter: 12px;
  --ax-shell-gutter-sm: 8px;
  --ax-shell-gutter-lg: 12px;
  --ax-workspace-gutter: var(--ax-shell-gutter);
}
```

### Regras De Cor

- `#365F8F` é o default do novo admin.
- `#2563EB` é fallback legado; não usar como default em tela migrada.
- `primary`, `surface.DEFAULT`, `surface.header`, `workspace.background`,
  `sidebar.background` e `ink` são os tokens principais do conceito.
- `surface.header` controla cabeçalhos e superfícies de topo; não deve ser usado
  como background da `ax-main` nem da `ax-sidebar`.
- `workspace.background` controla o fundo do workspace principal e do `ax-main`.
- `sidebar.background` controla exclusivamente o fundo da navegação lateral
  `ax-sidebar`.
- Cores de site público continuam separadas. Não use tokens públicos para
  inferir comportamento do admin nem vice-versa.
- Customização em `/admin/layout_setting/edit` deve deixar claro o impacto:
  tokens do CRM/admin afetam `/admin`; tokens do site afetam o site público.

### Checkpoint De Migração — 2026-06-19

Estado confirmado no filesystem deste checkout:

- O arquivo compat carregado pelo admin é `app/assets/stylesheets/admin_compat.css`.
  Não existe `app/assets/stylesheets/admin_bootstrap_compat.css` no estado atual.
- `admin_compat.css` continua sendo ponte temporária real, carregada junto com
  `admin.css` e `admin_tailwind.css`; não remover até zerar dependências de
  classes/estados legados nas views e controllers.
- `app/views/admin` tem 261 arquivos; `app/views/admin/shared/ui` tem 51
  partials; existem 13 controllers Stimulus `ax_*`.
- Backups dentro de `app` estão zerados. Backups em `tmp` continuam fora do
  versionamento.
- O azul legado `#2563EB` foi removido das views admin. Resíduos fora das views
  admin, como `property_card.css`, `sidebar.css`, `application.scss` e
  `store_map_picker_controller.js`, devem ser tratados em lote próprio após
  confirmar impacto no front público.
- Próximo lote recomendado: migrar JS inline/handlers soltos e remover
  dependências de `d-none` nos controllers que ainda controlam estado visual.

## Performance Do Admin

Performance faz parte do contrato visual e operacional do admin. Uma tela densa
só é aceitável se continuar interativa rapidamente; densidade não justifica
carregar JS, HTML, imagens ou queries que a tela não usa no primeiro momento.

### Diagnóstico Antes De Otimizar

Antes de alterar código por sensação de lentidão, coletar evidência:

- Lighthouse ou DevTools Performance/Network da rota real.
- Logs Rails do request principal e de `turbo-frame`/fetches adjacentes.
- Separar: TBT/long tasks de JS, tempo de backend, tamanho do HTML, quantidade
  de scripts, peso de CSS, payload de imagens e requests assíncronos.
- Não concluir que "é JS bloqueando" sem TBT/long task ou stack de main thread.

Evidência que fundamentou a diretriz em `/admin/habitations?ownership=all`:

- Lighthouse apontou `total-blocking-time: 0 ms`, sem long tasks relevantes.
- Main thread ficou abaixo de 1s, então o travamento percebido não era CPU JS
  clássica.
- A tela carregava 147 scripts separados por importmap/controllers.
- O inspector do catálogo entrava via `/admin/habitations/filter_inspector` com
  aproximadamente 132 KB de HTML e várias queries `DISTINCT` para opções.
- O `turbo-frame` do inspector estava lazy; para filtro lateral importante, isso
  atrasava a tela ficar utilizável.
- Imagens dos cards vieram como gargalo de rede separado, com blobs grandes
  levando segundos; tratar thumbnails/variants em passo próprio para não trocar
  rede por processamento pesado no primeiro acesso.

### Regras De Evolução

- O manifest Stimulus do admin deve favorecer lazy loading de controllers. Não
  voltar a importar e registrar todos os controllers em `controllers/index.js`
  se a tela usa só uma fração deles.
- Controllers Stimulus compartilhados devem continuar pequenos e conectados ao
  DOM real por `data-controller`; evite controllers globais que varrem a página
  inteira no `connect`.
- `turbo-frame` essencial para a primeira interação da tela deve carregar
  `eager`; use `lazy` apenas para conteúdo realmente secundário ou abaixo da
  dobra.
- HTML assíncrono pesado deve ser medido. Se um frame passa a carregar muitas
  opções, muitos partials ou muitos selects com TomSelect, considere reduzir
  payload, paginar/buscar remoto, cachear dados ou renderizar apenas seções
  abertas/ativas.
- Consultas de opção de filtro devem ser cacheadas, escopadas e revisadas com
  logs reais. Várias consultas `DISTINCT` em cada navegação do catálogo viram
  custo perceptível mesmo quando cada uma parece barata isoladamente.
- TomSelect e multiselects devem inicializar sob demanda quando estiverem
  ocultos ou em seções fechadas. Não force inicialização de todos os selects se
  o usuário ainda não abriu a seção.
- Imagens de catálogo devem usar fontes pequenas/thumbnail quando disponíveis.
  Antes de forçar Active Storage variants, medir impacto de processamento,
  cache e storage para não piorar o primeiro acesso.
- Resolução de imagem pública de imóvel deve ser CDN-only e barata por item.
  Não registrar/recriar serviços do Active Storage por foto. A API/payload Vista
  não é fonte de verdade para catálogo/site público; a fonte pública é o anexo
  local em `Habitation.photos` ou uma URL já no CDN configurado. Recuperações
  pontuais de Vista devem ficar em telas/serviços específicos da integração, não
  no caminho de renderização do catálogo.
- Toda otimização de performance precisa preservar params, permissões,
  comportamento Rails/Turbo, acessibilidade básica e fallback sem JS quando
  existir.

### Quality Gate De Performance

Ao mexer em listagens densas, inspector, catálogo de imóveis, dashboards ou
formulários com muitos campos:

1. Rodar `assets:precompile` quando alterar JS/CSS/importmap.
2. Rodar `zeitwerk:check` quando alterar Rails.
3. Conferir no diff se não houve reintrodução de imports globais pesados.
4. Se houver Lighthouse/DevTools disponível, comparar pelo menos TBT, número de
   scripts, peso do documento, requests assíncronos e imagens mais lentas.
5. Registrar no resumo se a causa era backend, rede, HTML, CSS/layout, JS
   main-thread ou inicialização de componentes.

## Anatomia Global

O admin migrado usa cinco componentes estruturais visíveis:

```text
ax-topbar
ax-contextbar
ax-sidebar
ax-main
ax-aside
```

Contrato completo:

```text
ax-admin-shell
├── ax-topbar
├── ax-contextbar
└── ax-admin-body
    ├── ax-sidebar
    └── ax-workspace
        ├── ax-main
        │   └── conteúdo principal da tela
        └── ax-aside [opcional]
            └── conteúdo contextual da tela
```

Regras:

- `ax-contextbar`, cabeçalho da `ax-sidebar` e cabeçalho da `ax-aside`
  compartilham a mesma régua vertical abaixo da `ax-topbar`.
- `ax-main` e `ax-aside` são irmãos dentro de `ax-workspace`.
- `ax-aside` nunca fica dentro do fluxo do `ax-main`.
- Conteúdo no `ax-main` não pode empurrar, deslocar ou alterar a altura inicial
  do `ax-aside`.
- A coluna direita pode existir ou não por tela, mas sua estrutura, largura,
  colapso, sticky/top e overflow pertencem ao componente compartilhado.

## Régua De Espaçamento

O respiro lateral do admin migrado é contrato do shell, não decisão local da
tela. O valor padrão é:

```css
:root {
  --ax-shell-gutter: 12px;
}

.ax-workspace-shell {
  --ax-workspace-gutter: var(--ax-shell-gutter);
}
```

Regras:

- `ax-navbar`, `ax-contextbar`, cabeçalho da `ax-sidebar`, `ax-main` e cabeçalho
  da `ax-aside` devem usar a mesma régua lateral.
- Em telas com master-detail, o body do `ax-main` e o body/header do `ax-aside`
  devem herdar `--ax-workspace-gutter`.
- Não criar compensações locais com `18px`, `.75rem`, `0` ou margens negativas
  para alinhar uma tela específica.
- Se uma tela precisar de densidade diferente, crie uma variação do shell com
  token explícito; não sobrescreva padding em cards, seções ou componentes
  internos.
- Componentes internos (`ax_form_section`, `ax_field_grid`, cards de catálogo,
  filtros do inspector) controlam o espaçamento dentro do seu próprio limite,
  mas não definem a distância entre sidebar/contextbar/main/aside.

## Quando Usar Cada Área

| Área | Uso |
| --- | --- |
| `ax-topbar` | identidade, usuário, ações globais |
| `ax-contextbar` | breadcrumb, estado da tela e ações do módulo |
| `ax-sidebar` | navegação global do produto/admin |
| `ax-main` | listagem, formulário, detalhe ou dashboard da tela |
| `ax-aside` | filtros, editor, propriedades, preview, mapa de impacto |

Exemplos:

- Catálogo de imóveis: `ax-main` com lista/cards, `ax-aside` com filtros.
- Cadastro de imóveis: `ax-main` com formulário, `ax-aside` com Editor do imóvel.
- Configurações de aparência: `ax-main` com formulário, `ax-aside` com mapa de impacto.
- Dashboard: `ax-main` com KPIs/gráficos, `ax-aside` opcional para filtros/contexto.

## Componentes Rails

Os componentes reutilizáveis vivem em:

```text
app/helpers/admin/ui_helper.rb
app/views/admin/shared/ui/
app/assets/stylesheets/admin_tailwind.css
app/javascript/controllers/ax_*.js
```

Use helpers `ax_*` em views Rails. Se um padrão aparece em duas telas, promova
para `app/views/admin/shared/ui` antes de replicar markup.

## Componentes Estruturais

| Helper/partial | Uso |
| --- | --- |
| `ax_workspace_shell` / `_workspace_shell.html.erb` | cria `ax-main` + `ax-aside` como irmãos |
| `ax_aside_panel` / `_aside_panel.html.erb` | estrutura da coluna direita com header, token e rail recolhido |
| `ax_sticky_action_footer` / `_sticky_action_footer.html.erb` | footer persistente de ações |

Exemplo:

```erb
<%= render "admin/shared/ui/workspace_shell",
           main_label: "Cadastro de imóvel",
           main: form_main,
           aside: editor_aside,
           aside_label: "Editor do imóvel",
           controller: "habitations-inspector",
           storage_key: "admin-habitation-form-editor-collapsed" %>
```

## Componentes De Formulário

| Helper | Quando usar |
| --- | --- |
| `ax_form_section` | seção compacta, com header funcional e colapso |
| `ax_field_grid` | grid denso de campos em 12 colunas |
| `ax_field_group` | subgrupo interno sem card dentro de card |
| `ax_field_label` | label padronizado com tooltip por ícone de info |
| `ax_text_field` | input simples |
| `ax_select_field` | select simples |
| `ax_relationship_select` | select relacional com ação acoplada `+` |
| `ax_input_group` | prefixo/sufixo/ação acoplada sem borda duplicada |
| `ax_currency_field` | valores monetários com prefixo `R$` |
| `ax_number_field` | quantidades e números compactos |
| `ax_date_field` | datas alinhadas ao padrão dos inputs |
| `ax_measure_field` | valores com unidade (`m²`, `%`, etc.) |
| `ax_multiselect_field` | TomSelect multi com manager opcional |
| `ax_toggle_chip` | checkbox visual em pill |
| `ax_radio_group` | escolhas exclusivas em pills |
| `ax_dynamic_list_field` | listas de valores repetíveis |
| `ax_file_upload_button` | acionador visual de upload |
| `ax_attachment_item` | anexo compacto com ações |
| `ax_inline_notice` | aviso curto no lugar de `alert` Bootstrap |
| `ax_info_badge` | dado readonly/informativo |

Exemplo:

```erb
<%= ax_form_section(title: "Definições básicas", eyebrow: "Classificação") do %>
  <%= ax_field_grid do %>
    <div class="ax-span-6">
      <%= ax_select_field(
            form: f,
            method: :tipo,
            label: "Tipo de cadastro",
            choices: tipo_options
          ) %>
    </div>

    <div class="ax-span-6">
      <%= ax_select_field(
            form: f,
            method: :categoria,
            label: "Categoria",
            choices: categoria_options
          ) %>
    </div>
  <% end %>
<% end %>
```

## Componentes De Mídia E Documentos

| Helper | Uso |
| --- | --- |
| `ax_media_source_notice` | origem/vínculo de mídia |
| `ax_media_upload_panel` | painel de upload, classificação, watermark e feedback |
| `ax_media_grid` | container da galeria/preview |
| `ax_media_tile` | tile de foto com posição, destaque, ações e estado |
| `ax_attachment_item` | item de documento/anexo |
| `ax_file_upload_button` | botão de upload conectado ao input real |

Regras:

- Preservar contratos de Stimulus/Sortable (`data-photo-upload-target`,
  `draggable-item`, ids de inputs e hidden fields).
- Não voltar a `row/col`, `ratio`, `badge` ou `btn` Bootstrap dentro dos tiles.
- Remoção destrutiva deve usar confirmação inline, não `window.confirm`.

## Componentes De Apoio

| Helper/controller | Uso |
| --- | --- |
| `ax_button` | botão padrão do admin |
| `ax_icon_button` | botão só com ícone e tooltip/title |
| `ax_badge` / `_badge.html.erb` | status compacto |
| `ax_metric_card` | KPIs compactos |
| `ax_panel` | painel genérico |
| `ax_operational_panel` | painel operacional com header denso |
| `ax_record_item` | item de lista interna/relacionamento |
| `ax_quick_modal` | cadastro rápido sem Bootstrap modal |
| `ax_empty_state` | vazio contextual |
| `ax_error_summary` | resumo de validação |
| `ax_filter_form` | formulário de filtro |
| `ax-confirm-submit` | confirmação inline para submit destrutivo |
| `lead_whatsapp_panel` | bloco de conversa WhatsApp dentro do lead |
| `whatsapp_composer` | composer compartilhado de texto/mídia/template |

## Regra De Componentização

Quando surgir oportunidade clara de componentizar um elemento recorrente,
eliminar conflito de CSS espalhado ou substituir markup manual equivalente a uma
primitive `ax-*`, isso deve ser feito no mesmo fluxo de trabalho, sem depender
de confirmação extra.

Ordem esperada:

1. identificar o padrão repetido ou o conflito;
2. promover para primitive compartilhada (`shared/ui` + helper + CSS global);
3. aplicar o componente novo na tela atual;
4. ao tocar em legado adjacente da mesma área, substituir o legado pelo
   componente em vez de manter duas versões.

Em área migrada, markup manual equivalente a primitive existente deve ser
tratado como dívida a remover, não como atalho aceitável. Se o componente ainda
não cobre o caso, a prioridade é evoluir o componente compartilhado, depois
substituir o uso local.

Guardrail operacional: rode `bin/rails admin:verify_ui_contract` ao fechar uma
fatia migrada. O verificador inicial cobre áreas já migradas de SEO, inbox
WhatsApp e disparos WhatsApp e falha
quando encontra:

- `<span class="ax-badge ...">` manual em vez de `ax_badge`;
- classes Bootstrap residuais (`row`, `col-*`, `form-group`, `card*`, `badge*`,
  `btn*`, `form-control`) dentro dessas áreas;
- override local de `.ax-badge` por seletor de tela, quando a correção deveria
  acontecer na primitive compartilhada.

Exemplo de confirmação inline:

```erb
<span data-controller="ax-confirm-submit"
      data-ax-confirm-submit-form-id-value="purge_attachment_<%= attachment.id %>"
      data-ax-confirm-submit-message-value="Remover este arquivo?"
      data-ax-confirm-submit-confirm-label-value="Remover">
  <%= button_tag type: "button",
                 class: "ax-btn ax-btn--ghost ax-btn--sm text-danger",
                 data: { action: "click->ax-confirm-submit#request" } do %>
    <i class="bi bi-trash"></i>
  <% end %>
</span>
```

## Componentes De Dashboard, Listagem E Kanban

| Helper | Quando usar |
| --- | --- |
| `ax_page_header` | cabeçalho simples de página (título, subtítulo, ações) |
| `ax_workspace_heading` | cabeçalho operacional do `ax-main`: eyebrow + título com pills, subtítulo, métricas e ações (ex.: listagem de leads/imóveis) |
| `ax_operational_panel` | **card padrão de conteúdo** (estilo dashboard): eyebrow + título (h2 13px/800) + ações + body. Header `#f8fafc`. O body já controla respiro interno com `padding` e `gap`; não adicionar wrapper só para separar header de tabela/lista. É o card a usar em telas de configuração, seções e painéis informativos |
| `ax_panel` | painel genérico com `title/subtitle/actions/body` quando não precisar do eyebrow do operational |
| `ax_metric_card` | KPI compacto (label, value, badge, hint, progress) |
| `ax_board` | container do kanban (grid de colunas com scroll horizontal); `data:` recebe o controller do consumidor |
| `ax_board_column` | coluna do kanban: header (eyebrow + título 13px/800 + contador), body com hooks de drag/drop e empty state |
| `ax_filter_form` | formulário de filtros de listagem (com reset/submit) |
| `ax_filter_section` / `ax_filter_check` | seções e checks de filtro no inspector |
| `ax_pagination` / `ax_pagination_summary` | paginação padronizada de listagens |
| `ax_empty_state` | estado vazio contextual |

Cards de conteúdo, colunas de kanban e KPIs **nunca** devem ser markup solto: usar
sempre `ax_operational_panel`, `ax_board_column` e `ax_metric_card`. O header desses
componentes já resolve fundo destacado (`#f8fafc`) e título compacto (13px/800)
vencendo a regra global `.ax-app h2`.

Quando uma tabela, gráfico ou lista entra dentro de `ax_operational_panel`, a
distância entre header e conteúdo pertence ao componente compartilhado. Não
colar `ax-table-wrap` no header e não criar `tw-mt-*` local para cada tela.
Se uma tabela parecer colada no header do painel, corrija o componente/variação
do painel ou o wrapper compartilhado, não a tela com margem avulsa. O padrão
visual esperado é: header compacto, linha divisória sutil, body com respiro
interno previsível e tabela/lista começando como conteúdo do body.

Badges de contagem dentro de painéis operacionais precisam ser curtos e densos:
prefira `Avaliadas 39`, `Criadas 0`, `Indexáveis 37` em vez de textos longos
com dois-pontos pesados. Use `ax_badge` puro antes de qualquer classe local,
mantendo a mesma escala visual dos KPIs, regras automáticas e coluna Score. Se o
badge compartilhado não atender uma necessidade real, evolua o componente
compartilhado em vez de criar variação local para uma tela. O peso do texto do
badge pertence ao `.ax-badge` global; não compensar com CSS por tela.
Não escrever `<span class="ax-badge ...">` manualmente em tela migrada: use o
helper para manter API, tons, dot e classes em uma única primitive.

Textos visíveis nunca devem expor nomes técnicos de banco/controller, como
`property_show`, `landing_pages_show`, `home_index` ou fallback `Seo settings`.
Crie mapas de apresentação no model/helper ou `content_for`/títulos explícitos
na contextbar. URL, params e `href` podem manter nomes técnicos; labels,
breadcrumbs, gráficos, legendas, badges e células visíveis devem estar em pt-BR.

## Componentes De WhatsApp

O atendimento WhatsApp é produto operacional, não um CRUD comum. A conversa deve
usar os componentes compartilhados abaixo em todos os pontos de entrada:

- inbox dedicado: `app/views/admin/whatsapp_inbox/index.html.erb`;
- thread reutilizável: `app/views/admin/whatsapp_inbox/_thread_workspace.html.erb`;
- bolha/mídia: `app/views/admin/whatsapp_inbox/_message_bubble.html.erb`;
- bloco dentro do lead: `app/views/admin/shared/ui/_lead_whatsapp_panel.html.erb`;
- composer: `app/views/admin/shared/ui/_whatsapp_composer.html.erb`.

Regras:

- não criar cards de conversa paralelos dentro de telas de lead, inbox ou campanha;
- reaproveitar `thread_workspace`, `message_bubble` e `whatsapp_composer` sempre
  que uma tela precisar mostrar ou responder uma conversa;
- o composer compacto deve ser uma barra única: anexar/modelo à esquerda, texto
  no centro e enviar à direita, sem toolbar explicativa ocupando altura;
- a timeline deve ter rolagem interna; a página não deve crescer além da viewport
  no inbox operacional;
- imagem, vídeo, áudio e documento devem abrir no viewer inline da conversa, sem
  navegar para outra página;
- áudio não deve carregar metadata nem tocar sozinho ao entrar na tela; carregar
  `src` apenas por ação explícita do usuário;
- ActionCable é o caminho principal para novas mensagens e status. Qualquer
  reconciliação HTTP deve ser manual/fallback, nunca polling visual que pisca,
  troca seleção ou exibe overlay de carregamento;
- status de mensagem (`pending`, `sent`, `delivered`, `read`, `failed`) deve
  atualizar na bolha existente sem refresh e sem re-renderizar a fila inteira;
- ações redundantes como "Abrir inbox" ou "Abrir WhatsApp" não devem aparecer
  quando a própria fila/thread já resolve seleção e navegação.

Se uma diferença visual aparecer entre `/admin/atendimento/whatsapp/:id`,
`/admin/atendimento/whatsapp/:id?workspace=focus` e `/admin/leads/:id`, corrija
o componente compartilhado ou sua variação (`compact_mode`) em vez de CSS local
por tela.

## Botões

O design system de referência usa botões compactos:

- botão de toolbar com altura visual próxima de `28px`;
- botão de ação normal com altura próxima de `30px`;
- raio `6px`;
- foco sutil com `--admin-primary-ring`;
- primário sempre em `--admin-primary`.
- botões da contextbar usam a escala compacta (`28px`) e devem alinhar com o
  breadcrumb/estado da `ax-contextbar__main`.
- variantes oficiais: `primary`, `secondary`, `ghost`, `danger`, `success`,
  `warning` e `info`; todas precisam manter contraste em estado normal, hover,
  foco, visited e disabled.
- ícones internos devem usar `.ax-ico` e herdar `currentColor`.

No admin Rails:

```erb
<%= ax_button "Salvar", nil, variant: :primary, type: "submit" %>
<%= ax_button "Cancelar", admin_habitations_path %>
<%= ax_icon_button label: "Voltar", icon: "arrow-left", url: admin_habitations_path %>
```

Não criar classes locais de botão quando `ax_button` ou `ax_icon_button` cobrir o
caso. Evolua o helper antes de duplicar. Não criar CSS local para tamanho,
padding, hover, foco ou cor de botão; se faltar uma intenção visual, adicionar a
variante no componente compartilhado.

## Inputs, Selects E Autocomplete

Padrão visual:

- altura base de `32px`;
- borda `--ab-field-border`;
- hover em `--ab-field-hover`;
- foco em `--ab-field-focus` com ring sutil;
- radius `7px`;
- labels compactos;
- tooltip por ícone de info quando o texto auxiliar for explicativo.

Regras:

- Use `ax_field_label` com `tooltip:` em vez de legenda permanente.
- `TomSelect` deve herdar o tema mesmo quando o dropdown renderiza no `body`.
- Multi-select deve quebrar linha quando os chips atingirem a extremidade.
- Grupos com prefixo/sufixo devem usar `ax_input_group`.
- Dados readonly devem virar `ax_info_badge` quando não precisam submeter.
- Se o valor precisa persistir, mantenha hidden/input real e use badge apenas
  como camada visual.

## Cadastro De Imóveis

O cadastro de imóveis é um Master-Detail dentro do workspace:

```text
ax-workspace
├── ax-main
│   ├── header operacional do imóvel
│   ├── ax_form_section
│   ├── ax_form_section
│   └── ax_sticky_action_footer
└── ax-aside
    └── Editor do imóvel
        ├── abrir por código
        └── navegação por áreas/abas
```

Regras específicas:

- Escopo atual: `/admin/habitations/:slug/edit` e `/admin/habitations/new`.
- Preservar abas, submits, permissões, strong params, campos e auditoria.
- Uma aba/pane visível por vez.
- O `Editor do imóvel` é estrutura de `ax-aside`, não conteúdo dentro do `ax-main`.
- Botão `+` de empreendimento deve ficar desabilitado em imóvel novo quando a
  unidade ainda não existe para vínculo; explicar via tooltip.
- Se criar empreendimento a partir de uma unidade, levar `source_habitation_id`
  e vincular no backend após salvar.
- `status comercial = Suspenso` controla a visibilidade do motivo de suspensão.
- Organização das abas do cadastro:
  `Base` concentra identificação, classificação, vínculo e endereço;
  `Estrutura` concentra dimensões físicas, vagas, face/topografia e atributos;
  `Empreendimento` concentra dados do edifício e infraestrutura/lazer;
  `Comercial` concentra valores, negociação, comissão, chaves, visitas e contatos;
  `Publicação` concentra texto público, portais e SEO;
  `Mídia` e `Documentos` ficam isoladas por fluxo operacional.

## Variações Do Aside Direito

`ax-aside` é a estrutura compartilhada da coluna direita. O comportamento interno
muda por tela, mas o alinhamento, colapso, largura, sticky e separação de `ax-main`
pertencem ao shell.

Variações aceitas:

- `Inspector de filtros`: usado em listagens, com campos de filtro, botões e grupos
  recolhíveis. Não usa navegação por ícones quando recolhido.
- `Editor navegável`: usado no cadastro de imóveis, com `rail_body` e ícones
  clicáveis para trocar de aba/área quando recolhido.
- `Painel informativo`: usado em telas de configuração ou preview, com header/body
  dinâmicos e sem obrigação de navegação.

Regra prática: não duplicar a estrutura da coluna. Mude o body/header/comportamento
passado para `ax_aside_panel`, mas mantenha `ax-main` e `ax-aside` como irmãos.

## Quick Modals

Cadastros rápidos devem usar:

```text
ax_quick_modal
ax-quick-create
ax_field_grid
ax_text_field / ax_select_field
ax_inline_notice
```

Não usar:

```text
modal fade
modal-dialog
modal-content
alert alert-danger
form-control como contrato público novo
row / col como layout de formulário migrado
```

Compatibilidade temporária pode existir dentro do componente somente enquanto o
comportamento legado ainda estiver sendo substituído. Ela não deve aparecer como
contrato público da tela migrada.

Tamanhos oficiais:

| Classe | Uso | Largura alvo |
| --- | --- | --- |
| `ax-quick-modal--sm` | confirmação, ajuste simples, escolha curta | `460px` |
| `ax-quick-modal--md` | cadastro rápido comum | `620px` |
| `ax-quick-modal--lg` | estratégia, exportação, configurações com textarea/tabela | `920px` |

Controles dentro de quick modal devem ser compactos e específicos do contexto.
Não reutilizar `.custom-checkbox-card` legado quando ele inflar padding, altura
ou quebrar labels. Para opções booleanas em modal, preferir um grid curto com
labels clicáveis, checkbox nativo preservado e classes escopadas da tela; se o
padrão aparecer em duas telas, promover para um componente `ax_*`.

Textarea técnico em modal (prompt, estratégia, JSON, observação longa) deve ter
altura explícita, `resize: vertical`, fonte menor e line-height confortável. Não
usar a escala gigante herdada de editor/campo legado.

## Aside Reutilizável

Todo painel direito deve reutilizar a mesma estrutura:

```text
ax_aside_panel
├── header dinâmico
│   ├── título
│   ├── token/contador
│   └── toggle
└── body dinâmico
```

Conteúdos possíveis:

- filtros do catálogo;
- editor do imóvel;
- mapa de impacto;
- preview de configuração;
- propriedades de seleção;
- configurações contextuais.

O conteúdo muda; a estrutura não.

## Padrões De Interação

- Use `ax-disclosure` para seções colapsáveis.
- Use `ax-tabs` para abas do novo layout.
- Use `ax-modal`/`ax_quick_modal` para modais migrados.
- Use `ax-async-download` para downloads de arquivos acionados dentro do admin.
- Use `ax-confirm-submit` para confirmação destrutiva.
- Use `ax-tooltip` ou `ax_field_label(tooltip:)` para ajuda contextual.
- Evite `window.alert`, `window.confirm`, scripts inline e dependência visual de
  Bootstrap em áreas já migradas.

## Downloads Assíncronos

Downloads acionados dentro do admin devem usar o controller reutilizável:

```text
ax-async-download
```

Use para links ou botões que baixam CSV, PDF, ZIP, XLSX, relatórios ou anexos
sem navegar a página, sem acionar Turbo e sem disparar o preloader global.

Contrato mínimo:

```erb
<%= link_to arquivo_path,
            class: "ax-icon-btn",
            title: "Baixar",
            download: filename,
            data: {
              controller: "ax-async-download",
              action: "ax-async-download#download",
              turbo: false,
              admin_navigation_ignore: true
            } do %>
  <i class="bi bi-download"></i>
<% end %>
```

Para links com texto, informe `loading_text`:

```erb
<%= link_to "Baixar relatório",
            arquivo_path,
            class: "ax-btn",
            download: filename,
            data: {
              controller: "ax-async-download",
              action: "ax-async-download#download",
              ax_async_download_loading_text_value: "Baixando...",
              turbo: false,
              admin_navigation_ignore: true
            } %>
```

Regras:

- o endpoint deve responder com `Content-Disposition: attachment` quando possível;
- o link deve manter `download` como fallback sem JS;
- não duplicar lógica de `fetch`/blob em controllers de tela;
- controllers específicos, como exportação assíncrona, apenas geram o link com
  `ax-async-download`;
- o controller emite `ax-async-download:start`, `ax-async-download:success`,
  `ax-async-download:error` e `ax-async-download:finish` para telas que precisem
  reagir.

## Anti-Padrões

Não fazer:

- colocar `ax-aside` dentro do `ax-main`;
- criar card dentro de card para resolver espaçamento;
- usar texto auxiliar permanente quando tooltip resolve;
- criar input group manual com bordas duplicadas;
- usar `row`, `col`, `form-group`, `card`, `alert`, `badge`, `btn` Bootstrap em
  área já migrada;
- manter markup manual equivalente a primitive `ax-*` já existente;
- criar CSS local para resolver elemento que deveria virar componente
  compartilhado;
- criar controller Stimulus específico de tela quando um controller `ax-*`
  genérico resolve;
- usar nomes de marca/imobiliária específica em código genérico do sistema;
- mexer no site público ao ajustar tema do admin.

## Playbook De Migração

1. Identifique comportamento real: rota, controller, params, permissões, submits,
   hidden fields, callbacks JS, uploads e auditoria.
2. Separe comportamento de apresentação.
3. Escolha o componente `ax-*` equivalente.
4. Se o componente não cobre o caso, evolua o componente.
5. Substitua o markup legado.
6. Remova classes/scripts antigos que ficaram sem função.
7. Valide no browser local.
8. Rode checks proporcionais ao risco.

## Checklist Antes De Entregar

- A tela ainda executa o fluxo principal anterior?
- Permissões e strong params foram preservados?
- `ax-contextbar`, `ax-sidebar` e `ax-aside` continuam alinhados?
- A tela usa `--ax-shell-gutter: 12px` sem compensações locais conflitantes?
- `ax-main` e `ax-aside` continuam irmãos dentro de `ax-workspace`?
- A tela usa `--admin-primary: #365f8f` como default?
- Não houve impacto no site público?
- Textos visíveis, breadcrumbs, gráficos, badges e células estão em pt-BR?
- A tela não expõe nomes técnicos (`controller_name`, `page_type`, params ou
  fallback `humanize`) como label de usuário?
- Painéis com tabela/lista/gráfico têm respiro entre header e body sem margem
  local improvisada?
- Badges e chips estão compactos o suficiente para tela operacional?
- Quick modals usam controles compactos e não herdaram cards/inputs legados
  inflados?
- Houve chance clara de componentizar ou substituir legado equivalente e isso
  foi feito no mesmo ciclo?
- Uma aba/pane aparece por vez?
- Inputs, selects, TomSelect e input groups têm mesma altura/radius/foco?
- Avisos explicativos viraram tooltips ou `ax_inline_notice`?
- Confirmações destrutivas não usam `window.confirm`?
- Uploads e documentos preservam ids, data attributes e submits?
- `assets:precompile` foi executado quando CSS/JS mudou?
- `zeitwerk:check` foi executado quando Ruby/helpers/views mudaram?
- Smoke visual no Atlas/in-app browser foi feito quando houve mudança de layout.

## Mapa Atual De Componentes

```text
app/views/admin/shared/ui
├── _aside_panel.html.erb
├── _attachment_item.html.erb
├── _badge.html.erb
├── _chip_grid.html.erb
├── _currency_field.html.erb
├── _date_field.html.erb
├── _dynamic_list_field.html.erb
├── _empty_state.html.erb
├── _error_summary.html.erb
├── _field.html.erb
├── _field_grid.html.erb
├── _field_group.html.erb
├── _field_label.html.erb
├── _file_upload_button.html.erb
├── _filter_form.html.erb
├── _form_actions.html.erb
├── _form_section.html.erb
├── _info_badge.html.erb
├── _inline_notice.html.erb
├── _input_group.html.erb
├── _lead_whatsapp_panel.html.erb
├── _measure_field.html.erb
├── _media_grid.html.erb
├── _media_source_notice.html.erb
├── _media_tile.html.erb
├── _media_upload_panel.html.erb
├── _metric_card.html.erb
├── _multiselect_field.html.erb
├── _number_field.html.erb
├── _operational_panel.html.erb
├── _page_header.html.erb
├── _panel.html.erb
├── _portal_publication_option.html.erb
├── _portal_publication_section.html.erb
├── _quick_modal.html.erb
├── _radio_group.html.erb
├── _record_item.html.erb
├── _relationship_select.html.erb
├── _select_field.html.erb
├── _sticky_action_footer.html.erb
├── _text_field.html.erb
├── _toggle_chip.html.erb
├── _whatsapp_composer.html.erb
└── _workspace_shell.html.erb
```

```text
app/javascript/controllers
├── ax_async_download_controller.js
├── ax_checkbox_chips_controller.js
├── ax_confirm_submit_controller.js
├── ax_disclosure_controller.js
├── ax_drawer_controller.js
├── ax_dropdown_controller.js
├── ax_form_hints_controller.js
├── ax_modal_controller.js
├── ax_quick_create_controller.js
├── ax_tabs_controller.js
└── ax_tooltip_controller.js
```

## Próximas Extrações Recomendadas

- Migrar quick modals restantes para `ax_quick_modal` completo.
- Reduzir `form-control`, `row`, `col`, `alert` e `btn` remanescentes dentro do
  cadastro de imóveis.
- Consolidar selects relacionais e multiselects no mesmo contrato visual.
- Criar exemplos pequenos de cada componente em uma página interna de referência
  se a equipe precisar testar visualmente os primitives sem abrir telas reais.
