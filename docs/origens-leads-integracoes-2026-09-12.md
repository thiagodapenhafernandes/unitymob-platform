# Origens de leads — implementação e auditoria

Data: 12/09/2026. Escopo visual final: **somente a coluna de origens da listagem**. Ficha, kanban, cards mobile, timeline, filtros, BI e demais colunas conservam sua interface. O componente e o helper são compartilhados, mas somente a coluna os utiliza nesta entrega. A consulta de produção foi somente leitura; não houve deploy, backfill, envio de mensagens ou alteração de configuração.

## Matriz verificada

| Fluxo | Salute (tenant 1) | Conexão (tenant 72) | Implementação e limite |
|---|---|---|---|
| WhatsApp Cloud API | Conexão registrada como connected, token e número configurados | Mesma situação | Webhooks::WhatsappController → Whatsapp::InboundWebhookJob → InboundProcessor. Estado configurado não equivale a teste de envio realizado nesta auditoria. |
| CTWA | Nenhum lead com CTWA no nome de origem/atribuição no recorte consultado | 521 leads com CTWA no nome de origem/atribuição | Contagens são de registros legados, não prova de referral nativo. Antes desta mudança o processor só usava referral para a janela de entrada. Agora preserva campos de referência na mensagem e uma captura inicial no lead novo. |
| Meta Lead Ads | Integração 3, token presente, validade local não expirada; nove páginas, sete sem token, duas com token; 924 e 149 formulários nas páginas com token | Integração 4, token presente, validade local não expirada; uma página com token e 149 formulários | MetaLeadProcessingJob já recebe leads; MetaSyncJob sincroniza formulários por página. Esta entrega reaproveita o cache da conta/página na coluna. |
| Nome de campanha/anúncio por Graph | Nenhuma conta de anúncios configurada na integração | Nenhuma conta de anúncios configurada na integração | MetaLeadEnrichmentJob é reaproveitado para CTWA, com validação de account_id. Sem integração elegível não consulta nem inventa nomes. Exibe headline/ID do anúncio quando recebido. |
| Formulário 873698782478495 | Página 198612244396795 sem token próprio, nome ausente no cache. Nova consulta read-only retornou código 100/subcódigo 33 | Não é referência da conta | ID continua como fallback. Existem outras páginas acessíveis na Salute; não é uma falha de todas as páginas. O retorno não determina sozinho a causa. |
| Site | 385 eventos SEO lead_created associados à conta | 11 eventos SEO lead_created associados à conta | LeadsController é o único emissor desse evento. A coluna consulta em lote o primeiro evento, seu imóvel e sua página, sem usar o imóvel atual como prova. A navegação posterior não altera a classificação. |
| RD Station | Loader de rastreamento desativado | Loader de rastreamento desativado | TrackingIntegrationSetting e layouts/_tracking_head suportam script de rastreamento. Não foi encontrado conector dedicado de ingestão de leads RD. Nomes legados continuam exibíveis; não indicam conexão ativa. |
| Portais | Feeds habilitados para VivaReal, Imovelweb/2, Chaves na Mão, Casa Mineira e Lais Ai; ZAP e Netimoveis2 desabilitados | Feeds listados desabilitados | PortalIntegration, feeds e Webhooks::PortalsController tratam publicação/status de anúncios. Esse webhook não cria leads. Não confundir feed habilitado com recebimento de leads do portal. |
| Importações | Fontes preservadas em external_lead_migration | Mesmo fluxo, incluindo origens CTWA legadas | ExternalLeadMigration::LeadMapper guarda fonte/canal e payload original. Na coluna, o fornecedor técnico é sempre apresentado como Importação, inclusive nos detalhes. |
| Cadastro manual / Showroom | Fluxos locais e fontes informadas | Mesma regra | Não exigem conector nem ganham origem digital por suposição. |

As demais contas utilizam os mesmos helpers, queries escopadas, identidade configurada e fallbacks. Não foram auditadas individualmente em produção. A presença de configuração ou registro não foi apresentada como comprovação de autenticação remota ou conversão nova.

## Comportamento implementado

