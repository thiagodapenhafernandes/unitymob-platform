# Ingresso de leads e efeitos

`Leads::Intake` é o centro existente para matching, deduplicação, referência do evento, complementação e lock por tenant. Receptores Meta, TikTok, LinkedIn, RD Station e portais adaptam contratos próprios antes de chamá-lo. `ManualCreate` usa matching, mas rejeita duplicata em vez de complementar.

Reentrega do mesmo evento e nova consulta do mesmo contato são situações distintas. Preservar responsável, funil, informações de origem e histórico de consultas conforme os testes de intake. Não substituir o lock por identidade sem medição de contenção.

A persistência de Lead mantém callbacks de auditoria, roteamento, exportação, automação e webhook. Flags como `skip_automatic_routing` são parte do contrato do consumidor e não foram removidas. Escritas por SQL direto/insert_all podem pular callbacks; não assumir cobertura desses caminhos.

A validação de novos leads registra a política Unitymob em `other_information.unitymob_data_processing_policy`; o cadastro manual pode escolher a base. Ver [política](../../integrations-legal-bases.md). O registro não comprova consentimento do titular nem substitui oposição/retirada.

`Leads::OutboundWebhook` seleciona eventos/destinos; `WebhookService` prepara o payload antes de enfileirar; o job entrega o mesmo payload durante retries, mantendo event_id. Templates personalizados de automação conservam contrato próprio. Ver [envelope e eventos](../../outbound-lead-webhook.md).

A correlação das tentativas de saída pertence ao `WebhookDeliveryJob`, não aos
controllers/receptores. IDs do envelope são preservados no retry; logs seguros
registram host e status HTTP, sem contato, caminho ou query do destino.

## Filtro de origens RD Station

Em `/admin/rd_station_integration`, a conta seleciona origens que não deseja receber
via RD, incluindo fontes personalizadas (uma por linha). A configuração é armazenada
em `rd_station.leads.blocked_sources`, sem fallback global, inicialmente vazia.
`RdStation::EntrySource` identifica a fonte por UTM/origem do contato ou do funil
(incluindo `Busca Paga | Google`); tags Meta conhecidas são fallback quando a fonte
não é informada. Campos de perfil social e nome do formulário não são evidência.
Comparações de fontes personalizadas são exatas, ignorando acentos, caixa e espaços
redundantes. Facebook e Instagram são agrupados em Meta.

O receptor verifica o filtro antes de `Leads::Intake`: uma origem bloqueada retorna
HTTP 200 com `ignored: true`, `reason: blocked_source` e `source`, sem criar lead,
complementar histórico ou redistribuir. As integrações diretas continuam independentes;
o filtro não altera registros anteriores nem desativa o webhook no RD.

Limite: o webhook RD entrega o perfil atual do contato, não uma prova da origem de
cada conversão. Tags podem persistir entre conversões; não inferir correlação exata
com uma conversão da Meta. Sem fonte confiável, a categoria é `unknown`, controlável
na tela. Referência: https://developers.rdstation.com/reference/webhooks-payload-mkt

## Página pública do corretor e conversão direta

Somente visitantes sem login da página pública do corretor recebem o vínculo
automático. `BrokerSitePage` carrega/reutiliza em lote `HabitationShareLink` dedicados
(prefixo `broker-page-`), separados dos compartilhamentos administrativos existentes.
Os helpers públicos mantêm esse contexto nos cards, links, menu e galeria. As chaves
de cache separam os tokens da grade/card; links expirados são substituídos ao renderizar.
Acesso logado à página usa os links normais, sem gerar o vínculo automático.

Ao abrir o imóvel pelo link dessa página, o token permanece explícito na URL e no
formulário. Ele não é salvo como cookie de atribuição: voltar ao imóvel/listagem normal
não carrega o dono da página. A conversão logada também ignora esse tipo de vínculo.
A captura obrigatória adicionada vale apenas para tokens `broker-page-`; opções de
captura e compartilhamento comuns conservam o comportamento anterior.

`LeadsController#apply_share_attribution` valida token ativo, imóvel, conta e corretor
ativo. Somente os tokens dedicados têm a nova precedência na reentrada por
`RoutingService.assign_shared_inquiry!`: reutiliza o cadastro, atribui ao dono do link,
limpa arquivamento/contingência/distribuição e registra o responsável anterior. Entradas
comuns do site continuam passando pelas regras de distribuição existentes; um cookie
com token dedicado não concede atribuição automática. Os compartilhamentos manuais
preexistentes mantêm seu contrato, sem receber essa nova precedência na reentrada.
