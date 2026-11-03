# Diagnóstico de rastreamento e conversões por conta — 29/10/2026

## Escopo e evidência

Comparação do arquivo `camada-de-dados-e-payload-crm.md` e das duas imagens de 27/10, enviadas por Grasiele, com o código local atual. Análise de aplicação compartilhada: nenhuma URL, conta ou funil deve ser fixado para Salute. Não houve acesso à configuração atual de produção, envio HTTP de teste, replay, mudança de conta ou deploy. Alterações locais preexistentes foram preservadas; não confundir código local com release publicada.

## Diagnóstico principal

Há dois caminhos diferentes: webhook geral (`WebhookService`) e conversões Google por etapa (`GoogleConversions::Recorder`). Compartilham a configuração de destino, mas têm contratos, habilitação e transporte distintos. Webhook ativo e teste geral bem-sucedido não comprovam ativação ou funcionamento de conversões por etapa.

A imagem mostra integração Google pausada e gatilho por qualificação, enquanto a mensagem relata teste por movimentação de etapa. O dispatcher exige `enabled` e `google_conversions_enabled` no webhook da conta, etapa ativa do próprio funil e ação correspondente ao gatilho. Portanto são hipóteses fortes de configuração, não causa de produção comprovada. Depois dessas condições ainda há bloqueios por modalidade e e-mail original.

## Lacunas confirmadas no código

| Prioridade | Evidência | Ajuste recomendado |
|---|---|---|
| Alta | `GoogleConversions::Recorder.business_type` traduz locação para `aluguel`; `Leads::Attribution` usa `locacao`. | Usar tradução canônica compartilhada. Preservar valores internos e tratar dados persistidos legados na leitura, sem backfill automático. |
| Alta | Recorder omite `lead_stage`, `lead_channel`, `external_id`, UTMs comuns, contexto do visitante e campos do imóvel. | Evoluir montador compartilhado de contexto; manter envelopes específicos e snapshots imutáveis. Não substituir o webhook geral pelo de conversões. |
| Alta | Recorder ignora evento sem e-mail válido no audit de criação, mesmo que telefone seja válido. | Definir elegibilidade por identificadores realmente aceitos no contrato do destino; mostrar motivo ao operador. Não exigir e-mail universalmente em formulários WhatsApp nem usar e-mail editado sem decisão de identidade. |
| Alta | `_tracking_head` retorna lista fixa de campos, sem `user_data`, `transaction_id`, `lead_id` ou `ecommerce`; captura confirma apenas UUID e dados mínimos. | Produzir evento confirmado com ID estável ligado ao lead, repassar campos permitidos e limpar dados do evento anterior. Não contar consulta complementar como novo lead sem mudar explicitamente a regra atual. |
| Alta | Não há implementação encontrada de `view_item`, contexto `page_type`/`site_language`, filtros/resultados e atualização do contexto no Turbo nos pontos compartilhados inspecionados. | Contexto antes do loader e eventos compartilhados para páginas/listagens/imóveis de todos os temas, respeitando consentimento e evitando page_view duplicado com GTM. |
| Média | Teste administrativo usa `WebhookTestForm`/`WebhookService`, não o montador de conversão por etapa; não aceita `utm_content`, etapa ou data de conversão. | Teste por tipo de evento, usando o mesmo serializer do fluxo real, dados sintéticos e UID editável; destino salvo da própria conta. |
| Média | UI oferece switches e gatilhos, mas não há tela encontrada para histórico de `GoogleStageConversionEvent`. | Mostrar destino efetivo, ativação, evento/gatilho por funil, pendências, falhas e motivos de descarte, com acesso restrito. HTTP 2xx não equivale a conversão aceita pelo provedor. |
| Média | Data de conversão usa espaço entre data/hora; nomes preservam acentos; fechamento sem comissão omite valor. | ISO 8601, normalização de identidade específica do contrato e política explícita para valor ausente. Não trocar silenciosamente IDs/sufixos já usados na deduplicação. |
| Média | Contrato geral usa código público em `property_id`; arquivo pede ID interno. | Definir versão/compatibilidade: preservar consumidores atuais e expor identificador interno separado ou em contrato novo. |

## O que já está disponível e deve ser reutilizado

- Destino de conversão, ativação e segredo criptografado por conta; exclusividade de um destino Google por conta.
- Evento e gatilho por etapa/funil; componente `admin/shared/ui/_stage_conversion_fields` compartilhado.
- Outbox criptografada, deduplicação por lead/marco, retries, recuperação e validação de tenant no registro e no job.
- UID original com prioridade cookie `user_id_mh`, campo, URL; preservação do primeiro UID e lista de novas consultas. Dados gerados depois do POST não chegam retroativamente.
- Captura existente de IP, user agent, landing URL, UTMs, click IDs; cookies de navegador condicionados ao consentimento. O recorder offline ainda não os incorpora.
- Comissão real em centavos; mudanças locais adicionais em fechamento e qualificação tardia ainda precisam de conferência de publicação.

## O que deve ser gerenciável na interface

