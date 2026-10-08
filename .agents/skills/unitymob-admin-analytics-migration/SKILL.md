---
name: unitymob-admin-analytics-migration
description: Use quando o usuario pedir para migrar, refinar, padronizar ou continuar telas do admin Rails em /Users/thiagodap.fernandes/worksapces/unitymob-crm para o conceito Analytics Builder / Dense Enterprise Workspace; inclui dashboard, menu, sidebar, contextbar, habitations, filtros como inspector, drawers, formularios, tabelas, cards, menus, submenus, motion/transicoes e remocao gradual de Bootstrap sem regressao.
---

# Unitymob Admin Analytics Migration

## Objetivo

Migrar o admin do Unitymob CRM para um padrao operacional denso, corporativo e produtivo inspirado em Analytics Builder, Power BI, Power Query, Figma/IDE e sistemas enterprise.

Aplicar o conceito, nao copiar literalmente o mock de `public/analytics-builder-design-system`. A migracao deve preservar o dominio Rails, os fluxos existentes e o comportamento de cada modulo, substituindo a camada visual e de interacao por componentes consistentes.

## Principios

- Manter Rails CRUD, views, partials, Turbo/Stimulus e helpers existentes quando ainda forem a implementacao mais simples e atual do projeto.
- Migrar por tela ou por area funcional, sem refatoracao global oportunista.
- Preservar comportamento, filtros, permissoes, parametros, retornos, paginacao, exportacao, links e acoes existentes.
- Usar o design system `ax-*` como base: `ax-navbar`, `ax-sidebar`, `ax-contextbar`, `ax-main`, `ax-panel`, `ax-btn`, `ax-menu`, `ax-disclosure`.
- Usar os tokens fonte de `public/analytics-builder-design-system` como referencia de tema. A cor primaria padrao do novo admin e `--admin-primary: #365f8f`; nao usar o azul legado `#2563EB` como default do layout migrado.
- Priorizar alta densidade de informacao com baixa carga cognitiva: mais contexto na tela, menos espaco desperdicado, hierarquia limpa.
- Usar tema claro, neutro e corporativo; evitar visual de landing page, cards decorativos excessivos, gradientes e espacos vazios.
- Remover Bootstrap e CSS customizado legado gradualmente conforme cada area for migrada. Compatibilidade temporaria so deve existir como ponte para telas ainda nao migradas, nunca como base visual reaproveitada no novo layout.
- Ao migrar uma area para o novo layout, reduzir tambem Bootstrap/Stimulus legado acoplado ao visual antigo. Preservar comportamento e contratos Rails, mas preferir primitives `ax-*`, CSS escopado e controllers simples/atuais em vez de manter controllers antigos apenas para sustentar markup legado.
- Quando um novo componente/padrao do design system substituir bem a funcao antiga, remover o bloco legado correspondente em vez de apenas esconder, duplicar ou empilhar interfaces. A migracao deve limpar codigo e reduzir superficie visual, preservando comportamento.
- Todo padrao visual ou comportamental com potencial de reutilizacao deve nascer ou ser promovido como primitive compartilhada `ax-*` ja na primeira ocorrencia. Nao aguardar uma segunda tela e nao manter uma versao local como etapa intermediaria.
- CSS/markup de pagina so pode permanecer para composicao ou geometria comprovadamente exclusiva do dominio, sempre namespaced e sem duplicar aparencia, estado ou comportamento de componente compartilhado. Se surgir outro consumidor, promover na mesma rodada.
- Validar visualmente no browser local quando houver mudanca de layout/interacao.

## Arquitetura Visual

Estruturar telas operacionais em:

```text
Topbar fixa
Contextbar: breadcrumb/estado no lado esquerdo, acoes do modulo no lado direito
Explorer/sidebar persistente a esquerda
Workspace/conteudo principal no centro
Inspector/drawer contextual a direita quando a tela tiver filtros, propriedades ou configuracoes
Painel inferior opcional para query, logs, historico, exportacao ou acoes tecnicas
```

