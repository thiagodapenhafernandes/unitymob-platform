# Tarefas e agenda pertencem ao lead — 07/09/2026

## Regra implementada localmente

Tarefas `pendente` e compromissos `agendado` acompanham o responsável atual do lead, inclusive quando atrasados. A transferência inclui todas as pendências ligadas ao lead, independentemente de quem estava atribuído à atividade. Atividades sem lead continuam pessoais. Atividades encerradas preservam o responsável histórico, assim como a autoria das tarefas.

- A alteração do responsável sincroniza pendências na mesma transação e registra IDs e responsáveis anteriores/novo na timeline (`activity_ownership_transferred`).
- O aceite atômico, o aceite por link seguro e a transferência por inativação de usuário usam a mesma sincronização. O aceite continua protegido contra corrida e limitado à conta/regra autorizada.
- A criação, edição, revinculação e reabertura de atividades usam o responsável do lead. O salvamento trava o lead para evitar gravar um responsável desatualizado durante uma transferência concorrente.
- O antigo responsável perde acesso operacional às pendências transferidas; o novo passa a operá-las. O acesso de gestão continua seguindo as permissões existentes.
- Lembretes usam o responsável sincronizado e sua própria trilha de entrega: uma entrega ao usuário anterior não suprime o lembrete do novo. Atividades encerradas, divergentes ou de leads sem responsável não enviam lembretes.
- Remover o responsável do lead não apaga nem encerra pendências. Elas voltam a acompanhar o lead quando ele recebe um responsável.

Esta regra substitui a solução intermediária que mantinha tarefas antigas operáveis pelo usuário anteriormente atribuído.

## Backfill necessário: consulta em produção, somente leitura

Coleta em 07/09/2026, 16h57–16h58 de Brasília, transação `READ ONLY` e `default_transaction_read_only=on`. Conexão: tenant 72 em `app.conexaobc.com`. Salute: tenant 1 em `143.110.138.67`. Nenhum dado alterado.

| Conta | Tarefas divergentes | Leads dessas tarefas | Compromissos divergentes | Tarefas de leads sem responsável | Compromissos de leads sem responsável |
|---|---:|---:|---:|---:|---:|
| Conexão | 29 | 27 | 0 | 1.635 | 0 |
| Salute | 17 | 16 | 0 | 8.878 | 3 |

**Backfill indicado para 46 tarefas.** Todas estão atrasadas e têm destinatário atual ativo. A consulta abrange todos os perfis e todas as pendências das contas, não somente usuários atualmente classificados como corretor nem somente o filtro operacional; por isso difere do levantamento anterior.

As 10.513 tarefas e 3 agendas ligadas a leads sem responsável não têm destinatário para reconciliação. Preservar esses registros; não escolher usuário, cancelar ou excluir automaticamente. A próxima atribuição do lead passará a sincronizá-los com o código novo. Não foram encontrados vínculos de atividades cruzando contas nem destinatários inválidos nas pendências analisadas.

## Execução preparada, não realizada

Depois de publicar o código e revisar a simulação, executar separadamente em cada servidor. Comandos de simulação no diretório `deploy/current`:

```sh
TENANT_ID=72 RAILS_ENV=production rvm 3.2.3 do bundle exec rake lead_activities:reconcile_owners
TENANT_ID=1 RAILS_ENV=production rvm 3.2.3 do bundle exec rake lead_activities:reconcile_owners
```

A gravação exige `EXECUTE=1` e `BACKUP_PATH` apontando para um arquivo novo em diretório existente fora da release. O arquivo tem permissão 0600 e guarda IDs, responsáveis e timestamps anteriores; cada entrada é sincronizada em disco antes da alteração. A rotina revalida o responsável sob bloqueio do lead, preserva atividades encerradas, audita as transferências e é idempotente. Uma falha pode deixar leads anteriores já reconciliados; preservar o backup e repetir com outro arquivo após diagnosticar. Repetir a simulação após executar para verificar divergências restantes.

Não houve commit, deploy ou execução do backfill nesta tarefa.

## Validação local

RVM 3.2.3: **107 exemplos, zero falhas**, cobrindo transferência, aceite e corrida perdida, isolamento de conta/regra, inativação, rollback, criação/reabertura, importação de histórico encerrado, acesso pelos usuários anterior/novo, lembretes e backfill (simulação, backup e idempotência). O gate `security:tenant_isolation` passou com **46 exemplos, zero falhas**; `zeitwerk:check` e `git diff --check` aprovados.

Fixtures antigas foram adequadas à exigência de responsável em atendimento já presente no checkout. Os casos de legado sem responsável/divergente continuam simulando explicitamente o estado antigo, sem enfraquecer a validação atual.
