# Unitymob Meta Webhook Gateway

Subapp isolado para receber o webhook global do app Meta da Unitymob e rotear eventos para os sistemas dos clientes.

## Objetivo

- Endpoint publico WhatsApp: `https://webhooks.unitymob.com.br/webhooks/whatsapp`
- Endpoint publico Meta Lead Ads: `https://webhooks.unitymob.com.br/webhooks/meta`
- Validar `X-Hub-Signature-256` com o app secret da Meta.
- Resolver a rota por `phone_number_id` e, se necessario, por `waba_id`.
- Resolver leads da Meta por `page_id` e, se necessario, por `form_id`.
- Encaminhar o payload bruto para o destino do cliente com assinatura interna.
- Registrar eventos sem rota como `unrouted` e emitir alerta operacional opcional.
- Manter o CRM fora do papel de webhook global da Meta.
- Endpoint publico de descoberta de conta do app hibrido mobile (Capacitor): `https://webhooks.unitymob.com.br/discovery/resolve` — dado um e-mail, devolve a URL do servidor fisico do cliente dono daquela conta.

## Setup local

```bash
cd gateway
bundle install
cp .env.example .env
bundle exec rake db:create db:migrate
bundle exec rackup -p 4001
```

## Deploy em `webhooks.unitymob.com.br`

Este subapp roda separado do CRM principal no servidor `root@webhooks.unitymob.com.br`:

- path: `/opt/unitymob-whatsapp-gateway`
- runtime: Docker Compose
- porta local: `127.0.0.1:4010`
- proxy publico: Apache `webhooks.unitymob.com.br` -> `http://127.0.0.1:4010`
- banco: PostgreSQL local `unitymob_whatsapp_gateway_production`

Atualizacao manual segura:

```bash
rsync -az --delete --exclude '.env' --exclude 'vendor/bundle' --exclude 'log/*' --exclude 'tmp/*' \
  gateway/ root@webhooks.unitymob.com.br:/opt/unitymob-whatsapp-gateway/

ssh root@webhooks.unitymob.com.br 'cd /opt/unitymob-whatsapp-gateway && docker compose build whatsapp-gateway && docker compose up -d whatsapp-gateway && docker compose exec -T whatsapp-gateway bundle exec rake db:migrate'
```

Validacao:

```bash
curl -i https://webhooks.unitymob.com.br/up
ssh root@webhooks.unitymob.com.br 'docker ps --filter name=unitymob-whatsapp-gateway'
```

## Retry de encaminhamentos falhos

Quando o CRM de destino estiver temporariamente fora, o gateway mantém o evento
persistido, marca `failed`, agenda `next_retry_at` com backoff e continua
respondendo `200` para a Meta. Assim a Meta não entra em retry storm e o
reprocessamento fica sob controle do gateway.

Retry manual:

```bash
ssh root@webhooks.unitymob.com.br 'cd /opt/unitymob-whatsapp-gateway && docker compose exec -T whatsapp-gateway bundle exec rake webhooks:retry_failed'
```

Sugestão de agendamento no servidor:

```cron
* * * * * cd /opt/unitymob-whatsapp-gateway && docker compose exec -T whatsapp-gateway bundle exec rake webhooks:retry_failed >> log/retry_failed.log 2>&1
```

Variáveis opcionais:

- `LIMIT`: quantidade máxima de eventos por execução, default `100`.
- `MAX_ATTEMPTS`: máximo de tentativas por evento, default `10`.

## Auditoria operacional

Eventos recentes podem ser consultados via API interna:

```bash
curl -H "Authorization: Bearer $INTERNAL_API_TOKEN" \
  "https://webhooks.unitymob.com.br/internal/webhook_events?provider=meta&status=unrouted&limit=50"
```

Ou diretamente no servidor:

