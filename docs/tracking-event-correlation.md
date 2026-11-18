# Correlação de eventos do site e CRM

Implementação de 17/11/2026. Para publicação, a migration
`20261117233000_create_tracking_event_links` deve preceder a publicação do código.
Não há backfill, replay, ativação de integração nem mudança de destino.

## Contrato

`tracking_event_links` relaciona uma ocorrência interna ao transporte, destino e
`external_event_id` já produzido pelo emissor. A chave de ocorrência não é enviada
às plataformas e não substitui `event_id`, `transaction_id`, IDs de lead ou UID.
Os payloads externos e as condições de elegibilidade permanecem os existentes.

Uma captura nova do modal liga o UUID oferecido na resposta ao navegador e o UUID
do webhook pela chave `lead:<id>:created`. A jornada posterior se liga pelo lead;
cada alteração tem uma chave própria, baseada no tipo/ID do registro, seu
`updated_at` com microssegundos e um digest dos campos alterados (sem guardar os
valores). Isso distingue alterações diferentes mesmo com timestamp igual.
Todos os emissores acionados pela mesma alteração
usam essa chave. Visitas e propostas usam o registro específico, não o timestamp
atual do job nem apenas a etapa do lead.

Formulários públicos usam `public_form_submission:<id>`. O webhook pode existir
antes do lead: o roteamento assíncrono preenche o vínculo quando encontra/cria o
lead, inclusive em consultas agregadas. `/contato` continua administrativo, com
uma ocorrência própria de webhook e sem entrada na distribuição de corretores.

## IDs, deduplicação e compatibilidade

- Site e webhook geral conservam seus UUIDs distintos.
- Google por etapa conserva `<lead_id>_<marco>` e a outbox existente.
- GA4 conserva UUID, chave de deduplicação e parâmetros existentes.
- Meta conserva o SHA1 por conta/lead/nome do evento e cada dataset configurado.
- A unicidade é por conta, transporte, ID externo e digest do destino. Um ID
  reutilizado pela deduplicação legada não é reatribuído a uma ocorrência nova.
  Na Meta, tentativas posteriores também guardam a chave da ocorrência que
  provocou cada reenvio, preservando a referência original e a causa posterior.
  Por isso duas visitas podem gerar dois eventos GA4 e somente o primeiro marco
  Google/Meta: esta entrega documenta essa diferença, sem mudar a contagem.
- WebhookDeliveryJob continua aceitando os dois argumentos antigos. Novos jobs
  levam uma referência interna adicional (conta + ID), conferida com evento e
  destino antes de registrar a tentativa.
- MetaConversionJob continua aceitando os argumentos antigos. Novos jobs levam o
  contexto interno adicional, preservado no retry. Jobs antigos não recebem
  correlação retroativa inventada.

## Leitura dos resultados

| Transporte | Fonte do resultado | Limite da evidência |
| --- | --- | --- |
| Site | `browser_offered` | Resposta preparada com o evento; não comprova execução da tag. |
| Webhook geral | Tentativas e HTTP na referência | `http_accepted` comprova somente HTTP 2xx do receptor. |
| Google por webhook | `GoogleStageConversionEvent` existente | `delivered` é apresentado como `http_accepted`; não prova conversão importada. |
| GA4 direto | `Ga4ConversionEvent` existente | Mantém `http_accepted`, `uncertain`, `rejected` e descartes existentes. |
| Meta | Tentativas por dataset, confirmação `events_received: 1` e trace | `received` confirma recebimento; não prova atribuição à campanha. |

Use `delivery_status`, `delivery_attempts` e `delivery_skip_reason` para consultar
o resultado. Os registros Google/GA4 são a fonte de verdade, sem copiar payloads,
status ou tentativas para outra outbox. Se um registro nativo for removido, a
referência retorna `record_removed`, sem apresentar sucesso inexistente.

Uma confirmação Meta já registrada não é apagada por falha de um reenvio
redundante; a nova tentativa continua no histórico. Falha sem resposta ou sem
confirmação unitária fica como `uncertain`. Os retries continuam sob controle dos
jobs existentes, com os mesmos IDs e destinos.

Exemplo de consulta, sempre escopada pela conta e pelas permissões já aplicadas
ao lead:

```ruby
lead = tenant.leads.find(lead_id)
lead.tracking_event_links
  .includes(:google_stage_conversion_event, :ga4_conversion_event)
  .order(:occurred_at, :id)
  .group_by(&:occurrence_key)
```

## Consulta no admin (terceira etapa)

Na ficha do lead, desktop ou mobile, abra **Auditoria de envios**:
`/admin/leads/:id/tracking_audit`. A tela reúne a origem/campanha já registrada,
a jornada do atendimento existente e as referências de envio, com filtro por
transporte e paginação de 25 registros, dos mais recentes para os mais antigos.
Cada referência mostra status, ID externo preservado, ocorrência interna,
destino sem credenciais e histórico de tentativas/resultados. O histórico pode
incluir descartes antes da rede; GA4 conserva somente o último resultado nativo.
Os registros são consultados novamente ao carregar/filtrar a página, sem polling.

O acesso exige login, permissão `view` de `leads` e o mesmo escopo da ficha
(próprio, equipe ou conta, conforme o perfil), incluindo as restrições de arquivo.
O ID é resolvido exclusivamente em `current_tenant.leads`; parâmetros de outra
conta não ampliam o acesso. Não é exigido acesso às configurações das integrações
para consultar os resultados do lead autorizado; a tela não exibe suas credenciais,
payloads completos ou URLs privadas. O cache da página segue `no-store` do admin.

A consulta é somente leitura, sem replay, edição, reenvio ou ativação de destinos.
A ausência de referências históricas não prova ausência de atendimento ou envio;
não foi realizado backfill. O componente compartilhado `ax_tracking_delivery`
reutiliza cards colapsáveis, badges, lista de estados e tabela `ax-*`.

## Segurança e limites

A referência não armazena contatos, payloads, credenciais nem URLs completas de
webhooks. Guarda um digest do destino e um rótulo seguro (host, measurement ID ou
dataset). Associações são validadas por tenant, com FKs e índices. Não recebe
identidade, consentimento, destino ou chave de ocorrência de parâmetros públicos.

Falhas de gravação são isoladas em savepoint, com log apenas da classe de erro:
não devem abortar cadastro, transação comercial ou envio. Essa proteção implica
que pode haver envio sem referência se o registro de auditoria falhar. Não há
promessa de auditoria infalível ou de processamento exatamente uma vez.

Esta etapa correlaciona capturas e conversões encaminhadas aos emissores existentes;
não converte todo evento de navegação em uma conversão, não registra motivos de
todos os gatilhos não elegíveis e não homologa containers externos. A escolha de
qual consulta recebe crédito pela venda continua a regra de atribuição existente.