### Contrato Estrutural Reutilizavel

O admin migrado deve usar 5 componentes estruturais visiveis como contrato base:

```text
ax-topbar
ax-contextbar
ax-sidebar
ax-main
ax-aside
```

`ax-main` e `ax-aside` devem ser filhos de um mesmo shell de workspace, para que a coluna direita seja estruturalmente independente do conteudo central:

```text
ax-admin-shell
├── ax-topbar
├── ax-contextbar
└── ax-admin-body
    ├── ax-sidebar
    └── ax-workspace
        ├── ax-main
        └── ax-aside [opcional]
```

Regra de alinhamento: `ax-contextbar`, cabecalho da `ax-sidebar` e cabecalho da `ax-aside` precisam compartilhar a mesma regua vertical imediatamente abaixo da `ax-topbar`. A `ax-aside` nunca deve nascer dentro do fluxo do `ax-main`; ela deve ser irma do `ax-main` dentro de `ax-workspace`. O conteudo da coluna direita muda por tela (`Filtros do catalogo`, `Editor do imovel`, preview, mapa de impacto), mas a estrutura, largura, colapso, sticky/top e overflow pertencem ao componente compartilhado.

### Regua De Espacamento

O admin migrado deve usar um gutter unico de shell:

```text
--ax-shell-gutter: 12px
--ax-workspace-gutter: var(--ax-shell-gutter)
```

`ax-navbar`, `ax-contextbar`, cabecalho da `ax-sidebar`, `ax-main` e cabecalho da `ax-aside` devem compartilhar essa regua lateral. Em telas master-detail, o body do `ax-main` e o header/body do `ax-aside` devem herdar `--ax-workspace-gutter`. Nao criar compensacoes locais com `18px`, `.75rem`, `0`, margins negativas ou padding em componente interno para corrigir desalinhamento do shell. Se uma tela precisar de outra densidade, crie uma variacao explicita do shell por token, nao um ajuste solto por tela.

Nao transformar todo modulo em "dashboard builder". Usar a linguagem do Analytics Builder, mas respeitar o tipo da tela:

- Dashboard: KPIs, graficos e listas compactas.
- Listagem CRUD: tabela/lista operacional + filtros no inspector.
- Catalogo de imoveis: manter conceito do card de imovel, ajustar o entorno.
- Formularios: grupos compactos, secoes colapsaveis e acoes persistentes.
- Auditorias/logs: tabela densa, filtros proximos, detalhe contextual quando util.

## Fluxo de Migracao

1. Entender a tela atual antes de mexer:
   - rotas, controller, params, filtros, partials, helpers, permissoes e JS envolvidos;
   - elementos que nao podem regredir: busca, paginacao, ordenacao, exportacao, selecao, bulk actions, links de retorno.

2. Separar o que e comportamento do que e apresentacao:
   - manter regras de negocio em controllers/models/helpers;
   - mover so a composicao visual para classes/componentes `ax-*`;
   - nao trocar fluxo Rails por SPA.

3. Aplicar o shell do conceito:
   - sidebar/explorer persistente a esquerda;
   - contextbar imediatamente abaixo da topbar;
   - breadcrumb/estado no lado esquerdo da contextbar;
   - acoes do modulo no lado direito da contextbar;
   - conteudo principal sem cabecalhos duplicados grandes.

4. Refatorar o conteudo:
   - trocar headers grandes por blocos compactos;
   - reduzir cards decorativos;
   - usar paineis com borda sutil e header funcional;
   - colocar filtros/propriedades em inspector quando forem configuracoes frequentes.

5. Refatorar interacoes:
   - drawers, sidebar, dropdowns e submenus devem abrir/fechar suavemente;
   - arrows de accordions/submenus devem girar conforme estado;
   - botoes inativos precisam parecer clicaveis, com borda/hover claros;
   - foco de inputs deve ser sutil, sem anel exagerado.

