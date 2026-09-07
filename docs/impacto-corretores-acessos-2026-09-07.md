# Uso dos corretores e impacto das correções — 07/09/2026

> **Regra final posterior:** tarefas e agenda abertas pertencem ao lead e acompanham seu responsável. A exceção intermediária para o responsável antigo foi substituída. Ver [implementação e backfill](lead-activity-ownership-2026-09-07.md). As análises abaixo registram as etapas anteriores.

## Conclusão

**As duas regressões identificadas foram corrigidas localmente após esta análise.** O corretor pode completar dados faltantes de um proprietário antes de vinculá-lo a uma captação editável. Tarefas e compromissos já atribuídos continuam operáveis após a transferência do lead, sem liberar seu painel ou novos vínculos fora da carteira.

A investigação em produção foi somente leitura, com `default_transaction_read_only` e transação `READ ONLY`. As correções posteriores estão no checkout; não houve deploy, alteração de dados de produção ou envio de mensagens.

### Ajustes posteriores à coleta

- O formulário envia o contexto da captação/imóvel. O servidor valida conta, permissão, responsável e revisão pendente antes de autorizar a complementação pré-vínculo; dados já preenchidos do proprietário não são sobrescritos nessa etapa.
- Criação e troca de lead de tarefas/agenda continuam exigindo acesso ao lead. Alterar, concluir ou excluir uma atividade já atribuída usa o escopo do responsável pela atividade.
- A resposta Turbo não renderiza o painel de lead fora da carteira; retorna à tela de origem.
- Os bloqueios administrativos e demais limites de segurança permanecem.

Validação após os ajustes de rotina: suíte ampliada com **142 exemplos, zero falhas**; cobertura final dos limites do corretor com **22 exemplos, zero falhas**, incluindo isolamento do contexto e do proprietário entre contas; `security:tenant_isolation` com **46 exemplos, zero falhas**. `zeitwerk:check` e `git diff --check` aprovados. Sem commit ou deploy.

As seções 1 e 2 abaixo preservam o diagnóstico anterior ao ajuste e dimensionam o impacto evitado.

## Escopo e evidência

- Conexão: tenant **72**, servidor `app.conexaobc.com`; Salute: tenant **1**, servidor `143.110.138.67`. A conta de QA da Salute não foi incluída.
- Ambos publicavam a revisão **0783eabdecffe76b7f4ea761040f8027afdd5a7a** na coleta. Os bloqueios desta tarefa ainda são alterações locais.
- Período dos eventos de banco: últimos 30 dias, de **08/08/2026 a 07/09/2026**, coleta iniciada aproximadamente às **16h36 de Brasília**.
- Foram selecionados usuários cujo perfil vertical atual tem `key=agent`: 11 na Conexão e 37 na Salute, sendo 11 e 27 ativos. Houve eventos de navegação de 10 e 26 usuários, respectivamente. A seleção usa o perfil atual, não uma reconstrução histórica de perfis.
- Eventos podem incluir impersonação e contas operacionais, como o usuário chamado “Corretor”; não representam necessariamente pessoas distintas nem produtividade. O campo `last_login_at` estava sem informação útil e não foi usado para concluir inatividade.
- Fontes: `operational_user_events`, auditorias de imóveis/leads, timeline, tarefas, agenda, propostas, mensagens e perfis. Eventos automáticos/importados não foram somados como trabalho humano. Registros de tarefas e compromissos demonstram atribuição, não necessariamente autoria do corretor.

## O que está sendo utilizado

| Evidência dos últimos 30 dias | Conexão | Salute | Efeito esperado das alterações |
|---|---:|---:|---|
| Eventos de busca no catálogo | 489 | 19.483 | Preservado |
| Eventos de abertura de imóveis | 111 | 5.215 | Preservado |
| Criações auditadas de captação por perfil corretor | 5 | 123 | Preservado; complementação pré-vínculo corrigida |
| Atualizações auditadas no fluxo de captação | 8 | 860 | Edição limitada e complementação preservadas |
| Publicações auditadas no fluxo de captação | 0 | 54 | Preservadas com os perfis atuais, que têm `publish=true` |
| Alterações auditadas de status de leads | 13 | 16 | Preservadas com os perfis atuais |
| Criações auditadas de leads | 5 | 0 | Preservadas |
| Mensagens de saída atribuídas a corretor no inbox | 18 | 1 | Permissão de atendimento preservada; inclui tentativas com falha |
| Tarefas recentes marcadas como manuais e atribuídas aos corretores | 13 | 8 | Sem incompatibilidade de carteira encontrada nesses registros |
| Compromissos atribuídos aos corretores | 25 | 158 | Nenhum incompatível com o escopo novo no estado atual |

As 209 tarefas recentes da Conexão incluem 196 importadas; as 78.351 da Salute incluem 78.343 importadas. Não interpretar esses totais como tarefas criadas manualmente pelos corretores. Da mesma forma, compromissos e vínculos de interesse podem ter origem em integração.

