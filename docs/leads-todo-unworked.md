# Aba A Fazer — critério de atendimento ainda não iniciado

Mudança restrita a A Fazer: status inicial/prioritário ou Em Atendimento, aberto, sem contato humano (aceite e abertura de link não contam), sem tarefas, agendamentos ou propostas. Registros de agenda importada também impedem classificação como intocado. Tarefas sem data/concluídas indicam que já houve ação. Sem corte arbitrário de dias. Demais abas preservadas.

Arquivos: app/controllers/admin/leads_controller.rb, app/views/admin/leads/index.html.erb, spec/requests/admin/leads_spec.rb.
Patch exclusivo: /tmp/leads-todo-only.patch. O checkout whatsapp-extension contém WIP anterior de exclusão/filtros nos mesmos arquivos; não incluir esse WIP no deploy desta demanda. Usar patch exclusivo/hunks para publicação.

Validação: 101 exemplos, 99 passaram. Duas falhas reproduzidas no checkout publicado sem a mudança: remoção de etapas referenciadas por transições (foreign key), e expectativa antiga de ausência do texto Contato na ficha. Novos testes cobrem aceite sem ação, contato, tarefa sem data/concluída, reunião, proposta, encerrados, lista desktop/PWA, paginação e preservação das outras abas. Zeitwerk e diff check passaram. Ainda não publicado; nenhum registro de produção alterado.