1. **Conta / Integrações:** destino efetivo salvo, ativo/pausado, segredo, GTM/Stape e provedor responsável pelo transporte. Manter um destino Google nesta entrega; múltiplos destinos não foram demonstrados como necessidade.
2. **Funil / etapa:** evento comercial e momento do disparo independentes para cada provedor, com resumo legível. Mover para etapa não deve ser confundido com visita realizada ou qualificação efetiva.
3. **Conta / rastreamento:** se houver envio ampliado de identificadores e dados pessoais, configuração explícita do escopo de dados permitido por destino e informação do consentimento capturado. Nunca criar campos de código JS livre ou permitir sobrescrever consentimento por formulário público.
4. **Operação / fechamento:** valor real e sua origem/regra de negócio, com mesma política entre desktop/mobile. Começar pela comissão real já existente; não implementar fórmula financeira genérica sem necessidade confirmada.
5. **Diagnóstico:** evento sintético, UID escolhido, payload efetivamente enviado com proteção de dados, resultado HTTP, motivo de bloqueio e histórico por conta. Reenvio de evento real deve ser ação separada, autorizada e deduplicada.

Não tornar gerenciável: nomes arbitrários de chaves, snake_case, moeda BRL para operação brasileira, serialização de números/datas, validação E.164, isolamento de tenant, idempotência e regras de segurança. São contratos/invariantes da plataforma, não opções de cada conta. Adotar alteração de contrato com compatibilidade/versionamento por integração quando necessário.

## Decisões de domínio pendentes

- Imóvel venda e locação: a plataforma suporta `sale_rent`/`venda_locacao`. O pedido de somente duas modalidades não autoriza apagar esse caso. Usar intenção do contexto selecionado; sem evidência não presumir venda.
- Canal de captura (`site_modal`, portal, Meta formulário etc.) é distinto de mídia de aquisição (`google_ads`, orgânico etc.). Mapear separadamente, sem substituir a taxonomia atual.
- Cidade/CEP do visitante não são cidade/CEP do imóvel. Não há enriquecimento geográfico demonstrado neste fluxo. Omitir o que não foi capturado; não inventar localização com base em país padrão.
- O arquivo pede segredo em todas as chamadas; o código o trata como opcional. Tornar estado de autenticação visível e exigir conforme contrato configurado, preservando destinos existentes até migração deliberada.
- A frase “somente depois de aceitar lead com telefone e e-mail válidos” conflita com leads telefone-only atuais. Separar aceitação comercial de elegibilidade para cada destino.
- Manter IDs antigos estáveis: mudar `_fechamento` para `_fechado` ou UUID para outro formato sem compatibilidade pode duplicar conversões.

## Sequência recomendada

1. Conferir somente leitura em cada ambiente: release/migrations, destino Google habilitado, gatilhos, fila/outbox e motivos dos eventos do teste relatado. Nenhuma ativação automática.
2. Fechar contrato comum com compatibilidade; alinhar modalidade, canal, IDs e payload offline.
3. Evoluir contexto/dataLayer e eventos na camada compartilhada de todos os temas (`default`, `saluteimoveis`, `conexaoimobiliaria`, `salute_luxury` e futuros).
4. Evoluir teste por contrato e visibilidade operacional por conta; reaproveitar componentes ax-* e permissões de integrações.
5. Validar isolamento entre contas, captura sem e-mail, imóvel nas duas modalidades, consultas repetidas, Turbo/consentimento, gatilhos e retries. Ao implementar site público, executar contrato de todos os temas e build CSS quando aplicável.
6. Validar evento sintético ponta a ponta no container autorizado e somente então planejar publicação/ativação por conta. Não reprocessar histórico como parte da correção.

## Conferência de produção — 29/10/2026, 12h51 (Brasília)

Consultas Rails executadas em transação PostgreSQL `READ ONLY`. Não houve alteração de registros, ativação, envio de testes ou replay.

- Salute: release 852, revisão `24675fc1cb5d6ad9079da7faf7904c2451f53693`.
- Conexão: release 432, mesma revisão.
- Puma e Solid Queue ativos nos dois servidores; `/up` HTTP 200 em ambos.
- Migration `20261027160000` aplicada em ambos. `20261027190000`, de qualificação adicional, ausente: a melhoria local ainda não integra o código publicado.

### Salute

Webhook #2 GTM–STAPE aponta para `https://gtm.saluteimoveis.com.br/crm-lead`, está `enabled: true`, com criptografia disponível, porém `google_conversions_enabled: false`. Nenhum segredo configurado. Assinaturas gerais limitadas a `lead_created`, `lead_inquiry`, `form_submitted`. Webhook #1 N8N também está ativo e sem conversões Google habilitadas.

**Bloqueio confirmado:** o dispatcher publicado não encontra destino ativo com `google_conversions_enabled: true` e retorna antes de registrar a conversão. A outbox Google contém zero registros (incluindo falhas e descartes); portanto não há evento desse fluxo aguardando retry nem evidência de tentativa HTTP dele. Isso não audita a entrega dos webhooks gerais de captura.