- Marca, nome, subtipo e complemento ficam na coluna de origens. Ciclo inicia fechado; a segunda linha não repete WhatsApp.
- Modal e formulário WhatsApp dentro do Site continuam Site. A página é mostrada sem query/fragmento; o imóvel só vem do evento original escopado. Site Salute Imóveis e Site Conexão BC usam a identidade da conta e o favicon, com fallback de logo/ícone funcional.
- Site tem prioridade apenas com evidência de conversão no site ou rótulos legados explícitos; uma visita posterior ou canal Internet não basta.
- WhatsApp sem indicação de campanha/referral não ganha Orgânico por ausência de evidência. Subtipos CTWA, Orgânico, Campanha e Importação preservam a informação disponível.
- CTWA com plataforma explicitamente registrada mantém Instagram ou Facebook. Referência de anúncio sem plataforma identificada aparece como WhatsApp · CTWA. source_url ou source_id isolados não comprovam Instagram.
- O referral preservado contém source_type, source_id, source_url, headline, body e ctwa_clid quando recebidos como strings. Campos arbitrários não são copiados. Uma referência source_type=post não vira anúncio CTWA.
- A mensagem guarda sua referência mesmo quando o contato já existe. Somente leads novos recebem whatsapp_entry. Mensagem repetida continua deduplicada pelo contrato existente; anúncios posteriores não substituem a aquisição inicial.
- Enriquecimento assíncrono reaproveita o job Meta e seu retry limitado. Não há consulta remota na renderização. Erro ao enfileirar enriquecimento não interrompe o registro de atividade nem as automações de mensagem existentes.
- Nenhum campo de origem persistido, responsável, status, filtro ou relatório foi renomeado. O fornecedor da importação é traduzido apenas na apresentação da coluna.
- Campanha/anúncio/formulário conhecidos têm seus nomes apresentados. ID de anúncio não vira ID de formulário. Formulário importado sem nome conserva ID e não usa título do imóvel como substituto.
- Portais individuais têm suas marcas; Grupo Zap genérico permanece Grupo Zap. RD Station e fontes personalizadas continuam válidos como nomes registrados sem prometer um conector ativo.

## Pendências de configuração e conectores futuros

1. **Salute / formulário específico:** recuperar acesso válido à página e executar a sincronização existente após configuração apropriada. Não foi disparada sincronização nem recuperado nome nesta entrega.
2. **CTWA / nomes por Graph:** configurar conta de anúncios na integração da conta e permissões de leitura necessárias. O job só aceita resposta cujo account_id corresponda à integração. Sem isso, preserva dados do webhook e o fallback por ID. A API não garante a plataforma de veiculação pelo simples ID do anúncio; não a inferimos.
3. **RD Station:** um conector de leads é projeto separado do loader. Definir produto/modalidade, autenticação, assinatura/validação do webhook, evento de conversão, IDs externos e contrato de campos. Depois implementar configuração por tenant, deduplicação, retry, observabilidade e associação de campanha/página com testes. Dados legados já funcionam na coluna sem esse conector.
4. **Portais:** negociar/verificar o contrato de leads de cada portal, independentemente do feed de imóveis. Definir autenticação, identificador de entrega, campo que distingue ZAP/VivaReal, código de imóvel, data e dados de contato; então criar ingestão idempotente por conta com testes. Não reutilizar o webhook de status como se recebesse leads.
5. **Histórico CTWA:** referências que nunca foram persistidas não podem ser reconstruídas a partir do nome do contato ou do imóvel atual. Nenhum backfill automático foi criado.

## Arquivos e operação

- `app/helpers/admin/lead_origin_helper.rb`: apresentação da coluna e consultas em lote.
- `app/views/admin/shared/ui/_lead_origin.html.erb`: componente reutilizável, consumido apenas por `admin/leads/_table`.
- `app/services/whatsapp/inbound_processor.rb`: preservação de referral e captura inicial dos leads novos.
- `app/jobs/meta_lead_enrichment_job.rb`: aproveitamento do anúncio CTWA original no fluxo de enriquecimento existente.
- Migration `20260912180000_add_referral_to_whatsapp_messages`: JSONB vazio por padrão, sem reprocessar registros existentes. Deve preceder a execução do código novo no deploy. Rollback remove apenas essa coluna; não executar rollback após capturar dados reais sem avaliar a perda dessas referências.

