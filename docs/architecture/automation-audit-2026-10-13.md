# Auditoria de /admin/automacoes — 13/10/2026

Escopo: hub, regras legadas, builder versionado, eventos, despachantes, rotina periódica e calendário. Inspeção de código e navegador autenticado em desenvolvimento, conta Salute. Sem alterações de dados operacionais ou deploy.

## Mapa e responsabilidades

- `Admin::AutomationRulesController`: CRUD legado, simulação e hub.
- `Admin::AutomationWorkflowsController`: criação, edição de rascunho, publicação e receptivo.
- `AutomationEvent` / `EventBus`: envelope persistido e emissão.
- `Dispatcher` / `WorkflowDispatcher`: seleção das regras/fluxos e retomada de esperas.
- `ActionRunner` / `WorkflowRunner`: execução legada/grafo; contratos diferentes, não fundidos.
- `ConditionMatcher`: etapa, origem e inatividade; reutilizado pelo builder.
- `ScheduleCalculator`: calendário das automações; validação compartilhada pela definição e runtime.
- `StagePolicy`, `WorkflowActionAdapter`, `ResponseCondition`, `WebhookUrlPolicy`: componentes existentes preservados.

## Erros corrigidos nesta entrega local

| Prioridade | Problema e evidência | Correção |
| --- | --- | --- |
| Alta | Tick emite `automation_rule_id`/`workflow_id`, mas ambos os despachantes iniciavam todas as automações do mesmo gatilho (`TickJob#perform`, `WorkflowDispatcher.dispatch_idle_candidates`, `Dispatcher#process`). | Destino centralizado em `AutomationEvent#targets_automation?`, consumido pelos dois despachantes. Eventos comuns continuam observáveis por múltiplas automações. |
| Alta | Entrada `lead_idle` caía no ramo genérico de `WorkflowDispatcher#entry_matches_event?`, sem validar etapa/origem/horas. | Reutiliza `ConditionMatcher.match_conditions?`; exige horas positivas e mantém filtro de distribuição existente. |
| Alta | `dispatch_scheduled_routines` selecionava repetidamente os primeiros 200 leads. | Exclui no banco eventos já emitidos para fluxo/período, incluindo os pendentes; lotes posteriores avançam. Não é garantia de processar toda a base dentro da janela de 16 minutos. |
| Alta | `Dispatcher#process` engolia erros e `ProcessEventJob` marcava sucesso. | Exceção chega ao job, que registra `failed`. Retry continua exigindo atenção à idempotência de ações legadas. |
| Alta | JSON ausente/malformado/vazio podia virar definição padrão; publicação salvava nome/rascunho antes do vínculo receptivo. | Entrada inválida rejeitada; transações preservam estado quando salvar/publicar falha. |
| Alta | Janela comercial com início igual/posterior ao fim podia prender o worker sem consumir duração. | Validação em `ScheduleCalculator`, reutilizada por `WorkflowDefinition` e runtime; horários inválidos são erro explícito. |
| Média | Sábado antes da abertura podia retornar domingo mesmo excluindo fins de semana. | Calendário pula todos os dias excluídos; fechamento comercial é exclusivo. |
| Média | Leads já tocados por workflow parado eram materializados em array (`dispatch_idle_candidates`). | Subconsulta SQL mantém a semântica e evita carregar todos os IDs em memória. |

## Correção das seis lacunas operacionais

