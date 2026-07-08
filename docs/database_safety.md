# Segurança de Banco — regras do projeto

Regras nascidas de incidentes reais. Toda mudança que toque banco deve respeitá-las.

## 1. Nenhuma query roda para sempre
- `statement_timeout` global de **30s** via `config/database.yml` (`PG_STATEMENT_TIMEOUT`).
- Migração pesada (índice em tabela grande etc.): rode com `PG_STATEMENT_TIMEOUT=0 rails db:migrate` — o timeout volta sozinho no processo seguinte.
- Se uma tela legítima estourar 30s, o problema é a query (índice/N+1), não o timeout.

## 2. CTE recursiva: sempre com dois freios
- **`UNION`, nunca `UNION ALL`** — deduplica o conjunto e TERMINA mesmo com ciclo
  ou grafo em diamante. (Incidente: `descendant_ids` com dois vínculos de gestor
  + `UNION ALL` re-expandia caminhos sem fim e derrubou o pool inteiro.)
- **Coluna `depth` com limite explícito** (`WHERE depth < N`) como segunda linha.
- Vale para PL/pgSQL também (ver `enforce_admin_user_profile_governance`).

## 3. Grafos de vínculo exigem anti-ciclo em TODAS as arestas
- O trigger de governança valida ciclo de `manager_id`; qualquer vínculo novo de
  hierarquia (ex.: `rentals_manager_id`) precisa do próprio anti-ciclo
  (validação no model + o freio das CTEs acima).

## 4. FK nova para admin_users = classificar no HardDeleter
- `AdminUsers::HardDeleter` verifica cobertura por introspecção e levanta erro
  para FK não classificada — é proposital. Classifique em REASSIGN / NULLIFY /
  DESTROY / MODEL_HANDLED com o racional em comentário.

## 5. Regra em três camadas anda junta
- Toda regra de integridade relevante existe em: form (UX) → model/controller
  (aplicação) → trigger/constraint (banco). Ao mudar a regra numa camada,
  atualize as outras (incidente: âncoras encadeadas de perfis passaram no app e
  quebraram no trigger).
