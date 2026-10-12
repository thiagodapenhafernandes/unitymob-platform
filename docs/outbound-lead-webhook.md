# Webhook de saída: captura e rastreamento

O contrato legado `origin_form`, `timestamp`, `source` e `data` permanece.
A ampliação adiciona no nível principal:

- `event_name`: `lead_created` para nova captura WhatsApp; `lead_inquiry` para consulta complementar; `form_submitted` para os demais formulários (o nome original continua em `origin_form`). O teste administrativo envia `test_webhook`.
- `event_id`: UUID por envio, compartilhado pelos destinos e preservado no payload durante retries. Não é um identificador de qualificação nem deduplica duas consultas diferentes.
- `event_timestamp`: Unix em segundos; `timestamp` continua ISO 8601.
- `action_source`: `website` com request de navegador; `system_generated` sem request.
- `lead_id`, `business_type`, `property_id`, `property_code`: quando disponíveis. Tipos de negócio existentes (`sale`/`rent`) são preservados.
- UTMs e IDs de clique suportados por `Leads::Attribution::TRACKING_KEYS`, incluindo `gclid`, `gbraid`, `wbraid`, `fbclid`, `msclkid` e `ttclid`, provenientes do payload/atribuição salva ou query do request.
- `client_ip_address` e `client_user_agent`: do request original, nunca do servidor de entrega do webhook.
- `fbc`, `fbp`: cookies `_fbc` e `_fbp` existentes, somente com `unitymob_lgpd_consent=accepted`.
- `client_id`: extraído de `_ga` no formato `GA<versão>.<domínio>.<id>.<timestamp>`, sob o mesmo consentimento.
- `placement`: quando o chamador envia esse contexto. `/leads` aceita `lead.placement` textual, limitado a 128 caracteres; os botões atuais não passam esse campo automaticamente.

Campos indisponíveis são omitidos. Não são criados cookies nem inventados IDs.
A expansão não adiciona `user_data`, nome, telefone ou e-mail ao nível principal;
os dados pessoais que já existiam em `data` permanecem no contrato legado.
IP e identificadores de navegador também são dados de rastreamento vinculáveis a pessoas.
Não há atribuição automática de valor monetário ou moeda.

## Eventos selecionáveis por configuração

`subscribed_events` controla os disparos. Configurações existentes recebem por padrão
`lead_created`, `lead_inquiry` e `form_submitted`, preservando as capturas.
Eventos opcionais do CRM:

- `lead_stage_changed`: status ou etapa mudou em uma atualização salva do lead.
- `lead_qualification_changed`: corretor ou gestor mudou sua avaliação.
- `qualified_lead`: uma dessas avaliações mudou para `qualified`; não é inferido pelo nome da etapa.

Os eventos de CRM são disparados após commit, usam o tenant do lead e incluem
`data.changes` com `from` e `to`. As duas avaliações atuais permanecem em `data`.
Se dois eventos selecionados corresponderem à mesma atualização, há dois envios com IDs distintos.
Os filtros de formulários continuam valendo para a captura; eventos de CRM seguem a conta inteira.
Operações de importação que suprimem roteamento e atualizações SQL diretas (`update_all`/`update_columns`)
não acionam callbacks de mudança; não há backfill de eventos antigos.
Desativar a configuração impede novos enfileiramentos; jobs já na fila mantêm seu payload/destino.

A validade dos links de corretor é configurada em `/admin/lead_setting/edit`,
na seção Compartilhamento, usando a mesma chave `lead_share_tracking_days`.

O botão de teste inclui UTMs de teste e `TEST_GCLID`, sem simular um lead real.
A edição e a criação mostram o payload completo por evento, com dados fictícios,
gerado pelo mesmo montador usado no envio. Valores opcionais reais podem estar ausentes.
O receptor (por exemplo, GTM server-side) precisa mapear os campos JSON recebidos;
a interface de preview do GTM não é o payload bruto enviado pelo Rails.
