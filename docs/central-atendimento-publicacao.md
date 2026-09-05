# Preparação da publicação — 05/09/2026

Estado: preparação local. Sem commit, push, integração ou provisionamento nesta etapa.

## Pacote Git

Base comum após fetch: b228c36e55f1685d6d7c756978c7343e51713933.
develop, master, origin/develop e origin/master apontam para essa revisão.
Não há sobreposição entre arquivos rastreados modificados nos dois worktrees.

Ordem proposta:
1. Commit das correções existentes no checkout unitymob-platform/develop.
2. Commit da central e engine support no worktree codex/central-atendimento.
3. Merge --no-ff codex/central-atendimento em develop.
4. Validar o conjunto integrado antes de promover develop para master.
5. Publicar somente após resolver as dependências de infraestrutura abaixo.

Credenciais .env.development estão ignoradas. Não transportar banco local, contas QA,
tickets de demonstração, sessões, anexos locais nem credenciais locais para produção.
Inventários abaixo são do momento da preparação; revisar novamente antes de git add.

## Infraestrutura proposta

API autenticada confirmou o gateway unitymob-whatsapp-gateway-01, id 593391664,
159.223.105.26, região nyc1, na conta conectada. Nenhum recurso foi alterado.

Novo servidor sugerido: unitymob-central-01, Ubuntu 24.04, nyc1,
s-1vcpu-2gb, 1 vCPU, 2 GB RAM, disco 50 GB, US$12/mês.
Backup diário percentual: +30%, total US$15,60/mês antes de impostos e anexos.
Preços conferidos na API e https://www.digitalocean.com/pricing/droplets .
É uma proposta inicial para baixo volume, não capacidade garantida; medir RAM/CPU
com web, worker, PostgreSQL e deploy juntos antes de liberar o piloto.
Planos de US$4/512 MB e US$6/1 GB têm pouca margem para essa composição.

Pendências para liberação:
- Criar servidor, usuário SSH, banco exclusivo e serviços systemd de central/ops.
- Confirmar/apontar admin.unitymob.com.br e emitir TLS.
- Armazenamento privado: buckets separados para central e CRMs; apurar custo e
  credenciais disponíveis sem expor segredos. Anexos não podem usar CDN público.
- Configurar backup do PostgreSQL e testar restauração, além do backup da VM.
- Gerar chaves de criptografia, SMTP e identidade de cada instalação em produção.
- Configurar SUPPORT_TRUSTED_INSTANCES, SUPPORT_INSTANCE_ID,
  SUPPORT_INSTANCE_SECRET e SUPPORT_CENTRAL_URL com endpoints reais.
- Cadastrar admin de produção; não restaurar banco de desenvolvimento.
- Validar upload/resposta/entrega confirmada, autorização, acesso assistido,
  recorrências, recuperação de falha e eventos/presença reais.

## Alvos e comandos posteriores

Central, a partir de central/:
CENTRAL_HOST=<novo_ip> CENTRAL_BRANCH=master rvm 3.2.3 do bundle exec mina deploy
Path /home/unitymob/central, usuário unitymob.
Serviços unitymob-central-web e unitymob-central-jobs.

CRMs, a partir do checkout unitymob-platform na revisão promovida:
rvm 3.2.3 do bundle exec mina all deploy
- Salute: 143.110.138.67, usuário salute, /home/salute/deploy.
- Conexão: app.conexaobc.com, usuário conexao, /home/conexao/deploy.
O gateway não recebe deploy neste pacote.

## Verificação nesta etapa

- Central: 48 exemplos, 0 falhas.
- Cliente de suporte: 24 exemplos, 0 falhas.
- git diff --check em ambos os worktrees.
- bash -n no script/post_deploy_regression_monitor.
- Regressão focada das correções prévias (distribuição e C2S): 49 exemplos, 0 falhas.
- Total desta etapa: 121 exemplos, 0 falhas. Validação do conjunto integrado ainda pendente.

## Inventário develop

