# Instruções do Projeto

## Deploy

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

- Todo padrão visual ou comportamental com potencial de reutilização deve ser criado ou ajustado na camada compartilhada (`ax-*`, `app/views/admin/shared/ui`, `Admin::UiHelper`, componentes CSS e controllers `ax_*`) já na primeira ocorrência. Não aguarde uma segunda tela e não deixe cópia local como etapa intermediária.
- CSS ou markup específico de página só é aceitável para composição ou geometria comprovadamente exclusiva, deve estar namespaced e não pode duplicar estado, aparência ou comportamento de primitive compartilhada.
- Se um segundo consumidor surgir, promova o padrão para a camada compartilhada na mesma mudança e remova as versões locais.

## Navegação mobile em telas específicas

- No mobile/PWA/app nativo, sempre que o usuário entrar em uma tela específica que não seja uma listagem principal, use o header compacto de detalhe: ação de voltar à esquerda, título/contexto centralizado no meio e uma ação, estado ou indicador relevante à direita.
- Esse header deve respeitar `safe-area` do iPhone e substituir visualmente o cabeçalho administrativo padrão no mobile, evitando sobreposição com status bar, navbar, breadcrumb ou contextbar.
- Listagens principais podem manter seus headers próprios de busca/filtro/tabs; telas de detalhe, formulário, acompanhamento, fila, agenda, proposta ou qualquer drill-down operacional devem seguir o padrão compacto.
