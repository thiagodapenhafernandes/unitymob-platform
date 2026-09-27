# Instruções do Projeto

## Deploy

- Referência completa por alvo: `docs/deploys.md`.
- `all` publica apenas Salute e Conexão. Central e Gateway são independentes.
- `$fazer_deploy central`: usar Mina em `central/`, com `CENTRAL_HOST=167.99.239.17`.
- `$fazer_deploy gateway`: usar o procedimento Docker Compose de `docs/deploys.md`, não Mina.

- O deploy de produção deste projeto é feito com Mina multistage.
- Para a Salute, usar:
  `rvm 3.2.3 do bundle exec mina saluteimoveis deploy`
- Para todos os stages configurados, usar:
  `rvm 3.2.3 do bundle exec mina all deploy`
- Não usar `mina production deploy`: este projeto não define um stage `production`.
- O stage `saluteimoveis` está em `config/deploy/saluteimoveis.rb`:
  branch `master`, servidor `143.110.138.67`, path `/home/salute/deploy`.
- O repositório de deploy é central:
  `git@github.com:thiagodapenhafernandes/unitymob-platform.git`.

## Prevenção de regressões

- Ao implementar uma demanda específica, preserve ativamente o comportamento existente de funcionalidades não diretamente relacionadas.
- Antes de alterar código, identifique fluxos adjacentes que possam ser afetados indiretamente, como listagens, filtros, permissões, salvamento, upload, visualização, auditoria, integrações e deploy.
- Evite refatorações oportunistas, mudanças globais ou simplificações fora do escopo da demanda. Se uma alteração indireta for necessária, explique o motivo e valide o impacto.
- Prefira mudanças estreitas e compatíveis com os padrões atuais do projeto, mantendo regras de negócio existentes para categorias, perfis, status e fluxos que não fazem parte da solicitação.
- Ajuste ou adicione testes proporcionais ao risco, cobrindo o caso novo e pelo menos os comportamentos vizinhos que poderiam regredir.
- Antes de entregar, rode validações relevantes para o escopo alterado e cite claramente o que foi validado. Se algum teste/check não puder ser executado, explique o motivo.
- Em deploys, valide também rotas críticas e fluxos próximos, não apenas a tela ou endpoint diretamente alterado.

## Componentização obrigatória do admin

- Antes de criar ou alterar uma função, regra de negócio, bloco visual ou comportamento de interface, verifique se o mesmo padrão já existe no projeto e reutilize ou evolua esse ponto compartilhado.
- Quando uma função, partial, helper, service, componente Stimulus ou bloco de layout tiver uso atual ou previsível em mais de uma tela, extraia para uma camada compartilhada na mesma implementação. Evite duplicar primeiro para "organizar depois".
- Todo padrão visual ou comportamental com potencial de reutilização deve ser criado ou ajustado na camada compartilhada (`ax-*`, `app/views/admin/shared/ui`, `Admin::UiHelper`, componentes CSS e controllers `ax_*`) já na primeira ocorrência. Não aguarde uma segunda tela e não deixe cópia local como etapa intermediária.
- Em qualquer UI nova ou ajuste de tela admin, revise explicitamente o ritmo visual antes de entregar: espaçamento vertical entre seções, gap entre label e controle, respiro interno de cards/painéis, distância entre grupos funcionais e alinhamento em mobile. Não use marcação manual para checkbox/switch/select quando existir helper/componente `ax-*`; prefira `ax_switch_field`, `ax_check_field`, `ax_field_grid`, `ax_field_group`, `ax_operational_panel` e equivalentes.
- Regras de domínio compartilhadas devem ficar em model, concern, service ou helper apropriado, não espalhadas em controllers/views/Stimulus.
- CSS ou markup específico de página só é aceitável para composição ou geometria comprovadamente exclusiva, deve estar namespaced e não pode duplicar estado, aparência ou comportamento de primitive compartilhada.
- Se um segundo consumidor surgir, promova o padrão para a camada compartilhada na mesma mudança e remova as versões locais.

## Navegação mobile em telas específicas

- No mobile/PWA/app nativo, sempre que o usuário entrar em uma tela específica que não seja uma listagem principal, use o header compacto de detalhe: ação de voltar à esquerda, título/contexto centralizado no meio e uma ação, estado ou indicador relevante à direita.
- Esse header deve respeitar `safe-area` do iPhone e substituir visualmente o cabeçalho administrativo padrão no mobile, evitando sobreposição com status bar, navbar, breadcrumb ou contextbar.
- Listagens principais podem manter seus headers próprios de busca/filtro/tabs; telas de detalhe, formulário, acompanhamento, fila, agenda, proposta ou qualquer drill-down operacional devem seguir o padrão compacto.

## Site público e temas

Referência completa: `docs/public-theme-contract.md`. Esta seção é o resumo obrigatório.

- Toda mudança em tela, componente, CSS ou comportamento do site público vale para **todos** os temas de `app/assets/stylesheets/public_site_themes/` (hoje `default`, `saluteimoveis`, `conexaoimobiliaria`, `salute_luxury`), cada um na sua identidade visual. Nunca só o tema citado no pedido.
- A regra vale para temas futuros: tema novo entra no padrão com o próprio CSS. Não crie condição ou trava que funcione só para os temas atuais (nada de `if tema == ...` no markup compartilhado).
- Um HTML por componente em `app/views/public_theme/components/`, com classes `public-theme-<componente>__*` e a variante como sufixo `--<variante>` (`default` ou `salute-luxury`). Tema com desenho próprio registra partial em `Tenant::PUBLIC_SITE_THEME_METADATA[:components]` e emite as mesmas classes. Apelidos de tema (`.sl-*`) só aparecem no CSS do tema, agrupados no seletor.
- Estilo da variante `default` (Padrão, Salute, Conexão) fica em `app/assets/stylesheets/components/_public_theme_*.scss`, usando a paleta da conta (`--color-primary`, `--color-secondary`, `--color-accent`). A variante luxury fica em `public_site_themes/salute_luxury.css`.
- O que existe num tema e falta em outro deve ser replicado na mesma entrega. Ao entregar, dê o veredito por tema: ajustado, ou já coberto sem mudança.
- Contas novas nascem no tema `default` (padrão da coluna `tenants.public_site_theme` e fallback em `Tenant#public_site_theme_key`).
- Validação obrigatória ao mexer no site público: `bundle exec rspec spec/requests/public_themes_contract_spec.rb spec/views/public_theme spec/lib` (o primeiro percorre todos os temas cadastrados, inclusive os que forem criados depois) e `npm run build:css` quando houver SCSS.