6. Validar:
   - rodar assets quando mexer em CSS/JS;
   - abrir a tela no browser local;
   - testar abrir/fechar sidebar, inspector, dropdowns e secoes colapsaveis;
   - testar um filtro/acao real da tela alterada;
   - citar o que foi validado e o que nao foi.

## Padroes Ja Definidos

### Header e Contextbar

- Topbar fica para identidade, busca global, usuario e atalhos globais.
- `ax-contextbar` fica logo abaixo da topbar.
- Lado esquerdo: breadcrumb e estado atual da tela.
- Lado direito: acoes do modulo, por exemplo `Novo imovel`, `Exportar`, `Proprietarios`.
- Evitar um segundo header grande dentro do workspace quando a contextbar ja comunica onde o usuario esta.
- Subcabecalho do workspace deve ser compacto no estilo dashboard command: eyebrow pequeno, titulo objetivo, descricao curta apenas quando agrega, metricas/status alinhados a direita. Evitar cards grandes decorativos ou acoes duplicadas que ja vivem na contextbar.
- Em listagens, incorporar no subcabecalho as acoes auxiliares que antes ficavam em toolbars separadas quando isso reduzir ruído: selecionar filtrados, contador de selecionados, limpar, bulk action, impressao e ordenacao. A barra de selecao deve aparecer somente quando houver selecao real.

### Sidebar / Explorer

- Sidebar expandida deve ter secoes compactas e itens com iconografia clara.
- Sidebar minimizada deve centralizar os icones, sem labels quebrados.
- Evitar menus que abrem/fecham inesperadamente ao navegar.
- Submenus devem ter contraste suficiente entre ativo, hover e grupo aberto.
- Arrows de submenu devem girar conforme aberto/fechado.

### Dashboard Admin

- Aplicar densidade de dashboard operacional: KPIs compactos, graficos e listas visiveis na primeira dobra.
- Evitar hero, saudacao muito grande e espacos vazios.
- Usar cards/painels por funcao, com headers discretos e acoes proximas.

### Habitations / Imoveis

- Usar layout de 3 areas:
  - Explorer/sidebar global a esquerda;
  - catalogo/listagem no centro;
  - filtros no inspector a direita.
- A coluna da esquerda nao deve ser substituida pelos filtros; filtros pertencem ao inspector direito.
- Preservar o conceito do card de imovel, mas refatorar o entorno: toolbar, filtros, tabs, chips, paginacao e painel lateral.
- O inspector deve ficar grudado no topo, alinhado com a contextbar, e recolher para a direita como a sidebar recolhe para a esquerda.
- O titulo do inspector deve ser contextual, por exemplo `Filtros do catalogo`; evitar labels tecnicos como `PROPERTY_QUERY`.
- Categorizar filtros em secoes colapsaveis, deixando os mais usados abertos.

### Formularios de Imoveis / Master-Detail

- No cadastro/edicao de imovel (`/admin/habitations/:slug/edit`), o escopo da migracao e o main do formulario. Nao mexer em dashboard, listagem de imoveis, sidebar global, contextbar ou shell ja finalizados sem pedido explicito.
- Aplicar o conceito Master-Detail dentro do formulario:
  - workspace central com secoes compactas de campos;
  - rail direito como `Editor do imovel`, com navegacao por areas/abas, status e atalhos do formulario;
  - nao copiar literalmente o Inspector do builder; trazer o conceito de propriedades/navegacao contextual para o dominio Rails.
