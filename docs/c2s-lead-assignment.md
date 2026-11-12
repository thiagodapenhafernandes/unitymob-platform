# Atribuição de novas consultas C2S

A integração Migração de Leads tem escolhas independentes para Venda e Locação:

## Recebimento de novos cadastros por modalidade

`incoming_business_type`, em `operational_mappings`, escolhe `all` (padrão,
inclusive para contas existentes), `sale` ou `rental`. O filtro vale para IDs
C2S ainda não cadastrados, em webhook, incremental e importação histórica.
Registros já importados continuam sincronizando, mesmo fora da modalidade
selecionada; não são excluídos, transferidos nem deixam de receber agenda.
Ampliar o filtro não importa retroativamente IDs que não foram recebidos.

Para o filtro, a negociação explícita do C2S tem prioridade sobre o anúncio:
Compra/Venda corresponde a `sale`, Aluguel/Locação a `rental`. Categorias como
Captação, Lançamento, Indefinido ou mistas ficam fora de um filtro específico;
`all` mantém seu recebimento. O funil padrão não é usado para inventar a
modalidade de um novo cadastro filtrado. O histórico conta registros filtrados
separadamente, sem tratá-los como importações ou falhas.

O filtro não muda quem atribui o lead. Para receber somente novas vendas do C2S
com o mesmo corretor de lá, usar `sale` e manter o espelhamento contínuo ativo.
Entradas diretas da Unitymob continuam seguindo suas configurações locais;
esse modo não exige desligar o espelhamento para usar regras nativas no futuro.
Ativar regras locais é uma decisão separada: durante a conferência da Salute,
elas e seus prazos permanecem desligados. Os campos de atribuição sem
espelhamento só se aplicam quando o espelhamento estiver desativado.

Eventos parciais no espelho são completados com GET do ID no C2S antes de
atualizar responsável, modalidade, etapa, favorito ou agenda. Falha nessa
consulta preserva a carteira atual e segue a retentativa do job, em vez de
aplicar campos ausentes como se estivessem vazios. Eventos completos evitam
essa consulta adicional.

## Atribuição e espelhamento

- **Espelhamento contínuo do C2S** (`mirror_c2s_owners`, opção independente antes da virada): o responsável e a etapa informados pelo C2S também prevalecem sobre atribuições locais nas sincronizações seguintes. Reutiliza usuários ativos ou inativos da mesma conta; quando não houver vínculo, cria referência inativa com e-mail técnico não entregável e senha aleatória, sem habilitar login, enviar convites ou reativar usuários antigos. Sem ID de vendedor, mantém sem responsável, sem contingência de fila. Cada ID externo possui cadastro próprio, inclusive quando o contato já existe ou houve unificação anterior. Não envia notificação de atribuição nem gira roleta. Eventos com `updated_at` anterior ao último espelhamento não desfazem o responsável. A opção prevalece sobre os modos por modalidade e cobre também consultas sem modalidade definida. Antes de ativar, desligar regras e prazos de redistribuição da conta e conferir os vínculos de usuários; a seleção não corrige a base existente. A validação da conexão mantém a regra de apoio desativada e sem prazo de redistribuição neste modo. A operação inicial de conciliação deve ser auditada separadamente. Desmarcar a opção encerra o espelhamento sem alterar automaticamente os responsáveis.

Nesse modo, reentradas, links de corretor, distribuição explícita e automações de atribuição não substituem o responsável dos leads vinculados. Automações de etapa também ignoram esses leads, sem consumir o limite de processamento dos demais. A sincronização de conteúdo e agenda é serializada por lead para evitar tarefas duplicadas quando webhook e incremental chegam juntos. Antes da virada, revisar as automações que voltarão a atuar ao desmarcar o espelhamento.

No espelhamento, a etapa usa o contrato real `funnel_status.status`, com prioridade para arquivamento/negócio fechado. O mapeamento configurado da conta prevalece; na ausência dele, reutiliza as etapas equivalentes do funil da conta (atendimento, visita, proposta e encerramento), sem criar etapas ou disparar automações/conversões. As sincronizações preservam contatos, conversas e agenda. Ao voltar a operar localmente, o modo desligado conserva as decisões locais.