```
 M app/controllers/admin/distribution_rules_controller.rb
 M app/jobs/external_lead_migration/webhook_event_job.rb
 M app/models/distribution_rule.rb
 M app/services/data_hygiene/whitespace_sanitizer.rb
 M app/services/external_lead_migration/lead_enrichment.rb
 M app/services/external_lead_migration/scheduled_action_reconciler.rb
 M lib/tasks/external_lead_migration.rake
 M spec/jobs/leads/holding_release_job_spec.rb
 M spec/jobs/leads/pocket_expiration_job_spec.rb
 M spec/jobs/leads/pocket_sweep_job_spec.rb
 M spec/jobs/leads/pool_renotify_job_spec.rb
 M spec/jobs/meta_lead_processing_job_spec.rb
 M spec/jobs/meta_sync_enabled_integrations_job_spec.rb
 M spec/models/distribution_rule_spec.rb
 M spec/requests/admin/create_edit_permission_spec.rb
 M spec/requests/admin/delete_permission_spec.rb
 M spec/requests/admin/distribution_rules_spec.rb
 M spec/requests/admin/leads_spec.rb
 M spec/requests/field/check_ins_spec.rb
 M spec/requests/secure_links_spec.rb
 M spec/services/external_lead_migration/lead_upsert_spec.rb
 M spec/services/external_lead_migration/scheduled_action_reconciler_spec.rb
 M spec/services/leads/distributor_service_spec.rb
 M spec/services/leads/notification_dispatcher_spec.rb
 M spec/services/seo/marketing_insights_spec.rb
?? script/post_deploy_regression_monitor
?? spec/jobs/external_lead_migration/webhook_event_job_spec.rb

```

## Inventário central