```bash
ssh root@webhooks.unitymob.com.br 'cd /opt/unitymob-whatsapp-gateway && docker compose exec -T whatsapp-gateway bundle exec rake webhooks:events PROVIDER=meta STATUS=unrouted LIMIT=50'
ssh root@webhooks.unitymob.com.br 'cd /opt/unitymob-whatsapp-gateway && docker compose exec -T whatsapp-gateway bundle exec rake webhooks:events PROVIDER=meta PAGE_ID=214973675033177 LIMIT=50'
```

## Rotas Meta Lead Ads

O gateway aceita:

- rota geral por página: `provider=meta`, `page_id=...`, `form_id=nil`;
- rota específica por formulário: `provider=meta`, `page_id=...`, `form_id=...`.

Quando chega um lead com `page_id` e `form_id`, o gateway tenta primeiro a rota específica do formulário. Se não encontrar, usa a rota geral da página.

## Descoberta de conta (app hibrido mobile)

O mesmo gateway/token do webhook do WhatsApp serve pra achar automaticamente o
servidor certo de cada corretor quando ele loga no app mobile (Capacitor) —
sem cadastro manual por usuario. Cada servidor de cliente sincroniza sozinho
(`app/services/mobile/account_route_registrar.rb` no CRM principal, disparado
por `after_commit` no `AdminUser`) sempre que um usuario e criado/editado.

**Onboarding de cliente novo**: alem das variaveis `WHATSAPP_WEBHOOK_GATEWAY_*`
que ja fazem parte do runbook padrao, so falta UMA variavel nova no `.env` de
producao do cliente:

```
PUBLIC_APP_URL=https://<dominio publico do cliente>
```

`GATEWAY_URL`/`GATEWAY_INTERNAL_TOKEN` nao precisam ser configurados — o
registrar cai automaticamente em `WHATSAPP_WEBHOOK_GATEWAY_URL`/
`WHATSAPP_WEBHOOK_GATEWAY_INTERNAL_TOKEN` (mesmo servico, mesmo
`INTERNAL_API_TOKEN`). So defina `GATEWAY_URL`/`GATEWAY_INTERNAL_TOKEN`
explicitamente se algum cliente precisar apontar pra um gateway diferente.

Depois de configurar `PUBLIC_APP_URL` e reiniciar o servico do cliente, rode
uma vez (retroativo — os proximos cadastros ja sincronizam sozinhos):

```bash
RAILS_ENV=production bundle exec rake mobile:backfill_account_routes
```

## Variaveis

- `DATABASE_URL`: banco PostgreSQL do gateway.
- `META_WEBHOOK_VERIFY_TOKEN`: token usado no GET de verificacao da Meta para WhatsApp e Lead Ads.
- `META_APP_SECRET`: app secret usado para validar assinatura do webhook.
- `INTERNAL_API_TOKEN`: bearer token para criar/atualizar rotas internas (webhook routes E account routes de discovery).
- `GATEWAY_UNROUTED_ALERT_WEBHOOK_URL`: endpoint opcional para receber alertas JSON quando um evento chegar sem rota.

## Rotas

- `GET /up`
- `GET /webhooks/whatsapp`
- `POST /webhooks/whatsapp`
- `GET /webhooks/meta`
- `POST /webhooks/meta`
- `POST /internal/whatsapp/routes`
- `DELETE /internal/whatsapp/routes/:phone_number_id`
- `POST /internal/meta/routes`
- `DELETE /internal/meta/routes/:page_id`
- `GET /internal/webhook_events`
- `POST /discovery/resolve` — publico, sem auth (rate-limit apenas); `{ email }` -> `{ tenant_url }`.
- `POST /internal/account_routes` — cadastra/atualiza a rota de um e-mail (usado pelo `AccountRouteRegistrar`).
- `DELETE /internal/account_routes/:email` — desativa a rota (ex.: usuario desativado/removido).

## Encaminhamento

O gateway envia para o `target_url` cadastrado:

- body original recebido da Meta.
- `X-Unitymob-Gateway-Signature: sha256=<hmac>`.
- `X-Unitymob-Gateway-Event-Id`.
- `X-Unitymob-Gateway-Provider: whatsapp` ou `meta`.

O destino deve validar a assinatura com o `forwarding_secret` da rota.