- Nao fazer skin sobre Bootstrap. Quando o comportamento ja estiver preservado, substituir gradualmente `row/col/form-group/card` legados por primitives densos do formulario e remover o bloco visual antigo.
- Nao perpetuar Bootstrap tabs/collapse/input-groups ou Stimulus antigo quando a area ja tiver equivalente `ax-*` mais limpo. Migrar em passos seguros: primeiro manter o contrato e o submit, depois substituir o markup/controller legado por componente simples e escopado.
- Campos devem usar grid denso, preferencialmente CSS grid de 12 colunas no escopo do formulario. Evitar gutters grandes, linhas vazias e grupos que somam mais que 12 colunas e empurram campos para a linha seguinte.
- Inputs, selects, TomSelect, multiselect, botoes acoplados (`+`, lupa, engrenagem), input-group addons e chips devem compartilhar altura, radius, borda, foco e alinhamento vertical.
- Textos auxiliares neutros nao devem ocupar linha permanente. Usar tooltip acionado por icone de info ao lado do label do campo; manter status operacional, sucesso e erro visiveis.
- Checkboxes do cadastro devem usar chips sutis no padrao `ax_toggle_chip`/`custom-checkbox-card`: pill compacto, bolinha/check interna, estado ativo verde discreto e label curto.
- Informacoes readonly/disabled que sao apenas referencia devem virar badges informativos quando nao precisarem submeter valor. Se precisarem persistir/submeter, manter o input/hidden correspondente e exibir o badge como camada visual.
- Secoes do formulario devem ser compactas, com header funcional, eyebrow discreto e acoes proximas. Evitar subcabecalhos grandes, cards dentro de cards e textos explicativos visiveis que repetem o label.
- Ao ajustar uma aba, varrer as demais abas do mesmo formulario para nao deixar padroes conflitantes entre Visao geral, Caracteristicas, Infraestrutura, Comercial, Midia, Documentos e SEO.
- Preservar comportamento Rails existente: nomes de campos, hidden fields, strong params, uploads, submits, retorno, permissoes, auditoria, TomSelect, modais de relacionamento e controllers Stimulus.
- Validacao minima para esse formulario: `zeitwerk:check`, `assets:precompile`, reload no Atlas/in-app browser, navegacao por todas as abas, uma pane visivel por vez, console sem erros e smoke visual de alinhamento dos input-groups.

### Inputs, Selects e Autocomplete

- Inputs/selects devem compartilhar altura, radius, borda e foco.
- Focus ring deve ser sutil e corporativo.
- Grupos de inputs precisam encaixar sem bordas duplicadas estranhas.
- Selects com autocomplete/multiselect nao podem empurrar o layout nem ficar cortados por `overflow: hidden`; dropdown deve sobrepor quando necessario.
- Tom Select deve herdar o tema da tela mesmo quando o dropdown for renderizado no `body`: option ativa/hover em tons neutros, foco sem azul forte, input de busca com a mesma borda dos campos e chips multi-select discretos.
- Badges e chips devem alinhar verticalmente com texto.

### Componentes Compartilhados

Primitives do novo admin devem viver em `app/views/admin/shared/ui` com helpers em `Admin::UiHelper`. Antes de duplicar markup, verificar se ja existe componente `ax-*` equivalente.

Componentes estruturais atuais:

- `ax_workspace_shell`: `ax-main` + `ax-aside` como irmaos estruturais.
- `ax_aside_panel`: coluna direita reutilizavel com rail recolhido, header, token/contador, toggle e body dinamico.
- `ax_sticky_action_footer`: footer persistente com meta a esquerda e acoes a direita.

Componentes de formulario atuais:

- `ax_field_label`: label padronizado com tooltip por icone de info e `meta:` opcional para contador, unidade ou estado curto; `ax_text_field` expoe esse conteudo por `label_meta:`.
- `ax_field_group`: subgrupo interno de campos dentro de uma secao, substituindo `h6`/classes Bootstrap locais sem criar card dentro de card.
- `ax_field_grid`: container de grid de campos em formularios migrados, substituindo `row/col` Bootstrap por spans `ax-span-*`.
- `ax_chip_grid`: container de listas compactas de chips/checkboxes, substituindo `row-cols` Bootstrap e preservando labels clicaveis e params Rails.
- `ax_inline_notice`: aviso curto dentro de secoes, substituindo `alert` Bootstrap quando nao houver acao complexa.
- `ax_input_group`: prefixo/sufixo/acao acoplada sem borda duplicada.
- `ax_text_field` e `ax_select_field`: wrappers para campos simples; `ax_text_field` deve preservar o tipo semantico solicitado (`email`, `url`, `password`, `number`, `tel`, `search`, `datetime-local` ou `textarea`) e funcionar tanto com model quanto com `form_with scope:`.
- `ax_standalone_field`: input ou textarea sem model para OTP, senha de confirmacao, testes e parametros top-level, com label, hint e acao acoplada via `ax_input_group`.
- `ax_standalone_select_field`: select simples ou agrupado sem model para parametros top-level, com nome, selecao, atributos das opcoes, opcao vazia e hint preservados.
- `ax_relationship_select`: select relacional com autocomplete/TomSelect e acao acoplada para criar/vincular registros.
- `ax_currency_field`: campo monetario com prefixo `R$`, mascara e targets preservados no input.
- `ax_number_field`: campo numerico compacto para quantidades, anos, posicoes e percentuais; aceita hint opcional e builders com ou sem model.
- `ax_date_field`: campo de data compacto, alinhado a inputs/selects do layout.
- `ax_measure_field`: campo numerico com sufixo de unidade (`m2`, `%`, etc.) sem repetir input group.
- `ax_range_field`: faixa numerica com label, output associado, hint, estados light/dark e hooks Stimulus no input.
- `ax_info_badge`: badge informativo compacto para dados somente leitura.
- `ax_multiselect_field`: TomSelect multi com manager opcional.
- `ax_toggle_chip`: checkbox visual em pill compacto.
- `ax_radio_group`: opcoes exclusivas em pills compactos, preservando `name`, `value`, submit Rails e `input_data` para interacoes Stimulus.
- `ax_dynamic_list_field`: listas dinamicas simples para valores repetiveis, usando Stimulus atual e params Rails preservados.
- `ax_file_upload_button`: acionador visual padronizado para `file_field`/uploads, mantendo ids, direct upload e data attributes existentes.
- `ax_attachment_item`: item compacto para anexos internos/downloads, preservando link, preview, tamanho e acoes de remocao sem `list-group`/badges Bootstrap.
- `ax_media_source_notice`: aviso compacto para origem/vinculo de midia, com icone, texto e acao opcional sem `alert` Bootstrap.
- `ax_media_upload_panel`: painel compacto de upload de midia para classificacao, dropzone, watermark, feedback e hidden fields de ordenacao/remocao sem `row/col`, `alert` ou `d-flex` Bootstrap.
- `ax_media_grid`: container da galeria/preview de fotos, preservando `data-photo-upload-target="previewContainer"` e substituindo `row/col` Bootstrap por `ax-media-grid__item`.
- `ax_media_tile`: tile reutilizavel para fotos da galeria do imóvel, preservando ordenacao, destaque, visibilidade no site, origem API/Vista e atributos usados por Stimulus/Sortable. Seus controles internos devem usar `ax-media-tag`/`ax-media-action`, nao `btn`/`badge`/`ratio` Bootstrap.
- `ax_portal_publication_section` e `ax_portal_publication_option`: bloco compacto de publicacao em portais, isolando collapse, checkbox principal e opcoes condicionais sem repetir markup no formulario.
- `ax_record_item`: registro compacto para listas internas de relacionamento/status, com titulo, eyebrow, meta, icone e acoes sem card Bootstrap.
- `ax_status_list`: lista descritiva compacta de pares rotulo/estado para inspectors, resumos e diagnosticos; aceita badges como valor sem repetir flex/utilitarios locais.
- `ax_quick_modal`: estrutura reutilizavel para cadastros rapidos dentro do admin, mantendo conteudo e footer dinamicos.
- `ax_form_section`: secao compacta e colapsavel.

