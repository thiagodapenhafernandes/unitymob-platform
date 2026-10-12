# Auditoria de rastreamento — 12/10/2026

Escopo: saída de formulários/leads e diagnóstico GTM. Não altera captura,
matching, distribuição, seleção de eventos ou configurações de contas.

## Evidências e reutilização

- `app/services/leads/attribution.rb`: TRACKING_KEYS, browser_identifiers e apply!
  já centralizam classificação e contexto HTTP com aceite para cookies.
- `app/services/webhook_service.rb`: build_payload reúne dados persistidos e
  contexto do request; send_form_data monta um envelope compartilhado pelos
  destinos; event_id e transaction_id são iguais.
- `app/services/leads/outbound_webhook.rb`: dispatch_changes seleciona eventos
  CRM com escopo pelo tenant; não criar outro emissor de conversões.
- `app/jobs/webhook_delivery_job.rb`: entrega e retry já compartilhados, mas
  os logs anteriores só tinham origin_form, URL e HTTP. Faltava identidade do
  evento para comparar uma tentativa com o recebimento no GTM.
- `app/services/leads/inquiry_complement.rb`: complement_metadata guarda a
  atribuição da nova consulta no histórico; a atribuição canônica do lead não
  é substituída. Esse contrato precisa ser considerado antes de atribuir uma
  qualificação posterior à última campanha.

## Decisão implementada

Evoluir o job existente para emitir JSON de correlação com IDs, host, evento,
HTTP e tentativa. Não criar banco de payloads, serviço remoto ou dashboard.
Logs não expõem contatos, tokens do caminho/query ou erro bruto do transporte.
O custo é perder a mensagem detalhada do transporte neste log; HTTP nulo ainda
indica falha sem resposta e a execução permanece retentável.

## Próximos recortes

1. Validar evento recebido e variável transaction_id no GTM com o mesmo ID.
2. Definir com a operação qual consulta/campanha deve receber crédito quando
   um contato volta a consultar: primeira entrada ou consulta da conversão.
3. Definir unicidade de conversão por etapa antes de usar lead+evento como ID;
   trocar UUID por ID fixo silenciosamente pode suprimir conversões distintas.

Esses recortes não foram ativados por esta entrega. Resposta HTTP de sucesso
não prova acionamento de tags. Validação: specs do job e serviço de webhook.