Configuração dos funis 1 e 3: qualificação usa `qualified`, visitas usam `visit_completed`, propostas usam `proposal_sent`, fechamento usa `deal_closed`. A etapa “Visita Realizada” (#51, funil 1) está configurada para `qualify_lead` por qualificação, e não para evento de visita; requer revisão da intenção operacional. Movimentação de card por si só não corresponde aos gatilhos de qualificação, visita ou proposta. Meta possui configuração independente e não deve ser alterada como efeito colateral.

### Demais contas observadas

Conexão (tenant 72): nenhum webhook de saída cadastrado, todos os eventos Google das etapas em `none`, zero conversões na outbox. Não habilitar por replicação da Salute.

Conta Staging QA (tenant 2 no servidor Salute): nenhum webhook, eventos Google em `none`, zero conversões. Preservar desativada.

### Consequência para a implementação

A primeira correção do caso é tornar explícita a ligação e ativação por conta na UI. Ativar envio é uma ação operacional separada: antes, validar contrato real do payload e os gatilhos desejados, pois habilitar o destino inicia novas conversões reais em todas as etapas já mapeadas daquela conta. Não há justificativa para ativar outras contas ou reenviar histórico. As lacunas de serialização verificadas localmente também existem no recorder publicado.

## Rechecagem após ativação — 29/10/2026, 17h30–17h35

O webhook #2 agora tem `google_conversions_enabled: true`; atualização salva às 13h08min06s. Há segredo preenchido (valor não consultado/exposto). Revisão publicada permanece `24675fc1`. Outbox Google continua sem registros, inclusive descartados/falhos; não há evidência de tentativa HTTP por esse fluxo.

Evidência dos testes próximos ao relato das 13h09:

- Lead 17683: mudança de status para “Em Atendimento | Qualificado” às 13h08min40s no audit; etapa 24, gatilho `qualified`. Avaliações de corretor e gestor continuam nulas.
- Lead 17993: mesma mudança às 13h10min30s; etapa 24, avaliações nulas.
- Não houve mudança de avaliação de qualificação nos audits da conta após 13h08min06s até a consulta. Nenhuma visita/proposta atualizada encontrada nessa janela nos models usados pelos callbacks (propostas escopadas via lead).

Assim, nesses dois casos a ativação foi salva, mas a ação realizada foi entrada/movimentação de etapa, não qualificação efetiva exigida pelo gatilho. A ausência de envio é comprovada; falha de recebimento no GTM não é demonstrada porque não houve evento registrado para entrega.

Há também um caso posterior distinto: lead 41316 mudou o status de “Em Atendimento” para “Negócio fechado” às 16h15min30s; estado atual às 16h15min56s está na etapa ganha 26, mas sem evento na outbox. O audit não inclui mudança de `lead_pipeline_stage_id`, logo não permite reconstruir a ordem das duas mudanças. Código publicado de `close_deal` altera apenas status, enquanto o dispatcher depende do vínculo com a etapa ganha. Isso é compatível com a lacuna já corrigida localmente, mas a causa específica desse fechamento não foi comprovada. Não classificar todos os casos como simples configuração. Nenhum replay ou mudança de gatilho foi feito.

## Correção local de Kanban e arquivados — 29/10/2026

A tela sem filtro de funil reúne todas as etapas cadastradas, mas o editor abria
somente o funil padrão. Além disso, o catálogo injetava `LEGACY_STATUSES` sem
exigir registros. Removida essa injeção: status antigos com leads continuam
acessíveis, e o Kanban passa a buscar os status existentes no seu recorte filtrado.
O editor agora explica o contexto global e oferece links para cada funil da
conta, permitindo abrir a mesma configuração usada no recorte da tela.
Etapas invisíveis ao perfil não são recuperadas pelo fallback quando nenhuma
etapa está visível, nem por filtro explícito no funil selecionado/paginação.
Não houve exclusão, renomeação, migração ou transferência de leads/etapas.

`Leads::OperationalScope.without_archived` centraliza a exclusão padrão para as
abas, contadores, cards e paginação desktop/PWA: considera `archived_at`, etapa
de tipo `archived` (inclusive vínculo por nome no mesmo funil para registros sem
stage_id) e o marcador importado `attribution_data.archive_details.archived`
quando o status ainda é o descarte correspondente. Um descarte comercial sem
marcador não é convertido automaticamente em arquivamento. Filtros explícitos
de status, etapa ou motivo preservam a consulta ao histórico; escopos de conta e
responsável permanecem os existentes. Não usa dados de outra conta/funil para
classificar status homônimos.

A paginação Kanban agora usa `column_status` para separar a coluna do filtro
`status`, mantendo compatibilidade com chamadas antigas sem tratar o parâmetro
da coluna como autorização implícita para mostrar arquivados.

Validação focada: 18 exemplos sem falhas, incluindo N+1. Na suíte ampla foram
identificadas cinco expectativas preexistentes sobre o HTML inteiro: nomes de
leads continuam em notificações do cabeçalho mesmo quando não estão nos cards.
As mesmas cinco falham na contraprova sem as mudanças de escopo/colunas desta
tarefa; detalhes em `/tmp/unitymob-leads-baseline.log`. Notificações históricas
não foram removidas como parte da correção operacional. Nenhum deploy realizado.
