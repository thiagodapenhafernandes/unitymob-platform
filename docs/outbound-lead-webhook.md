# Webhook de saída: captura e rastreamento

O contrato legado `origin_form`, `timestamp`, `source` e `data` permanece.
A ampliação adiciona no nível principal:

- `event_name`: `lead_created` para nova captura WhatsApp; `lead_inquiry` para consulta complementar; `form_submitted` para os demais formulários (o nome original continua em `origin_form`). O teste administrativo envia `test_webhook`.
- `event_id`: UUID por envio, compartilhado pelos destinos e preservado no payload durante retries. Não é um identificador de qualificação nem deduplica duas consultas diferentes.
- `transaction_id`: mesmo UUID de `event_id`, compartilhado pelos destinos e preservado nos retries. No GTM, mapear para o ID da transação da tag Google Ads (ou `order_id` ao usar a API). Não deduplica eventos gerados separadamente.
- `event_timestamp`: Unix em segundos; `timestamp` continua ISO 8601.
- `action_source`: `website` com request de navegador; `system_generated` sem request.
- `lead_id`, `business_type`, `property_id`, `property_code`: quando disponíveis. No envelope, `sale`/`rent` são traduzidos para `venda`/`locacao`; o valor original permanece em `data`. `property_id` agora contém o código público do imóvel (também em `property_code`), não o ID do banco. Consumidores que usavam o ID interno devem ler `data.property_id`.
- UTMs e IDs de clique suportados por `Leads::Attribution::TRACKING_KEYS`, incluindo `gclid`, `gbraid`, `wbraid`, `fbclid`, `msclkid` e `ttclid`, provenientes do payload/atribuição salva ou query do request.
- `client_ip_address` e `client_user_agent`: do request original, persistidos na atribuição do lead para eventos posteriores; nunca do servidor de entrega do webhook.
- `fbc`, `fbp`: cookies `_fbc` e `_fbp` existentes, somente com `unitymob_lgpd_consent=accepted`.
- Os identificadores de navegador autorizados são persistidos na atribuição do lead para eventos posteriores sem request. A finalidade e o placement da captura também são preservados. Não há backfill de dados que não foram coletados.
- `client_id`: extraído de `_ga` no formato `GA<versão>.<domínio>.<id>.<timestamp>`, sob o mesmo consentimento.
- `placement`: quando o chamador envia esse contexto. `/leads` aceita `lead.placement` textual, limitado a 128 caracteres; os botões atuais não passam esse campo automaticamente.

Campos indisponíveis são omitidos. Não são criados cookies nem inventados IDs.
`user_data` nos eventos de lead inclui email_address, phone_number normalizado com +, external_id e address.first_name/last_name. O sobrenome é o restante do nome informado. Campos ausentes são omitidos; formulários genéricos e testes administrativos não são apresentados como leads. Os dados originais permanecem em `data`.
IP e identificadores de navegador também são dados de rastreamento vinculáveis a pessoas.
`value` é enviado somente quando fornecido pelo chamador; nesse caso `currency` usa a moeda informada ou BRL. Não usamos o preço do imóvel como valor de conversão. O teste sintético continua identificado como test_webhook; o exemplo completo de lead fica no preview da configuração.

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

## Base legal declarada no webhook

Os novos payloads declaram a política padrão solicitada para processamento operacional:

```json
{
  "legal_bases": [
    { "category": "data_processing", "type": "legitimate_interest", "status": "granted" }
  ]
}
```

`granted` é o status do contrato de intercâmbio, qualificado pelo `type`;
não representa checkbox marcado ou prova de consentimento do titular.
O backend declara essa política em cada payload e não aceita sobrescrita
por parâmetros públicos do formulário. O mesmo campo aparece nos exemplos
e no teste sintético. O job conserva a declaração durante retries.

Escopo de envio deste campo: `WebhookService` e payload padrão de automação, inclusive destinos explícitos de
formulários que usam esse serviço. O registro compartilhado de novas entradas está
detalhado em `docs/integrations-legal-bases.md`. Não altera APIs de outros fornecedores,
não cria registros retroativos e não cadastra bases legais no RD Station CRM.
A integração RD atual recebe leads; encaminhar esse JSON a um intermediário
não significa que ele foi registrado no contato do RD.

