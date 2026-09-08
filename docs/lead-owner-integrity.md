# Responsabilidade de leads e atividades — 07/09/2026

## Diagnóstico confirmado em produção (somente leitura)

Conexão, tenant 72: lead Silvestre 210, criado em 18/07/2026. ID C2S ae00cba81f9d9c490f3b00ace6dfccf2. Consulta GET pela integração 1 confirmou seller Cacildo Perrone Junior, ID 99b8e16de7b6753494dad1891ed7a63a. O mapeamento local retornou nil; não há usuário com nome Cacildo nessa conta. Não criar ou associar corretor apenas por semelhança de nome.

A tarefa 107, external_legacy, ficou atribuída ao usuário 452. Eventos de 07/09 às 13:00 e 15:00 confirmam aceitação pelo provedor para inscrição iOS 126. O job usa responsável da tarefa, mesmo com lead sem responsável.

Inventário atual, sem alterações:

| Conta | Em atendimento sem corretor | Tarefas pendentes de leads sem corretor | Compromissos agendados de leads sem corretor |
|---|---:|---:|---:|
| Conexão 72 | 4 | 1635 | 0 |
| Salute 1 | 92 | 8878 | 3 |

Contagens de atividades incluem leads não operacionais; não são contagens de push elegível. Não cancelar em massa nem atribuir automaticamente.

## Fluxos e proteções

- Lead: validação compartilhada impede salvar Em Atendimento sem responsável, incluindo remoção de corretor mantendo essa etapa. Regularizar atribuindo corretor ou mudando a etapa.
- Task/Appointment: validação compartilhada impede criação/agendamento com lead sem corretor. Atividades pessoais sem lead e com responsável continuam permitidas. Atividades antigas podem ser concluídas/canceladas.
- Lembretes: os dois jobs bloqueiam envio para atividade cujo lead está sem corretor, mesmo que a atividade retenha responsável antigo.
- Importação C2S: lead em atendimento sem mapeamento fica na etapa inicial; informações do vendedor externo são preservadas. Não criar atividade usando fallback da origem quando o lead local está sem corretor.
- Reconciliação de ações C2S: ignora leads sem responsável local.
- Automações: deixam de escolher primeiro usuário ativo/fallback para tarefas de lead sem corretor. Disponibilização de lead remove corretor junto com retorno à etapa inicial.
- Admin e extensão usam os models; erros de validação são tratados pelos endpoints existentes. A extensão retorna invalid_fields e o admin apresenta erros do registro.

## Limites e próximos passos

Código local, ainda não publicado. Nenhum dado de produção foi corrigido. Validar mapeamentos e decidir destino dos leads sem corretor antes de backfill. Não alterar as notificações de oferta de leads no Bolsão: elas têm destinatários explícitos e fazem parte da atribuição inicial.

Validações: 63 exemplos de models, jobs, importação, reconciliação e automações passaram. Operações diretas SQL/update_all não executam validações Rails; o bloqueio no job cobre registros antigos ou criados fora dessas validações. Não adicionada constraint global porque os status são configuráveis por tenant.
