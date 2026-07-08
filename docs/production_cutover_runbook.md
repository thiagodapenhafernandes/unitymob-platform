# Roteiro de migração/cutover de produção

Este roteiro é para o corte em que a produção atual será migrada para a nova
versão do sistema preservando dados operacionais críticos da produção e levando
as configurações preparadas neste ambiente.

## Premissas

- Antes de qualquer alteração destrutiva, fazer backup completo do banco de
  produção em formato custom do PostgreSQL e validar que o arquivo foi gerado.
- O deploy da Salute deve usar o stage Mina `saluteimoveis`, apontando para o
  repositório `git@github.com:thiagodapenhafernandes/unitymob-platform.git`.
- O comando de deploy específico da Salute é:

```bash
rvm 3.2.3 do bundle exec mina saluteimoveis deploy
```

- Quando houver mais stages configurados, `mina all deploy` deve executar todos
  os stages isoladamente. No momento, `all` contém apenas `saluteimoveis`.
- O banco de produção atual é a fonte de verdade para dados transacionais que
  aconteceram depois da cópia local.
- O banco/local deste workspace é a fonte de verdade para configurações,
  perfis, permissões, ajustes de sistema e catálogos preparados durante a
  evolução da nova versão.
- Logs CSV de saneamento devem ser preservados em produção para auditoria.

## Estado atual antes do corte

Em 08/07/2026 foi feita simulação local com dump recente de produção. Nenhum
deploy novo foi executado durante o ensaio e nenhum dado operacional de produção
foi alterado, exceto atualização controlada do `.env` compartilhado para incluir
as chaves `AR_ENCRYPTION_*`, com backup prévio do arquivo.

- Produção atual voltou para o release antigo:
  `/home/salute/deploy/releases/274`.
- `https://saluteimoveis.com.br/` responde `200 OK`.
- Serviços ativos em produção ficam no `systemctl` global:
  `puma_salute_imoveis_v3_production` e
  `solid_queue_salute_imoveis_v3_production`.
- A simulação do Mina confirmou stage `saluteimoveis`, branch `master`,
  repositório `git@github.com:thiagodapenhafernandes/unitymob-platform.git` e
  restart via `sudo systemctl`.
- `mina all deploy` em modo de simulação expande para
  `bundle exec mina saluteimoveis deploy`.
- O banco de produção já estava com as migrations da nova versão aplicadas por
  tentativa anterior de deploy; o código em produção segue no release antigo até
  o deploy final.

Snapshot read-only usado no ensaio:

| Origem | AdminUser | Profile | DistributionRule | Habitation | Captacao | Lead | Proprietor |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Produção antiga | 47 | 5 | 0 | 6775 | 7 | 24 | 5492 |
| Local nova versão | 53 | 10 | 1 | 6897 | 7 | 50 | 2906 |

Essa diferença confirma que o corte não pode ser "substituir banco". O banco de
produção deve permanecer como base transacional, recebendo migrations e
configurações selecionadas deste ambiente.

Resultado do ensaio completo com dump novo:

| Etapa | Resultado |
| --- | --- |
| Dump novo | `tmp/migration_rehearsal/production-20260708192152.dump`, 135.6 MB |
| `pg_restore --list` | OK, 1793 entradas no TOC |
| Restore temporário | OK em PostgreSQL 17/PostGIS, banco `unitymob_cutover_rehearsal_20260708192323` |
| `db:migrate` | OK, sem migrations pendentes no dump novo |
| Configuração segura | OK, 48 usuários finais, 1 super admin, 1 regra de distribuição |
| Validação de referências | 0 usuários sem perfil, 0 gerentes inválidos, 0 imóveis com proprietário inválido, 0 leads com regra inválida |
| Saneamentos após executar no ensaio | proprietários 0, localização 0, espaços 0 em dry-run final |

## Dados que devem ser preservados da produção

Preservar do banco de produção atual:

- Imóveis (`habitations`) e vínculos diretamente ligados ao cadastro do imóvel,
  incluindo proprietário, corretor responsável, atribuições e fotos/anexos.
- Proprietários criados em produção no mesmo período dos imóveis novos. Esses
  registros não podem ser sobrescritos pelo banco/local: quando um imóvel novo
  gerou um `proprietor_id` em produção, o proprietário e o vínculo do imóvel
  ficam como dados transacionais da produção.
- Captações (`captacoes`) e dados relacionados ao fluxo de captação.
- Leads (`leads`) e dados relacionados ao atendimento/funil.
- Usuários administrativos existentes em produção (`admin_users`) como
  identidade operacional: e-mail de login, senha criptografada, 2FA, dispositivos
  confiáveis, tokens de webhook, histórico de acesso/auditoria e vínculos com
  imóveis, leads, campanhas, check-ins e demais registros criados em produção.

O objetivo é não perder movimentações reais feitas em produção enquanto o novo
sistema estava sendo ajustado localmente.

## Dados/configurações que devem vir deste ambiente

Levar deste banco/local para produção:

