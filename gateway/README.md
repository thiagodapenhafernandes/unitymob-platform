# Unitymob WhatsApp Webhook Gateway

Subapp isolado para receber o webhook global do app Meta da Unitymob e rotear eventos para os sistemas dos clientes.

## Objetivo

- Endpoint publico Meta: `https://webhooks.unitymob.com.br/webhooks/whatsapp`
- Validar `X-Hub-Signature-256` com o app secret da Meta.
- Resolver a rota por `phone_number_id` e, se necessario, por `waba_id`.
- Encaminhar o payload bruto para o destino do cliente com assinatura interna.
- Manter o CRM fora do papel de webhook global da Meta.

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

## Variaveis

- `DATABASE_URL`: banco PostgreSQL do gateway.
- `META_WEBHOOK_VERIFY_TOKEN`: token usado no GET de verificacao da Meta.
- `META_APP_SECRET`: app secret usado para validar assinatura do webhook.
- `INTERNAL_API_TOKEN`: bearer token para criar/atualizar rotas internas.

## Rotas

- `GET /up`
- `GET /webhooks/whatsapp`
- `POST /webhooks/whatsapp`
- `POST /internal/whatsapp/routes`
- `DELETE /internal/whatsapp/routes/:phone_number_id`

## Encaminhamento

O gateway envia para o `target_url` cadastrado:

- body original recebido da Meta.
- `X-Unitymob-Gateway-Signature: sha256=<hmac>`.
- `X-Unitymob-Gateway-Event-Id`.
- `X-Unitymob-Gateway-Provider: whatsapp`.

O destino deve validar a assinatura com o `forwarding_secret` da rota.