Nas abas operacionais do espelhamento, `A fazer`, `Visitas`, `Futuras` e `Favoritos` excluem leads encerrados; a estrela e a agenda histórica permanecem salvas. A classificação segue a **atividade atual** (`last_activity_date`) do C2S: `A fazer` inclui acompanhamento vencido/para hoje, mesmo sem ação ainda aberta, e mensagens de cliente não lidas; `Futuras` inclui a atividade aberta para dias futuros, inclusive visitas; `Visitas` considera apenas visitas abertas da atividade atual. Ações antigas na fonte não substituem a atividade atual. Visitas `Não realizada` são importadas como canceladas, mantendo a descrição original nos metadados. `c2s_current_activity_at_epoch` é a data atual da fonte normalizada na importação; o campo pode ser limpo sem mudar o histórico.

Compromissos criados somente localmente e atividades substituídas continuam na agenda/histórico, sem incluir o lead indevidamente nas abas do espelho. Lista, PWA e contadores compartilham os mesmos escopos. Contas sem espelhamento preservam o comportamento local.


Lista, kanban, filtros de período e paginação desktop/PWA usam o recebimento do ID no C2S (`c2s_source_created_at_epoch`, validado na importação), com fallback para o cadastro original. Reentradas locais continuam preservadas na timeline, mas não promovem um cadastro antigo enquanto ele é espelhado. Contas/leads fora desse modo mantêm suas regras de datas e ordenação anteriores. O card PWA exibe a etapa espelhada sem substituir o rótulo por ausência de interação local; isso não registra contato humano nem muda os indicadores de atendimento.

O relógio de obsolescência só é comparável dentro do mesmo ID do C2S. Um payload legado de outro ID, deixado por conciliação antiga por contato, não pode bloquear a restauração da identidade correta por uma atualização mais antiga. Corrigir esses casos com GET do ID próprio, backup e auditoria; nunca unificar IDs externos distintos por telefone/e-mail.

O cliente normaliza `updated_gte` para o relógio exigido pelo C2S: a API exige `Z` literal, mas compara o filtro no horário de Brasília. Chamadores continuam enviando ISO 8601 com o instante real; não devem antecipar essa conversão.

- **Corretor informado pelo C2S** (`c2s`, padrão): entrega ao usuário local vinculado, ativo, do mesmo tenant, com perfil vertical de atendimento e atuação compatível com a modalidade. Proprietário da conta e superadministrador não recebem por esse caminho. Sem corretor elegível, usa a fila local.
- **Fila de distribuição da Unitymob** (`unitymob`): ignora o vendedor externo para atribuição e aplica as regras locais ativas de origem, modalidade, filtros, fidelização, represamento e disponibilidade. A origem C2S continua sendo o webhook de migração, identificado pela tag `external_lead_migration`; não ativa regras desativadas.

A modalidade usa a negociação do produto e, na ausência dela, o tipo do funil. Para consultas mistas ou sem modalidade, a escolha C2S só é aplicada quando ambas as configurações são `c2s`; em caso de divergência, usa a fila. Sem destino disponível, o fluxo registra a falha e mantém a consulta para triagem, sem afirmar entrega.

Uma nova consulta de contato existente passa pela conciliação e pelas regras de fidelização/pocket. Reentregas do mesmo evento não giram a fila. Sincronizações posteriores não alteram o responsável/regra local; consultas que passaram pela decisão operacional também preservam status/funil local. O vendedor e o conteúdo externo continuam disponíveis nos metadados da integração. Redistribuições locais continuam sob as regras existentes; o reconciliador histórico de responsáveis não assume leads cuja atribuição operacional já foi decidida.

Importações históricas continuam espelhando o legado sem iniciar distribuição. A migração adiciona dois campos com padrão `c2s`, sem redistribuir ou modificar leads existentes. A alteração não recupera eventos ausentes nem reatribui a Daniela. Não executar sincronização, backfill ou replay como parte da ativação desta configuração.
