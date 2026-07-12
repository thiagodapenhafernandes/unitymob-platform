# Contrato de isolamento por tenant

## Regra principal

Todo registro operacional deve ser consultado a partir do tenant autenticado ou de um tenant explicitamente resolvido por credencial externa confiável.

Exemplos seguros:

```ruby
current_tenant.habitations.find(params[:id])
tenant.leads.where(status: :novo)
integration.tenant.portal_listing_states
```

Não usar `Model.find`, `Model.find_by` ou `Model.where` em recursos operacionais quando o tenant já é conhecido.

## Exceções globais intencionais

- `ErrorEvent`: rastreador do System Admin; precisa registrar falhas mesmo sem tenant.
- `SystemNotificationSetting`: transporte global usado somente como fallback opt-in.
- chaves `tracking.*` em `Setting`: configuração de plataforma, alterável somente pelo System Admin.
- `StorageIntegrationSetting`: infraestrutura global, alterável somente pelo System Admin.
- resoluções de webhooks por token, assinatura HMAC ou identificador externo global: podem iniciar globalmente apenas para descobrir um único tenant; toda operação posterior deve usar esse tenant.
- métricas do `Admin::SystemController`: agregações globais somente leitura exclusivas do System Admin.

## Jobs

Jobs operacionais devem receber `tenant_id` ou recuperar o tenant a partir de um registro raiz confiável. Antes de consultas secundárias, devem executar dentro de `Current.set(tenant: tenant)`.

## Active Storage

Direct uploads administrativos registram `tenant_id` no metadata do blob. O vínculo ao imóvel deve validar que o blob pertence ao mesmo tenant e ainda não está anexado.

## Testes obrigatórios

Funcionalidades tenantizadas devem cobrir:

- dois tenants com registros de IDs distintos;
- tentativa de acesso cruzado por ID;
- tentativa cruzada por slug ou token quando aplicável;
- jobs executados com o tenant correto;
- exports e anexos sem conteúdo de outra conta;
- acesso global permitido apenas ao System Admin.

O gate local/CI é:

```bash
RAILS_ENV=test bundle exec rake security:tenant_isolation
```

## Saúde e alertas globais

O monitor `SystemHealthMonitorJob` roda fora do contexto de tenant porque avalia a
plataforma inteira. As amostras por conta sempre carregam `tenant_id`; apenas a
amostra consolidada da plataforma usa `tenant_id: nil`. O histórico é exclusivo
do Admin do Sistema e tem retenção de 90 dias.

Os limites podem ser ajustados pelas variáveis `HEALTH_*`. Alertas usam Web Push
para Admins do Sistema e e-mail via `SYSTEM_HEALTH_ALERT_EMAIL`, com fallback para
`ERROR_ALERT_EMAIL`, sem incluir conteúdo operacional de imóveis ou leads.

Esse comando deve ser executado obrigatoriamente antes de deploys que alterem autenticação, autorização, models operacionais, exports, anexos, jobs, webhooks ou integrações.