- **Concorrência:** emissão idempotente protegida pelo lock da conta; processamento protegido pelo lock do evento; execução legada protegida pelo lock do lead e checkpoints em `AutomationRun#result`; criação do builder serializada no workflow e execução no registro da execução. Cada continuação leva o ID da espera, causa (evento ou timeout) e nós já consumidos. Jobs duplicados não reiniciam entrada em espera. Reprocessar erro do builder retoma no nó que falhou. Compatibilidade mantida para continuações antigas sem ID da espera.
- **Base atual:** publicação concluída enfileira `BackfillWorkflowJob` via `after_update_commit`, também para consumidores além do controller. Snapshots de `lead_created`, `lead_idle` e `scheduled_routine` usam `LeadCandidates`; outros gatilhos usam o evento histórico real mais recente de cada lead anterior à publicação. Cliques de fluxo WhatsApp só usam eventos anteriormente vinculados ao próprio workflow; campanhas respeitam o ID da campanha. Versão fixada e chave idempotente; eventos de base atual não respondem esperas de outros fluxos. Republicar “base atual” cria avaliação para a nova versão; retomar a mesma versão não duplica essa avaliação. Sem histórico compatível, não há entrada fictícia.
- **Simulação:** seleção somente pelos filtros de entrada, incluindo distribuição. Grafo percorrido por lead da amostra usando o mesmo matcher `and/or` do runtime; blocos desconectados e ramos que falham não apresentam intervenções como alcançadas. Esperas/respostas futuras interrompem a previsão e recebem aviso explícito. Visual compartilhado em `admin/shared/automation_simulation`.
- **Frequência:** tick configurado a cada minuto. Intervalo inteiro mínimo de um minuto, horários HH:MM válidos, mês de 1 a 31 e dias semanais de 0 a 6. Rotinas percorrem toda a seleção em lotes, sem limitar sempre aos mesmos 200; calendário diário/semanal/mensal usa tolerância de dois minutos. Pausa do scheduler acima dessa janela não gera recuperação automática de todos os horários perdidos.
- **Paginação:** 12 workflows e 20 regras por página, parâmetros independentes e `ax_pagination`; métricas mostram total, não apenas a página.
- **Pausa:** ações PATCH tenant-scoped no hub. Mantém versão ativa e esperas; não aceita novas entradas normais enquanto pausado. Ao retomar, recupera jobs pendentes/continuações não consumidas e eventos direcionados pendentes. Prazos seguem datas originais: vencidos retomam imediatamente, futuros permanecem agendados. Ramos paralelos preservam esperas abertas por outro ramo. Eventos comuns ocorridos inteiramente durante a pausa não são reexecutados automaticamente.

## Limites e próximos trabalhos fora das seis lacunas

1. **Efeito externo confirmado antes de crash:** checkpoints e locks eliminam duplicações normais de entrega e reprocessamento parcial. Um provedor externo que aceite uma mensagem e perca a resposta antes do commit ainda pode deixar resultado incerto; garantia absoluta exige idempotência/reconciliação oferecida pelo provedor. Não presumir exatamente uma entrega externa.
2. **Carga:** intervalos de um minuto e inclusão da base atual podem criar muitos eventos. Dados são percorridos em lotes, mas o volume total continua proporcional ao recorte da automação; capacidade produtiva não foi medida nesta entrega.
3. **Regras legadas:** `AutomationRulesController#parse_actions` ainda transforma JSON inválido em lista vazia e remove ações proibidas. O exemplo legado inclui `Represado`, proibido por `StagePolicy`. Esses pontos não pertencem às seis lacunas solicitadas e registros existentes não foram alterados automaticamente.

## Decisão de centralização

Escolha: evoluir componentes existentes, sem novo motor nem camada genérica. O envelope decide destinatário, o matcher decide compatibilidade do lead e o calendário valida sua própria janela. Controllers mantêm orquestração e transações. Não unir calendário de WhatsApp (pode cruzar meia-noite) ao de automações (janela diurna), nem fundir runners com contratos diferentes. Benefício: mesma regra nos consumidores; risco: comportamento mais restritivo para janelas inválidas legadas, agora com erro em vez de worker preso.

## Validação

Testes cobrem isolamento por tenant, despacho direcionado, filtros de inatividade, avanço de lotes, propagação de erro, preservação de rascunho, rollback receptivo e calendário. Suíte de automações, model e requests, incluindo entregas simultâneas em conexões PostgreSQL separadas: 159 exemplos, zero falhas. Mais 6 testes JavaScript do builder passaram. Navegador autenticado validado em desktop e 390 × 844. `rails zeitwerk:check` e `git diff --check` passaram. Prévia acionada no navegador autenticado em desenvolvimento, sem executar intervenções. Nenhuma mensagem enviada, automação ativada ou conversão criada.