## 1. Regressão comprovada: completar proprietário antes de vincular

Fluxo existente:

1. Corretor entra na captação e pesquisa um proprietário já cadastrado.
2. Se falta telefone ou cidade, o componente abre o formulário para completar os dados.
3. O componente envia `quick_update` e **só depois do sucesso** aplica o proprietário ao formulário.
4. A captação ainda não possui o vínculo persistido exigido pela minha nova regra.
5. O endpoint devolve **404** e impede concluir essa seleção.

Reproduzido em teste local transacional: tela de captação **200**, proprietário encontrado na busca **200**, tentativa de completar cidade **404**, sem gravação. O teste comprova a regressão, não uma aprovação do comportamento.

O risco é relevante: existem **544 de 565** proprietários sem cidade na Conexão e **3.885 de 4.465** na Salute. Esses números dimensionam cadastros potencialmente sujeitos ao fluxo; não são contagem de pessoas já bloqueadas.

Os logs disponíveis registram **15 atualizações rápidas 200 na Conexão e 6 na Salute**. Demonstram uso do endpoint na conta, mas não identificam o usuário e não têm data confiável para aplicar o corte de 30 dias. Não atribuí essas chamadas individualmente a corretores.

**Ajuste implementado após a análise:** autorizar a complementação no contexto de uma captação que o corretor possa editar, inclusive durante a seleção ainda não salva, preservando limites de campos. Não liberar alteração genérica de qualquer proprietário nem exigir vínculo já persistido antes de permitir a etapa que o cria.

Referências: `app/javascript/controllers/habitation_owner_selector_controller.js:108`, `:180`, `:295`, `:333`; `app/controllers/admin/proprietors_controller.rb:279`; `app/views/admin/captacoes/steps/_proprietario.html.erb:24`.

## 2. Impacto comprovado sobre tarefas existentes

A tarefa pode continuar atribuída ao corretor enquanto o lead já pertence a outro. A consulta antiga usa o responsável da tarefa. A nova verificação também exige acesso à carteira do lead para alterar, concluir ou excluir.

| Situação | Conexão | Salute |
|---|---:|---:|
| Tarefas com responsável diferente do lead que seriam barradas | 18 | 60 |
| Dessas, ainda pendentes | 12 | 11 |
| Pendentes dentro do filtro operacional atual | **7** | **1** |
| Pendentes fora do filtro operacional atual, acessíveis no legado | 5 | 10 |

Todas as pendentes afetadas são `external_legacy`; os responsáveis dessas pendências estão ativos. Não encontrei eventos dos últimos 30 dias de criação/edição/conclusão atribuídos a essas tarefas específicas na timeline. Portanto, está comprovado que o novo código barraria registros atualmente atribuídos; não que os corretores tenham tentado operá-los recentemente.

Pendências operacionais identificadas:

| Conta | Responsável da tarefa | Quantidade | IDs das tarefas |
|---|---|---:|---|
| Conexão Imobiliária | Augusto Cesar Sampaio Lima | 2 | 10581, 10564 |
| Conexão Imobiliária | Fábio Luís Avallone | 2 | 10531, 10535 |
| Conexão Imobiliária | Karla Luiza Barcelos Guimarães | 3 | 10527, 10545, 10557 |
| Salute Imóveis | Luciane Kovalczyk | 1 | 172648 |

**Ajuste implementado após a análise:** criação/revinculação a lead fora da carteira continuam bloqueadas. A atividade já atribuída permanece editável, concluível (tarefas) e excluível no escopo do responsável, sem renderizar o painel do lead alheio. Nenhuma atribuição de corretor ou lead foi alterada.

Referências: `app/controllers/admin/tasks_controller.rb:5`, `:106`; `app/controllers/admin/base_controller.rb:327`.

## Demais mudanças, comparadas ao uso e às permissões reais

| Mudança | Avaliação |
|---|---|
| Remover Contratos B2B do menu do corretor | Alinha menu ao bloqueio administrativo existente. Logs da conta têm redirecionamentos e acessos administrativos; não comprovam uso autorizado pelo corretor. |
| Restringir configurações de atendimento WhatsApp ao dono da conta | Bloqueio administrativo intencional. Há consultas à tela nos logs; não identifiquei atualizações bem-sucedidas nesse conjunto. O atendimento permanece permitido. |
| Exigir integrações para sincronizar templates | Retira essa função dos corretores atuais; não encontrei chamadas de sincronização nos logs lidos. Não impede usar templates já sincronizados. Ausência no log não prova que nunca foi usado. |
| Interromper execução após negar permissão | Correção de segurança a manter. Os perfis reais já permitem comercial e atendimento; as ações normais continuam passando. |
| Exigir edição para etiquetas/interesses e gerenciamento para cartões pessoais | Todos os perfis corretor consultados têm as permissões necessárias. Nenhum bloqueio adicional devido à configuração atual. Defaults de etiquetas não foram tratados como criação manual comprovada. |
| Respeitar publicação de captações | Todos têm `publish=true`; a publicação auditada na Salute continua autorizada. Não foi removida a edição limitada dos próprios imóveis. |
| Escopo de propostas | Não existem propostas com corretor como autor nas duas contas. Isso não prova ausência de consulta a propostas criadas pela administração; logs não identificam o ator. Não há carteira de propostas de autoria dos corretores que a consulta tenha apontado como bloqueada. |
| Escopo de agenda | Os 25/158 compromissos atribuídos passam pela comparação atual de carteira. Mudanças futuras de responsável podem produzir a mesma situação das tarefas. |