A finalidade pretendida é atender e acompanhar uma solicitação comercial.
O controlador da conta deve verificar a adequação da política a cada destino,
tipo de formulário e finalidade, inclusive formulários de carreira ou parceria.
Declarar o padrão não executa teste de balanceamento nem comprova conformidade.
A avaliação deve documentar finalidade, necessidade, expectativas do titular,
balanceamento e salvaguardas. Legítimo interesse não é base para dados sensíveis.

Não declaramos `communications`: esse campo não autoriza campanhas indiscriminadas.
Também não convertemos aceite de cookies em consentimento para comunicação ou
compartilhamento. Os cookies analíticos seguem exigindo o aceite já implementado;
recusá-los não gera `consent: granted` nem libera a leitura desses identificadores.

Para adotar `consent` em outra finalidade, antes será necessário registrar a
manifestação específica: finalidade, texto/versão apresentado, origem, momento
do aceite e mecanismo de retirada. Na ausência dessa evidência, não inventar
consentimento. Esta entrega não implementa esse registro nem gestão de oposição.
Uma oposição ao tratamento precisa ser atendida antes de novos compartilhamentos;
a declaração padrão não substitui esse procedimento.

Referências:
- ANPD: https://www.gov.br/anpd/pt-br/assuntos/noticias/anpd-lanca-guia-orientativo-sobre-legitimo-interesse

As opções e identificadores deste payload pertencem ao contrato da Unitymob Platform, definido em `Privacy::LegalBases::OPTIONS`; não dependem de uma integração com o RD.

### Cadastro manual

O cadastro manual oferece o select **Base legal para tratamento de dados**, com labels em português e padrão **Legítimo interesse**. A escolha é validada no servidor e persistida em `other_information.unitymob_data_processing_policy`, com origem `manual_registration`, versão e horário. Os webhooks padrão usam essa base registrada; cadastros sem declaração continuam com o padrão. Não há migration nem alteração retroativa.

Opções: Legítimo interesse (`legitimate_interest`), Consentimento (`consent`), Contrato preexistente (`pre_existent_contract`), Processo judicial (`judicial_process`), Interesse público (`public_interest`) e Proteção da vida (`vital_interest`). A seleção de consentimento é declaração do operador, não coleta ou comprovação da autorização; registre a evidência nas observações. O select se aplica ao cadastro, não altera a base de leads existentes.

## Diagnóstico no GTM server-side

HTTP 2xx confirma a aceitação pelo endpoint, não que o cliente do container tenha
interpretado o JSON ou que uma tag tenha disparado. Correlacione `event_id` nos
logs do destino e na prévia do container, verificando cliente, dados do evento,
gatilhos e resultado das tags. Uma requisição normal de produção não é garantia
de aparecer na sessão de prévia; siga o procedimento do container para debug.

A captura usa `lead_created` ou `lead_inquiry`. `qualified_lead` corresponde à
qualificação no CRM e exige seleção desse evento na configuração do webhook.
`test_webhook` é diagnóstico e não deve ser configurado como conversão real.

## Correlação de entrega

`WebhookDeliveryJob` emite `[WEBHOOK_DELIVERY]` seguido de JSON com `event_name`,
`event_id`, `transaction_id`, `origin_form`, `destination_host`, `http_status`,
`status` e `attempt`. Aceita payload com chaves string ou symbol. O destino é
somente o host: caminho, query, contatos e mensagem bruta do transporte não são
registrados. `failed` mantém DeliveryError e o retry existente de cinco tentativas.

`delivered` significa resposta HTTP de sucesso; não comprova que o consumidor
interpretou o evento ou disparou tags. Correlacionar o mesmo event_id no destino.
Eventos antigos sem IDs continuam entregáveis e aparecem com IDs nulos.
Não há backfill de logs nem armazenamento adicional de payloads pessoais.

O botão de teste do admin envia sempre dados fictícios completos (contato, imóvel, valor, IDs de anúncios, cookies e contexto HTTP), com `event_name: test_webhook` e `diagnostic: true`. Cada clique recebe IDs novos, sem criar lead ou alterar uma etapa. O receptor deve excluir eventos de diagnóstico das conversões reais. Os identificadores de anúncio de teste não correspondem a cliques válidos.