Referência de API: [coleção oficial WhatsApp Cloud API da Meta](https://www.postman.com/meta/whatsapp-business-platform/documentation/wlk6lh4/whatsapp-cloud-api). O payload tratado é o da Cloud API já usada pelo projeto; não foi presumido contrato de outros provedores.

Assets: marcas Meta/Instagram/WhatsApp já existentes preservadas. ZAP, Imovelweb e VivaReal reaproveitam os favicons dos respectivos domínios usados no preview aprovado (obtidos pelo cache de favicons do Google); RD Station e Chaves na Mão usam seus favicons oficiais. Os arquivos ficam locais, sem consulta remota por lead. Origens sem marca usam ícones funcionais existentes.

## Complemento — consultas oficiais CTWA

Em 12/09/2026, consultas GET a `me/permissions` e `me/adaccounts` com as integrações existentes confirmaram `ads_read` e `ads_management` concedidas em Salute e Conexão. A primeira página retornou 100 contas de anúncios em cada integração; isso não determina qual pertence ao tenant. Nenhuma conta foi selecionada automaticamente, e nenhuma configuração de produção foi alterada. O bloqueio atual do enriquecimento é o vínculo explícito de `ad_account_id`, não a ausência dessas permissões.

O [exemplo oficial de recebimento CTWA da Meta](https://www.postman.com/meta/whatsapp-business-platform/request/g7sv9jo/received-message-triggered-by-click-to-whatsapp-ads) confirma o referral com ID, tipo, URL e título do anúncio. Esse contrato não oferece um campo de plataforma de veiculação por mensagem. URL do criativo, presença de uma conta Instagram ou estatísticas agregadas não provam que aquele contato clicou no Instagram. Assim, a entrada nativa fica `WhatsApp · CTWA` com o anúncio conhecido; fontes legadas explicitamente identificadas continuam `Instagram · CTWA` ou `Facebook · CTWA`. Isso recebe leads de anúncios que encaminham ao WhatsApp, incluindo Instagram, sem inventar a plataforma. Não implementa mensagens diretas do Instagram, que são outro canal.

O código de captura está implementado localmente. Para validar ponta a ponta em produção, publicar a migration/código, vincular a conta de anúncios correta e conferir uma mensagem real originada de anúncio. Não foi enviada mensagem nem criado lead de teste em produção.

## Validação da implementação

- Rodada final: **166 exemplos, zero falhas**, cobrindo listagem administrativa, helper da coluna, webhook WhatsApp, deduplicação/BSUID e enriquecimento Meta.
- Rodada ampliada: 180 exemplos, com quatro falhas reproduzidas nos mesmos testes no HEAD anterior `86d8fc89`: resolução do telefone público por tenant, duas expectativas de captura pública com 403 e um double incompleto no teste de atribuição. Essas falhas não foram corrigidas neste escopo.
- Build CSS, `zeitwerk:check` e `git diff --check` concluídos com sucesso.
- Conferência visual local com registros existentes confirmou favicon da conta, formulário por nome/ID, contexto de imóvel do evento e ciclo fechado por padrão. Ao expandir o ciclo, a linha cresce sem sobrepor a próxima. As demais colunas mantêm composição e largura.
- Migration aplicada apenas nos bancos locais de desenvolvimento e teste. Sem deploy, alteração de configuração, backfill ou envio de mensagem em produção.

## Diagnóstico de permissões na configuração Meta

A tela Integrações Meta agora oferece Verificar permissões e Atualizar autorização. A consulta é sob demanda, usa somente a integração do usuário na conta atual e distingue permissão concedida, recusada, expirada e ausente. Falha de rede/API é apresentada como diagnóstico indisponível, sem concluir que permissões foram recusadas. `ads_read` é aceito como alternativa para leitura de anúncios. Não há exposição do token nem alteração de inscrições por esse diagnóstico.

O login Facebook passa a solicitar `instagram_basic` e `instagram_manage_messages`, preservando os escopos anteriores. O botão de atualização usa `auth_type=rerequest`, suportado pela estratégia OmniAuth Facebook instalada. É necessária nova autorização do usuário; permissões não são concedidas automaticamente.

As instruções explicam seleção das páginas, vínculo profissional, acesso às mensagens e a diferença entre reautorização e aprovação/acesso avançado do aplicativo. Referência: [requisitos oficiais de Instagram Messaging via Facebook Login](https://www.postman.com/meta/messenger-platform-api/folder/22794852-255610cd-47f5-4f4d-b3fa-71aec360be9a). O diagnóstico não verifica App Review nem prova saúde do token de cada página e não apresenta o Direct como ativo.

Validação deste complemento: 14 testes passaram (serviço e requisições), `zeitwerk:check` e `git diff --check` passaram. Sem novos estilos, dependências ou migration; componentes administrativos existentes reutilizados. O processo Rails deve ser reiniciado para carregar os novos escopos do initializer. Sem deploy nesta etapa.

## Correção da versão no login Facebook

O initializer do Devise agora configura `client_options.site`, `authorize_url` e `token_url` explicitamente. A opção `api_version`, ignorada pela estratégia instalada, foi removida. Login, troca de token e consultas de perfil passam a respeitar `META_API_VERSION`, com fallback v24.0, em vez do padrão v19.0 da gem. Nenhuma versão de produção foi alterada. Reiniciar o processo Rails após publicar para carregar a configuração.

Validação: 12 testes passaram, incluindo URLs efetivas do cliente OAuth e requisições da configuração Meta. O teste de URLs também foi executado com sobrescrita de versão via ambiente.

## Instagram Direct — implementação de recebimento

Implementados descoberta do Instagram profissional na sincronização de páginas e por botão, ativação explícita por página e processamento assíncrono das mensagens. A configuração fica dentro de cada página em Integrações Meta. A ativação registra rota pelo Instagram ID quando há gateway, preserva as inscrições atuais da página ao adicionar `messages` e consulta novamente a Meta para confirmar a inscrição. A configuração do objeto Instagram/callback no App Dashboard e a autorização do usuário continuam necessárias. A ausência de evento recebido não é apresentada como prova de funcionamento.

O gateway agora extrai eventos do objeto `instagram` e encaminha um corpo separado por mensagem/perfil, assinado com a credencial de encaminhamento existente. Formulários `leadgen` mantêm seu contrato. O CRM valida a assinatura antes de agendar o job; falha ao agendar Direct retorna 503 para reentrega. É necessário publicar o gateway separadamente quando esse modo estiver em uso.

O lead é criado sem telefone fictício, com identidade composta por tenant, perfil profissional e remetente Instagram. Mensagens repetidas não duplicam registros; ecos e notificações sem mensagem são ignorados. Leads já identificados mantêm nome, status, responsável e origem. Não há associação por nome, captura retroativa nem resposta automática. O nome inicial é Contato Instagram; não fazemos consulta adicional de perfil do remetente nesta etapa. Texto recebido fica em instagram_messages, sem criar uma Inbox. Contexto do primeiro recebimento permite mostrar Instagram · Direct, referência de anúncio ou resposta a story na coluna existente, quando disponível.

A desativação é local: interrompe o processamento do perfil, sem remover as inscrições compartilhadas da página ou os formulários. Um índice único impede ativar o mesmo perfil em duas conexões no mesmo banco; o roteamento do gateway continua responsável por vincular o perfil ao destino correto entre servidores.

Migration 20260912210000 aplicada apenas em desenvolvimento/teste. Conferência visual da seção Instagram feita no ambiente local. Validação: rodada de 44 testes passou; testes adicionais de roteamento isolado no gateway e de confirmação da ativação também passaram; zeitwerk:check concluído. Nenhuma inscrição real foi criada, nenhum Direct foi enviado e não houve deploy. Permissões/tokens de produção pendentes ainda precisam ser regularizados para o teste ponta a ponta.

Contrato consultado: documentação oficial Meta/Postman de Instagram via Facebook Login e Conversations API; o SDK oficial `facebook/facebook-python-business-sdk`, Page, também documenta o endpoint subscribed_apps. Não foram misturados tokens ou endpoints do fluxo Instagram Login.

### Seleção de conta de anúncios pela API

A seção Conta de anúncios consulta `me/adaccounts` com paginação em um Turbo Frame e apresenta nome e ID para seleção. Nenhuma conta é escolhida automaticamente. O vínculo atual é preservado mesmo quando não aparece na resposta; salvar continua validando acesso ao ID pela Meta. Lista vazia, token recusado, permissão recusada e indisponibilidade recebem orientações distintas. A consulta é restrita à integração do usuário e da conta atual. Não houve alteração de configurações de produção.

### Falhas parciais da sincronização

A requisição continua apenas enfileirando `MetaSyncJob`. Falhas na descoberta do Instagram não interrompem formulários; falhas na consulta de formulários não impedem a tentativa de inscrição do webhook nem as páginas seguintes. Falhas de registro no gateway também entram nas pendências. O estado `partial` mantém orientações visíveis na seção de progresso e não agenda sua remoção automática. O reset de sucesso verifica a execução concluída para não apagar o status de uma execução posterior. A busca inicial de páginas continua sendo uma dependência da sincronização: sua falha marca a execução como falha, sem desativar canais existentes.

### Aviso persistente ao retornar à integração

`last_sync_error` conserva o motivo seguro da falha de sincronização, incluindo falha no enfileiramento, falha fatal e pendências parciais. É renderizado a partir do banco ao abrir a tela, inclusive durante nova tentativa. Só uma sincronização sem pendências limpa o campo; o reset do aviso de sucesso não o modifica. Não são exibidas mensagens brutas da API, tokens ou URLs internas. Migração aplicada apenas nos bancos locais de desenvolvimento e teste. Validação: 23 exemplos e `zeitwerk:check` passaram.