```
 M app/models/tenant.rb
 M app/views/layouts/admin.html.erb
 M app/views/layouts/field.html.erb
 M config/application.rb
 M config/recurring.yml
 M config/routes.rb
 M config/storage.yml
 M db/structure.sql
 M design-qa.md
?? central/.env.example
?? central/.gitignore
?? central/.ruby-version
?? central/Gemfile
?? central/Gemfile.lock
?? central/Rakefile
?? central/app/assets/config/manifest.js
?? central/app/assets/javascripts/central_notifications.js
?? central/app/assets/javascripts/central_presence.js
?? central/app/controllers/application_controller.rb
?? central/app/controllers/management_controller.rb
?? central/app/controllers/notifications_controller.rb
?? central/app/controllers/outreach_controller.rb
?? central/app/controllers/presence_controller.rb
?? central/app/controllers/queue_preferences_controller.rb
?? central/app/controllers/sessions_controller.rb
?? central/app/controllers/sla_controller.rb
?? central/app/controllers/support_labels_controller.rb
?? central/app/helpers/sla_helper.rb
?? central/app/mailers/login_mailer.rb
?? central/app/models/sla_policy.rb
?? central/app/models/sla_policy_change.rb
?? central/app/models/staff.rb
?? central/app/models/staff_presence_window.rb
?? central/app/models/staff_session.rb
?? central/app/models/support/ticket_event.rb
?? central/app/models/support_label.rb
?? central/app/models/support_notification_read.rb
?? central/app/queries/support_notifications.rb
?? central/app/services/support/operations_dashboard.rb
?? central/app/services/support/sla_report.rb
?? central/app/services/support/timeline.rb
?? central/app/views/layouts/application.html.erb
?? central/app/views/management/dashboard.html.erb
?? central/app/views/management/finance.html.erb
?? central/app/views/management/index.html.erb
?? central/app/views/sessions/edit.html.erb
?? central/app/views/sessions/new.html.erb
?? central/app/views/sessions/verify.html.erb
?? central/app/views/sla/index.html.erb
?? central/bin/jobs
?? central/bin/rails
?? central/config.ru
?? central/config/application.rb
?? central/config/boot.rb
?? central/config/cable.yml
?? central/config/database.yml
?? central/config/deploy.rb
?? central/config/environment.rb
?? central/config/environments/development.rb
?? central/config/environments/production.rb
?? central/config/environments/test.rb
?? central/config/initializers/rack_attack.rb
?? central/config/initializers/smtp.rb
?? central/config/puma.rb
?? central/config/queue.yml
?? central/config/recurring.yml
?? central/config/routes.rb
?? central/config/storage.yml
?? central/db/migrate/20251125165431_create_active_storage_tables.active_storage.rb
?? central/db/migrate/20260205121042_create_solid_queue_tables.rb
?? central/db/migrate/20260905150100_create_staff.rb
?? central/db/migrate/20260905153000_add_staff_email_verification.rb
?? central/db/migrate/20260905161000_add_attendance_measurement.rb
?? central/db/migrate/20260905190000_create_support_notification_reads.rb
?? central/db/migrate/20260905200000_create_support_label_catalog.rb
?? central/db/migrate/20260905210000_add_queue_preferences_to_staffs.rb
?? central/db/schema.rb
?? central/ops/nginx.conf
?? central/ops/unitymob-central-jobs.service
?? central/ops/unitymob-central-web.service
?? central/spec/models/staff_spec.rb
?? central/spec/rails_helper.rb
?? central/spec/requests/activation_spec.rb
?? central/spec/requests/api_spec.rb
?? central/spec/requests/central_spec.rb
?? central/spec/requests/dashboard_spec.rb
?? central/spec/requests/email_login_spec.rb
?? central/spec/requests/inbox_spec.rb
?? central/spec/requests/infinite_queue_spec.rb
?? central/spec/requests/notifications_spec.rb
?? central/spec/requests/presence_spec.rb
?? central/spec/requests/queue_preferences_spec.rb
?? central/spec/requests/reference_inbox_spec.rb
?? central/spec/requests/registration_spec.rb
?? central/spec/requests/support_labels_spec.rb
?? central/spec/services/timeline_spec.rb
?? central/spec/views/ticket_event_spec.rb
?? config/initializers/support_assisted_access.rb
?? docs/central-atendimento-validacao.md
?? docs/central-atendimento.md
?? spec/requests/support/access_spec.rb
?? spec/requests/support/outreach_spec.rb
?? spec/requests/support/tickets_spec.rb
?? spec/services/support/exchange_spec.rb
?? spec/services/support/registration_spec.rb
?? support/BOOTSTRAP_ICONS_LICENSE.txt
?? support/app/assets/javascripts/support_desk.js
?? support/app/assets/javascripts/support_image_editor.js
?? support/app/assets/javascripts/support_image_engine.js
?? support/app/assets/javascripts/support_labels.js
?? support/app/assets/stylesheets/support_desk.css
?? support/app/controllers/support/access_grants_controller.rb
?? support/app/controllers/support/assisted_guard.rb
?? support/app/controllers/support/base_controller.rb
?? support/app/controllers/support/events_controller.rb
?? support/app/controllers/support/recipients_controller.rb
?? support/app/controllers/support/registrations_controller.rb
?? support/app/controllers/support/tickets_controller.rb
?? support/app/helpers/support/audit_helper.rb
?? support/app/helpers/support/messages_helper.rb
?? support/app/helpers/support/widget_helper.rb
?? support/app/jobs/support/dispatch_job.rb
?? support/app/jobs/support/notify_job.rb
?? support/app/jobs/support/register_accounts_job.rb
?? support/app/models/support/access_session.rb
?? support/app/models/support/account.rb
?? support/app/models/support/audit.rb
?? support/app/models/support/delivery.rb
?? support/app/models/support/message.rb
?? support/app/models/support/receipt.rb
?? support/app/models/support/ticket.rb
?? support/app/services/support/assisted_policy.rb
?? support/app/services/support/exchange.rb
?? support/app/services/support/intake.rb
?? support/app/services/support/registration.rb
?? support/app/services/support/transport.rb
?? support/app/views/admin/shared/ui/_support_access_banner.html.erb
?? support/app/views/admin/shared/ui/_support_assignee.html.erb
?? support/app/views/admin/shared/ui/_support_audit.html.erb
?? support/app/views/admin/shared/ui/_support_choice.html.erb
?? support/app/views/admin/shared/ui/_support_composer.html.erb
?? support/app/views/admin/shared/ui/_support_field.html.erb
?? support/app/views/admin/shared/ui/_support_form.html.erb
?? support/app/views/admin/shared/ui/_support_header.html.erb
?? support/app/views/admin/shared/ui/_support_identity.html.erb
?? support/app/views/admin/shared/ui/_support_intake_summary.html.erb
?? support/app/views/admin/shared/ui/_support_kpi.html.erb
?? support/app/views/admin/shared/ui/_support_label_badges.html.erb
?? support/app/views/admin/shared/ui/_support_labels.html.erb
?? support/app/views/admin/shared/ui/_support_message.html.erb
?? support/app/views/admin/shared/ui/_support_metric.html.erb
?? support/app/views/admin/shared/ui/_support_note.html.erb
?? support/app/views/admin/shared/ui/_support_notification_bell.html.erb
?? support/app/views/admin/shared/ui/_support_ticket_bi.html.erb
?? support/app/views/admin/shared/ui/_support_ticket_controls.html.erb
?? support/app/views/admin/shared/ui/_support_ticket_event.html.erb
?? support/app/views/admin/shared/ui/_support_widget.html.erb
?? support/app/views/support/tickets/_operator_conversation.html.erb
?? support/app/views/support/tickets/_operator_inbox.html.erb
?? support/app/views/support/tickets/access.html.erb
?? support/app/views/support/tickets/created.html.erb
?? support/app/views/support/tickets/index.html.erb
?? support/app/views/support/tickets/new.html.erb
?? support/app/views/support/tickets/show.html.erb
?? support/db/migrate/20260905150000_create_support_desk.rb
?? support/db/migrate/20260905151000_add_support_delivery_tracking.rb
?? support/db/migrate/20260905154000_order_support_account_controls.rb
?? support/db/migrate/20260905160000_add_support_diagnostics.rb
?? support/db/migrate/20260905180000_add_support_outreach_and_message_revisions.rb
?? support/engine.rb
?? support/lib/tasks/support.rake
?? support/routes.rb

```
