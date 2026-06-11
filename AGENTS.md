# Instruções do Projeto

## Deploy

- O deploy de produção deste projeto é feito com Mina pela task padrão:
  `rvm 3.2.3 do bundle exec mina deploy`
- Não usar `mina production deploy`: este projeto não define uma task/stage `production`.
- O ambiente de produção já está configurado em `config/deploy.rb`:
  branch `master`, servidor `143.110.138.67`, path `/home/salute/deploy`.
- Para o fluxo `$fazer-deploy`, quando estiver em `develop`, seguir:
  `develop -> master -> mina deploy`.

## Prevenção de regressões

- Ao implementar uma demanda específica, preserve ativamente o comportamento existente de funcionalidades não diretamente relacionadas.
- Antes de alterar código, identifique fluxos adjacentes que possam ser afetados indiretamente, como listagens, filtros, permissões, salvamento, upload, visualização, auditoria, integrações e deploy.
- Evite refatorações oportunistas, mudanças globais ou simplificações fora do escopo da demanda. Se uma alteração indireta for necessária, explique o motivo e valide o impacto.
- Prefira mudanças estreitas e compatíveis com os padrões atuais do projeto, mantendo regras de negócio existentes para categorias, perfis, status e fluxos que não fazem parte da solicitação.
- Ajuste ou adicione testes proporcionais ao risco, cobrindo o caso novo e pelo menos os comportamentos vizinhos que poderiam regredir.
- Antes de entregar, rode validações relevantes para o escopo alterado e cite claramente o que foi validado. Se algum teste/check não puder ser executado, explique o motivo.
- Em deploys, valide também rotas críticas e fluxos próximos, não apenas a tela ou endpoint diretamente alterado.