- Configurações globais e por conta/tenant.
- Perfis, permissões, menus e regras de acesso.
- Perfis verticais/horizontais e permissões preparados neste ambiente.
- Organização hierárquica preparada neste ambiente, aplicada sobre os usuários
  preservados da produção por correspondência segura.
- Regras de distribuição e governança operacional.
- Configurações de integrações e módulos ajustados neste ambiente.
- Catálogos dinâmicos e parâmetros funcionais preparados na nova versão.

Ponto crítico: o roteiro atual em `lib/tasks/migration_rehearsal.rake` cobre
hierarquia/perfis/usuários/tenants, mas ainda não deve ser usado diretamente em
produção para usuários: ele pode atualizar atributos de `admin_users` a partir do
banco/local. Antes do cutover, separar "identidade do usuário" de "perfil e
hierarquia" e validar a exportação das configurações restantes.

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

No ensaio de 08/07/2026, o dump novo
`tmp/migration_rehearsal/production-20260708192152.dump` foi validado com
`pg_restore --list`: formato custom, PostgreSQL 16.10, 1793 entradas no TOC.
Para o corte real, se houver intervalo relevante entre ensaio e execução final,
gerar outro dump novo imediatamente antes do deploy.

## Variáveis obrigatórias antes do cutover

Confirmar no `.env` compartilhado de produção:

- `AR_ENCRYPTION_PRIMARY_KEY`
- `AR_ENCRYPTION_DETERMINISTIC_KEY`
- `AR_ENCRYPTION_KEY_DERIVATION_SALT`
- Credenciais de banco (`DB_NAME`, `DB_USERNAME`, `DB_PASSWORD`, `DB_HOST`,
  `DB_PORT`).

Sem as chaves de Active Record Encryption, migrations e rotinas que leem ou
gravam CPF/CNPJ criptografado podem executar de forma incompleta ou gerar avisos
sem sanear os dados.

No ensaio de 08/07/2026, o `.env` compartilhado de produção tinha `APP_HOST`,
mas ainda não tinha:

- `AR_ENCRYPTION_PRIMARY_KEY`
- `AR_ENCRYPTION_DETERMINISTIC_KEY`
- `AR_ENCRYPTION_KEY_DERIVATION_SALT`

As chaves foram adicionadas em 08/07/2026. Backup do `.env` anterior:

```text
/home/salute/deploy/shared/.env.bak.before-ar-encryption-20260708181349
```

## Estratégia para usuários, perfis e hierarquia

Regra base:

- Usuários de produção são preservados.
- Perfis/permissões vêm deste ambiente.
- Hierarquia vem deste ambiente, mas só é aplicada quando o usuário existir em
  produção e puder ser identificado com segurança.

O pareamento deve usar, nesta ordem:

1. `email` normalizado.
2. `contact_email` normalizado, para usuários espelho/multi-conta.
3. `vista_id`, quando existir e for único dentro da conta.

Ao aplicar a organização deste ambiente em produção, pode atualizar nos usuários
pareados apenas os campos de alocação/organização:

- `tenant_id`, se a conta/tenant tiver sido mapeada e confirmada.
- `profile_id`.
- `horizontal_profile_id`.
- `manager_id`.
- `rentals_manager_id`.
- Campos operacionais de escopo/hierarquia que forem parte da regra nova, como
  `hierarchy_position`, desde que não sobrescrevam identidade/login.

Não sobrescrever automaticamente em produção:

- `email`, `encrypted_password`, reset tokens, remember/session fields.
- `otp_secret`, `otp_enabled_at`, `otp_backup_codes`,
  `otp_consumed_timestep`.
- `active`, sem conferência explícita. Desativar usuário de produção por
  acidente é risco operacional.
- `name`, `phone`, `creci`, `biography`, `avatar` e dados pessoais recentes,
  salvo se houver decisão de negócio para padronizar.
- `super_admin`, sem revisão manual.

Usuários que existem em produção e não existem neste ambiente devem continuar
existindo. Eles entram em relatório de revisão para receber um perfil padrão ou
serem classificados manualmente, mas não devem ser removidos no cutover.

Usuários que existem neste ambiente e não existem em produção não devem ser
criados automaticamente, exceto Admin do Sistema ou usuários explicitamente
marcados no checklist como necessários para operar a nova versão.

Conferência read-only sugerida antes do corte:

```bash
RAILS_ENV=production bundle exec rails runner '
  puts({
    tenants: Tenant.count,
    admin_users: AdminUser.count,
    active_admin_users: AdminUser.where(active: true).count,
    system_admins: AdminUser.where(super_admin: true).pluck(:email),
    without_profile: AdminUser.where(super_admin: false, profile_id: nil).count,
    with_manager: AdminUser.where.not(manager_id: nil).count,
    with_rentals_manager: (AdminUser.column_names.include?("rentals_manager_id") ? AdminUser.where.not(rentals_manager_id: nil).count : nil),
    mirrors: (AdminUser.column_names.include?("primary_admin_user_id") ? AdminUser.where.not(primary_admin_user_id: nil).count : nil)
  }.to_json)
'
```

O ensaio local precisa produzir um relatório de diffs antes de aplicar:

- usuários pareados;
- usuários só em produção;
- usuários só neste ambiente;
- mudanças de perfil/hierarquia por usuário;
- conflitos de gerente inexistente, tenant divergente ou perfil incompatível.

No ensaio de 08/07/2026, `migration_rehearsal:export_hierarchy` exportou:

- tenants: 2
- profiles: 10
- admin_users: 53
- account_memberships: 0
- distribution_rules: 0

Essa lacuna foi corrigida em 08/07/2026: o export passou a levar
`distribution_rules=1` e `distribution_rule_agents=1`.

Para aplicar configuração em produção, não usar
`migration_rehearsal:import_hierarchy`, pois ele foi mantido para ensaio local e
pode atualizar atributos de usuários. Usar a task segura, que preserva
identidade/login/senha/2FA e aplica somente tenants, perfis, hierarquia
pareada, regra de distribuição e Admin do Sistema:

```bash
RAILS_ENV=production bundle exec rails \
  migration_rehearsal:apply_production_configuration \
  FILE=/home/salute/deploy/shared/migration_rehearsal/hierarchy-safe-YYYYMMDDHHMMSS.json \
  APPLY=true \
  CONFIRM=salute_imoveis_v3_production
```

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

## Validação específica de proprietários novos em produção

Antes do corte, definir a data de início do período em que o banco/local ficou
defasado em relação à produção e rodar uma conferência read-only em produção:

```bash
SINCE="2026-07-01 00:00:00"
RAILS_ENV=production bundle exec rails runner '
  since = Time.zone.parse(ENV.fetch("SINCE"))
  scope = Proprietor.where("created_at >= ?", since)
  puts({
    since: since.iso8601,
    proprietors_created: scope.count,
    linked_to_habitations: Habitation.where(proprietor_id: scope.select(:id)).count,
    linked_to_client_interactions: (defined?(ClientInteraction) ? ClientInteraction.where(proprietor_id: scope.select(:id)).count : nil),
    linked_to_crm_appointments: (defined?(CrmAppointment) ? CrmAppointment.where(proprietor_id: scope.select(:id)).count : nil),
    linked_to_client_property_interests: (defined?(ClientPropertyInterest) ? ClientPropertyInterest.where(proprietor_id: scope.select(:id)).count : nil),
    unlinked_proprietors: scope.where.not(id: Habitation.select(:proprietor_id)).count
  }.to_json)
'
```

Se o corte for feito mantendo o banco de produção e apenas aplicando migrations +
configurações deste ambiente, esses proprietários permanecem naturalmente. Se em
algum momento for usado restore/import a partir do banco local, é obrigatório
exportar esses proprietários e reapontar suas referências antes de liberar o
sistema.

## Validações pós-cutover

Validar antes de liberar uso:

- Backup de produção registrado e íntegro.
- Migrations executadas sem erro.
- Imóveis/captações/leads continuam com contagens compatíveis com o banco
  anterior.
- Imóveis continuam apontando para proprietários válidos.
- Proprietários criados no período em produção continuam existindo e com seus
  imóveis/interações vinculados.
- Duplicidade de proprietários saneada sem perder referências.
- `data_hygiene:sanitize_whitespace` em dry-run retorna `0 colunas | 0 valores`.
- Duplicidades normalizadas em `cidade`, `bairro` e `bairro_comercial` retornam
  zero em `habitations` e `addresses`.
- Menus/permissões novas aparecem conforme perfis configurados neste ambiente.
- Usuários de produção conseguem autenticar com suas credenciais preservadas.
- Usuários pareados receberam os perfis e gestores esperados.
- Usuários que só existiam em produção continuam existentes e ativos, salvo
  decisão manual registrada.
- Integrações e configurações críticas foram conferidas na tela administrativa.

## Gaps antes do corte real

Antes de executar em produção, fechar estes pontos:

- Confirmar lista final de tabelas de configuração que devem ser copiadas deste
  ambiente para produção.
- Instalar/habilitar PostGIS no ambiente de ensaio local, ou executar o ensaio
  completo em um banco temporário que tenha PostGIS. O restore temporário do
  dump falhou em tabelas com `geography` (`stores`, `check_ins`,
  `location_pings`) porque o PostgreSQL local não tinha a extensão.
- Resolvido no ensaio: usar PostgreSQL 17 local na porta `5433`, onde PostGIS
  está disponível.
- Resolvido no checkout: a migration `20260706120000` foi reconciliada com uma
  migration vazia/documental.
- Resolvido no checkout: `migration_rehearsal:export_hierarchy` exporta
  `distribution_rules`.
- Confirmar scripts de export/import para captações e leads, caso o fluxo de
  dump/restore não preserve esses registros automaticamente.
- Ajustar o fluxo de importação de perfis/hierarquia para preservar identidade
  dos `admin_users` de produção. Não usar `migration_rehearsal:import_hierarchy`
  diretamente em produção até essa separação estar validada.
- Rodar ensaio local com dump recente de produção e comparar contagens antes e
  depois.
- Registrar comandos exatos usados no ensaio e reaproveitar no corte real.
- Atualizar/confirmar chaves de Active Record Encryption no `.env` de produção.
