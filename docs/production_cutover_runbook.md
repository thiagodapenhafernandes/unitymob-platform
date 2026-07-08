# Roteiro de migração/cutover de produção

Este roteiro é para o corte em que a produção atual será migrada para a nova
versão do sistema preservando dados operacionais críticos da produção e levando
as configurações preparadas neste ambiente.

## Premissas

- Antes de qualquer alteração destrutiva, fazer backup completo do banco de
  produção em formato custom do PostgreSQL e validar que o arquivo foi gerado.
- O banco de produção atual é a fonte de verdade para dados transacionais que
  aconteceram depois da cópia local.
- O banco/local deste workspace é a fonte de verdade para configurações,
  perfis, permissões, ajustes de sistema e catálogos preparados durante a
  evolução da nova versão.
- Logs CSV de saneamento devem ser preservados em produção para auditoria.

## Dados que devem ser preservados da produção

Preservar do banco de produção atual:

- Imóveis (`habitations`) e vínculos diretamente ligados ao cadastro do imóvel,
  incluindo proprietário, corretor responsável, atribuições e fotos/anexos.
- Captações (`captacoes`) e dados relacionados ao fluxo de captação.
- Leads (`leads`) e dados relacionados ao atendimento/funil.

O objetivo é não perder movimentações reais feitas em produção enquanto o novo
sistema estava sendo ajustado localmente.

## Dados/configurações que devem vir deste ambiente

Levar deste banco/local para produção:

- Configurações globais e por conta/tenant.
- Perfis, permissões, menus e regras de acesso.
- Usuários administrativos e hierarquia quando fizer parte da configuração nova.
- Regras de distribuição e governança operacional.
- Configurações de integrações e módulos ajustados neste ambiente.
- Catálogos dinâmicos e parâmetros funcionais preparados na nova versão.

Ponto crítico: o roteiro atual em `lib/tasks/migration_rehearsal.rake` cobre
hierarquia/perfis/usuários/tenants, mas ainda não deve ser tratado como cobertura
total de todas as configurações. Antes do cutover, ampliar ou validar a exportação
das configurações restantes.

## Backup obrigatório de produção

Antes do deploy/cutover, a partir do ambiente local de manutenção:

```bash
bin/rails migration_rehearsal:pull_production_dump
```

Ou, no servidor, gerar `pg_dump --format=custom --no-owner --no-acl` usando as
credenciais reais do `.env` compartilhado.

Validações mínimas do backup:

- Arquivo existe e tem tamanho compatível.
- `pg_restore --list <arquivo.dump>` funciona.
- Caminho do arquivo registrado no checklist do deploy.

## Saneamentos obrigatórios após migrations/imports

Rodar em produção, após o schema estar atualizado e após importar/preservar os
dados necessários:

```bash
RAILS_ENV=production bundle exec rails proprietors:merge_candidates EXECUTE=1
RAILS_ENV=production bundle exec rails data_hygiene:sanitize_locations EXECUTE=1
RAILS_ENV=production bundle exec rails data_hygiene:sanitize_whitespace EXECUTE=1
```

Essas tasks devem gerar logs em `log/`:

- `log/proprietor_merge_*.csv`
- `log/location_sanitize_*.csv`
- `log/whitespace_sanitize_*.csv`

## Validações pós-cutover

Validar antes de liberar uso:

- Backup de produção registrado e íntegro.
- Migrations executadas sem erro.
- Imóveis/captações/leads continuam com contagens compatíveis com o banco
  anterior.
- Imóveis continuam apontando para proprietários válidos.
- Duplicidade de proprietários saneada sem perder referências.
- `data_hygiene:sanitize_whitespace` em dry-run retorna `0 colunas | 0 valores`.
- Duplicidades normalizadas em `cidade`, `bairro` e `bairro_comercial` retornam
  zero em `habitations` e `addresses`.
- Menus/permissões novas aparecem conforme perfis configurados neste ambiente.
- Integrações e configurações críticas foram conferidas na tela administrativa.

## Gaps antes do corte real

Antes de executar em produção, fechar estes pontos:

- Confirmar lista final de tabelas de configuração que devem ser copiadas deste
  ambiente para produção.
- Confirmar scripts de export/import para captações e leads, caso o fluxo de
  dump/restore não preserve esses registros automaticamente.
- Rodar ensaio local com dump recente de produção e comparar contagens antes e
  depois.
- Registrar comandos exatos usados no ensaio e reaproveitar no corte real.
