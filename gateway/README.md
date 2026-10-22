# Unitymob Meta Webhook Gateway

Subapp isolado para receber o webhook global do app Meta da Unitymob e rotear eventos para os sistemas dos clientes.

## Entrega assíncrona Meta/WhatsApp (opt-in; não ativada automaticamente)

`GATEWAY_ASYNC_DELIVERY_ENABLED=true` faz os endpoints Meta/WhatsApp persistirem
antes de responder 200, sem chamadas de rede no recebimento. Um worker separado
(`webhooks:work`, profile Compose `async-delivery`) usa o próprio banco do gateway,
com dois consumidores, exclusão mútua e intervalo mínimo de 300 ms por host,
compartilhado entre provedores. TikTok, Grupo OLX, discovery, URLs, assinaturas,
segredos e seleção de rotas permanecem nos contratos atuais.

Eventos novos recebem identidade única; reentregas não criam outra entrega.
WhatsApp distingue transições sent/delivered/read e alterações de template.
Recibos históricos correspondentes não são inscritos na fila nova. Nenhum
backfill, replay ou limpeza de duplicatas históricas faz parte da migration.
Os retries antigos ignoram a fila nova, evitando concorrência entre mecanismos.

Falhas novas têm até 10 tentativas, espera exponencial e jitter. HTTP 429 pausa
o destino por pelo menos 60 segundos, respeitando `Retry-After` maior, inclusive
HTTP-date. Depois do limite, o registro permanece `failed` e finalizado para
revisão manual. Não prometer exactly-once: queda após aceite pelo CRM e antes do
commit pode exigir nova entrega; a idempotência do consumidor continua necessária.

### Publicação futura, após aprovação do pacote

1. Guardar revisão/configuração, inventariar fila e rotas. Preservar `.env` e
   arquivos de runtime existentes. Não executar `webhooks:retry_failed` genérico.
2. Construir as imagens novas, sem substituir os processos. Executar a migration
   `20261022170000` com a imagem nova **antes** de subir web/worker. Exemplo:
   `docker compose run --rm --no-deps whatsapp-gateway bundle exec rake db:migrate`.
   A migration é aditiva, sem backfill, com índices da tabela de eventos criados
   concorrentemente; a FK nova é NOT VALID para evitar varredura bloqueante do
   histórico. Não remover colunas/índices no rollback de aplicação.
3. Somente na Salute, publicar o Rails e configurar
   `AUTHENTICATED_GATEWAY_WEBHOOK_LIMIT=1200`. Não trocar o forwarding secret.
   A assinatura HMAC é validada sobre o corpo cru antes de separar a cota. Header
   inválido continua na cota pública. Meta/WhatsApp têm cotas independentes;
   instalações sem essa variável mantêm o limite anterior. Não implantar Rails
   na Conexão por inferência deste pacote.
4. Configurar o flag do gateway e iniciar primeiro o worker:
   `docker compose --profile async-delivery up -d webhook-delivery`.
   Verificar processo, logs e acesso ao banco. O web antigo ainda mantém seu
   ambiente até ser recriado; não modificar a tabela de eventos históricos.
5. Só então recriar o serviço web com o flag habilitado. Validar `/up`,
   `webhooks:queue_status`, idade da fila, logs, falhas finais, latência e entrega
   natural em cada CRM; 200/forwarded não substitui confirmação de ingestão.
6. Alertar worker parado/reiniciando, fila envelhecendo e falhas finais. `/up`
   sozinho continua sendo apenas saúde HTTP. Comparar rotas e callbacks com o
   baseline, sem reconectar contas nem reenviar o histórico.

Rollback deve preservar os recibos pendentes: manter o receptor novo e reparar
ou reverter o worker compativelmente, ou drenar a fila antes de voltar ao modo
síncrono. Não desligar a fila e voltar cegamente ao web antigo com pendências:
reentregas poderiam passar pelos dois mecanismos. Nenhum comando deste roteiro
foi executado em produção durante a implementação local.

## Objetivo

- Endpoint publico WhatsApp: `https://webhooks.unitymob.com.br/webhooks/whatsapp`
- Endpoint publico Meta Lead Ads: `https://webhooks.unitymob.com.br/webhooks/meta`
- Validar `X-Hub-Signature-256` com o app secret da Meta.
- Resolver a rota por `phone_number_id` e, se necessario, por `waba_id`.
- Resolver leads da Meta por `page_id` e, se necessario, por `form_id`.
- Encaminhar o payload bruto para o destino do cliente com assinatura interna.
- WhatsApp: processar somente eventos com rota ativa; reconhecer eventos autenticados sem rota com HTTP 200, sem armazenar ou encaminhar seu conteúdo.
- Meta Lead Ads: manter eventos sem rota como `unrouted`, com alerta operacional opcional.
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