## Atividade por usuário

Eventos agrupados pelo usuário registrado; não são métricas de produtividade. Navegação soma listagens, buscas, aberturas, seleções e compartilhamentos. Alterações são eventos auditados, não quantidade de imóveis/leads únicos. Usuários sem eventos nessas três fontes não aparecem na tabela.

| Conta | Usuário | Navegação | Auditoria de imóveis/captações | Auditoria de leads |
|---|---|---:|---:|---:|
| Conexão Imobiliária | Fábio Luís Avallone | 255 | 0 | 0 |
| Conexão Imobiliária | Karla Luiza Barcelos Guimarães | 176 | 1 | 4 |
| Conexão Imobiliária | Augusto Cesar Sampaio Lima | 144 | 0 | 7 |
| Conexão Imobiliária | Corretor | 95 | 11 | 1 |
| Conexão Imobiliária | Levi Ribeiro | 83 | 0 | 0 |
| Conexão Imobiliária | Lidia da Cruz Tonet | 50 | 0 | 1 |
| Conexão Imobiliária | Gabriela Machado | 47 | 0 | 2 |
| Conexão Imobiliária | Leticia Rossatto | 29 | 0 | 0 |
| Conexão Imobiliária | Tayana Agne | 22 | 2 | 4 |
| Conexão Imobiliária | Corretor 2 | 9 | 0 | 0 |
| Salute Imóveis | Vera Janete | 2719 | 77 | 2 |
| Salute Imóveis | Luciane Kovalczyk | 2280 | 32 | 0 |
| Salute Imóveis | Fabiane Telles | 2200 | 56 | 0 |
| Salute Imóveis | Francislaine Mota | 1954 | 51 | 0 |
| Salute Imóveis | Angye Karine | 1665 | 273 | 2 |
| Salute Imóveis | Tania Tonial | 1633 | 80 | 0 |
| Salute Imóveis | Manoela Sosa | 1622 | 20 | 0 |
| Salute Imóveis | Lucas Rheinheimer | 1615 | 38 | 0 |
| Salute Imóveis | Yara Loira | 1568 | 94 | 0 |
| Salute Imóveis | Adriana Stark | 1565 | 32 | 0 |
| Salute Imóveis | Ana Leitão | 1527 | 69 | 0 |
| Salute Imóveis | Simone Schmitt | 1520 | 49 | 0 |
| Salute Imóveis | Patricia Paula | 1495 | 142 | 0 |
| Salute Imóveis | Abner Marcelo | 1439 | 116 | 0 |
| Salute Imóveis | Fernando Mendes | 1361 | 12 | 0 |
| Salute Imóveis | Daniele Bresolin | 1142 | 25 | 0 |
| Salute Imóveis | Michele Paula | 1051 | 16 | 0 |
| Salute Imóveis | Nilton Cardoso | 939 | 2 | 0 |
| Salute Imóveis | Sophia Marzotto | 930 | 15 | 1 |
| Salute Imóveis | Eliane Rosa | 726 | 55 | 0 |
| Salute Imóveis | Luciana Wagner | 325 | 61 | 0 |
| Salute Imóveis | Patrick Denardi | 291 | 0 | 0 |
| Salute Imóveis | Edmar Luiz Cavaca Junior | 205 | 2 | 0 |
| Salute Imóveis | Luciana Indalécio | 106 | 0 | 0 |
| Salute Imóveis | Contato Salute (Imóveis Construtora) | 36 | 0 | 0 |
| Salute Imóveis | Eduardo Antunes | 25 | 25 | 11 |

## Limites e decisão recomendada

O teste anterior validou o bloqueio de proprietário sem vínculo, mas não cobriu o caminho da interface que precisa completar esse proprietário **antes** de vinculá-lo. A análise de uso revelou essa lacuna. Os testes aprovados também não substituíam o confronto com tarefas importadas já atribuídas em produção.

Os dois pontos foram ajustados no checkout e cobertos por testes de requisição, incluindo o contexto real do formulário e a resposta Turbo de atividades antigas. A publicação continua pendente; os dados e perfis de produção não foram modificados.
