# Atribuição de novas consultas C2S

A integração Migração de Leads tem escolhas independentes para Venda e Locação:

- **Corretor informado pelo C2S** (`c2s`, padrão): entrega ao usuário local vinculado, ativo, do mesmo tenant, com perfil vertical de atendimento e atuação compatível com a modalidade. Proprietário da conta e superadministrador não recebem por esse caminho. Sem corretor elegível, usa a fila local.
- **Fila de distribuição da Unitymob** (`unitymob`): ignora o vendedor externo para atribuição e aplica as regras locais ativas de origem, modalidade, filtros, fidelização, represamento e disponibilidade. A origem C2S continua sendo o webhook de migração, identificado pela tag `external_lead_migration`; não ativa regras desativadas.

A modalidade usa a negociação do produto e, na ausência dela, o tipo do funil. Para consultas mistas ou sem modalidade, a escolha C2S só é aplicada quando ambas as configurações são `c2s`; em caso de divergência, usa a fila. Sem destino disponível, o fluxo registra a falha e mantém a consulta para triagem, sem afirmar entrega.

Uma nova consulta de contato existente passa pela conciliação e pelas regras de fidelização/pocket. Reentregas do mesmo evento não giram a fila. Sincronizações posteriores não alteram o responsável/regra local; consultas que passaram pela decisão operacional também preservam status/funil local. O vendedor e o conteúdo externo continuam disponíveis nos metadados da integração. Redistribuições locais continuam sob as regras existentes; o reconciliador histórico de responsáveis não assume leads cuja atribuição operacional já foi decidida.

Importações históricas continuam espelhando o legado sem iniciar distribuição. A migração adiciona dois campos com padrão `c2s`, sem redistribuir ou modificar leads existentes. A alteração não recupera eventos ausentes nem reatribui a Daniela. Não executar sincronização, backfill ou replay como parte da ativação desta configuração.
