# Ingresso de leads e efeitos

`Leads::Intake` é o centro existente para matching, deduplicação, referência do evento, complementação e lock por tenant. Receptores Meta, TikTok, LinkedIn, RD Station e portais adaptam contratos próprios antes de chamá-lo. `ManualCreate` usa matching, mas rejeita duplicata em vez de complementar.

Reentrega do mesmo evento e nova consulta do mesmo contato são situações distintas. Preservar responsável, funil, informações de origem e histórico de consultas conforme os testes de intake. Não substituir o lock por identidade sem medição de contenção.

A persistência de Lead mantém callbacks de auditoria, roteamento, exportação, automação e webhook. Flags como `skip_automatic_routing` são parte do contrato do consumidor e não foram removidas. Escritas por SQL direto/insert_all podem pular callbacks; não assumir cobertura desses caminhos.

A validação de novos leads registra a política Unitymob em `other_information.unitymob_data_processing_policy`; o cadastro manual pode escolher a base. Ver [política](../../integrations-legal-bases.md). O registro não comprova consentimento do titular nem substitui oposição/retirada.

`Leads::OutboundWebhook` seleciona eventos/destinos; `WebhookService` prepara o payload antes de enfileirar; o job entrega o mesmo payload durante retries, mantendo event_id. Templates personalizados de automação conservam contrato próprio. Ver [envelope e eventos](../../outbound-lead-webhook.md).