Procedimento canônico: [Deploys de produção](../docs/deploys.md#gateway-docker-compose-sem-mina).
O alvo `$fazer_deploy gateway` publica somente este componente; `all` não o inclui.
Prefira o pacote extraído do commit descrito nessa referência ao checkout local.

Este subapp roda separado do CRM principal no servidor `root@webhooks.unitymob.com.br`:

- path: `/opt/unitymob-whatsapp-gateway`
- runtime: Docker Compose
- porta local: `127.0.0.1:4010`
- proxy publico: Nginx `webhooks.unitymob.com.br` -> `http://127.0.0.1:4010`
- banco: PostgreSQL local `unitymob_whatsapp_gateway_production`

Proteção contra saturação, diagnóstico, patch do proxy e rollback:
[runbook operacional](ops/README.md). O espelho opcional de desenvolvimento
recebe somente após a entrega oficial e pausa por 60 segundos após falhar;
cópias puladas durante a pausa ou outra tentativa em curso não são reenviadas.

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

### Filtro de contas WhatsApp

O cadastro de rotas ativas é a lista de aceitação do WhatsApp. A assinatura
Meta continua sendo validada antes de qualquer consulta de roteamento.
Cada requisição carrega as rotas WhatsApp ativas uma vez, prioriza o
`phone_number_id` e mantém o fallback existente por `waba_id` (necessário para
eventos de templates sem número). Não há lista fixa de clientes ou cache entre
requisições: uma rota ativada passa a aceitar eventos na próxima requisição.

Eventos sem rota recebem HTTP 200 com a contagem `ignored` na resposta, sem
criar `WebhookEvent`, emitir alertas ou chamar o espelho de desenvolvimento.
Não responder 4xx para esses eventos evita incentivar novas tentativas da Meta.
Em lotes mistos, somente os eventos aceitos são persistidos, entregues e
espelhados, com payload isolado por evento. Falhas de assinatura continuam
recebendo 401; falhas na entrega oficial continuam no mecanismo de retry.

O histórico anterior não é apagado. Novos eventos ignorados não ficam disponíveis
para recuperação posterior. O filtro reduz escrita e I/O, mas ainda precisa
receber, autenticar e interpretar o webhook; não altera inscrições ou entregas
de outros apps na Meta. Meta Lead Ads, ZAP e TikTok não usam esse filtro.

O gateway envia para o `target_url` cadastrado:

- body original recebido da Meta.
- `X-Unitymob-Gateway-Signature: sha256=<hmac>`.
- `X-Unitymob-Gateway-Event-Id`.
- `X-Unitymob-Gateway-Provider: whatsapp` ou `meta`.

O destino deve validar a assinatura com o `forwarding_secret` da rota.

## Painel administrativo (`/admin`)

Visão geral somente leitura das contas roteadas: de onde vêm os eventos (identificadores da Meta — `phone_number_id`/`waba_id` para WhatsApp, `page_id`/`form_id` para Lead Ads) e para onde cada uma é encaminhada (`target_url`), com status do último evento e eventos recentes sem rota.

Login em duas etapas, sem cadastro de usuários — uma única credencial de operação:

1. `POST /admin/login` com e-mail e senha (`GATEWAY_ADMIN_EMAIL` / `GATEWAY_ADMIN_PASSWORD_DIGEST`).
2. Código de 6 dígitos, válido por 10 minutos, enviado por e-mail (Resend) para `GATEWAY_ADMIN_EMAIL` — não para o e-mail digitado no formulário.
3. Sessão de navegador (cookie assinado) válida por 12h.

Setup:

```bash
PASSWORD='sua-senha' bundle exec rake admin:hash_password
# copiar a saída para GATEWAY_ADMIN_PASSWORD_DIGEST no .env
```

Defina também `SESSION_SECRET`, `GATEWAY_ADMIN_SECRET` e `GATEWAY_ADMIN_EMAIL` (ver `.env.example`). Reaproveita `RESEND_API_KEY`/`DISCOVERY_MAIL_FROM` já usados pelo Discovery, a menos que `GATEWAY_ADMIN_MAIL_FROM` seja definido.

Rate limit de 10 tentativas / 10 min por IP em cada etapa (login e verificação de código).

## Discovery V2 (ativação coordenada)

Implementação aditiva: índice `account_memberships`, credenciais exclusivas por instância, confirmação de e-mail via API HTTPS do Resend, desafios de uso único e limites persistidos. Não altera os contratos de webhook.

Contratos, configuração privada, reconciliador e rollback: [roteiro de ativação](../docs/discovery-v2-activation.md). Execute as migrations antes de subir o processo novo. Configure a manutenção horária `bundle exec rake discovery:cleanup`.

O endpoint antigo continua compatível para um destino único. Com múltiplos vínculos V2, responde `409 multiple_accounts`; é necessário o cliente V2 para escolher a conta. Não existe fallback silencioso para o último CRM sincronizado nesse caso.