Regra de evolucao: qualquer padrao visual ou comportamental repetivel deve ser criado ou promovido em `shared/ui`/`Admin::UiHelper`/CSS ou Stimulus `ax-*` ja na primeira ocorrencia, antes do consumo pela tela. Nao esperar duas ocorrencias. Compatibilidade com Bootstrap pode existir no componente como ponte, mas o contrato publico do novo layout deve ser `ax-*`. CSS local fica restrito a composicao/geometria realmente exclusiva e deve ser promovido na mesma rodada assim que houver outro consumidor.

### Command Menus

- Menus de acoes do subcabecalho devem usar `ax-dropdown` e visual de command menu compacto, nao listas Bootstrap soltas.
- Command menu deve ter largura controlada, `max-height` com scroll interno, header curto, itens com icone/status e estado ativo claro.
- Ao abrir um command menu, outros `ax-dropdown` abertos devem fechar para evitar sobreposicao cognitiva.
- Usar command menu para listas como impressao, ordenacao, exportacao contextual, acoes em lote e escolhas de visualizacao.
- Estado aberto precisa reativar `pointer-events: auto`, porque a camada Bootstrap compat pode deixar `.dropdown-menu` visualmente aberta mas nao clicavel.
- Para acoes GET como impressao/exportacao de relatorio, preferir `link_to` direto com query params e `target="_blank"` quando aplicavel, em vez de formularios dentro do menu.
- O `ul` do command menu deve ficar sem padding; o respiro visual deve vir de margin nos headers/itens para manter alinhamento previsivel.

### Motion

- Usar transicoes curtas e consistentes: cerca de 120ms a 240ms.
- Preferir `opacity`, `transform`, `width`, `margin-left` e `grid-template-columns` quando fizer sentido.
- Evitar trocar `display: none` no inicio da animacao; aplicar `hidden` apenas ao final quando JS controlar o componente.
- Respeitar `prefers-reduced-motion`.
- Animar sidebar, inspector, dropdowns, drawers, submenus e accordions sem criar gaps visuais.

## O Que Evitar

- Nao replicar o mock Analytics Builder em todas as telas como se todo modulo fosse um builder.
- Nao esconder a navegacao principal para dar lugar a filtro local.
- Nao criar hero/landing dentro do admin.
- Nao usar componentes grandes e espacados quando a tela e operacional.
- Nao introduzir SPA ou framework novo para resolver layout.
- Nao remover compatibilidade Bootstrap de uma vez se a tela ainda depende dela.
- Nao quebrar parametros existentes, links de retorno, permissoes ou filtros.
- Nao deixar elementos interativos sem cursor, hover, borda ou affordance clara.

## Checklist Antes de Entregar

- A tela ainda executa o fluxo principal anterior?
- Breadcrumb e acoes estao na contextbar correta?
- Sidebar e inspector abrem/fecham sem salto brusco?
- O conteudo principal ficou mais denso sem virar poluido?
- Filtros/configuracoes frequentes estao no inspector ou proximo do contexto?
- Inputs, selects, badges, botoes e menus seguem o padrao visual atual?
- Cada padrao repetivel encontrado foi criado/evoluido na camada compartilhada, sem copia local intermediaria?
- Todo CSS/markup que permaneceu local e geometria realmente exclusiva, namespaced e justificada?
- Mobile/responsivo nao quebra a leitura ou o acesso aos controles?
- Assets/JS/CSS foram compilados quando necessario?
- Foi feito smoke test no browser local quando houve mudanca visual?

## Como Evoluir Esta Skill

Quando um novo componente for padronizado no projeto, acrescentar uma subsecao curta em `Padroes Ja Definidos` com:

- onde o componente deve ser usado;
- comportamento esperado;
- classes/controllers preferenciais;
- riscos de regressao;
- validacao minima.
