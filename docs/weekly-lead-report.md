# Relatório comercial por corretor

CSV e Excel mantêm o recorte de acesso da conta e do usuário, os filtros e o agrupamento pelo responsável atual. O período seleciona entradas/novas consultas e capturas de bolsão, como antes; as novas colunas não mudam a população da listagem.

## Datas

- **Data de entrada original:** `leads.created_at`, sem substituir pela data de nova consulta ou captura do bolsão. Pode anteceder o período do relatório.
- **Recebido pelo corretor atual em:** atribuição mais recente documentada para esse responsável, na distribuição, captura de bolsão ou auditoria de criação/transferência. Aceite comum não substitui a data de atribuição.
- **Primeiro atendimento do corretor atual:** primeira tentativa de contato humano registrada depois da atribuição conhecida. Considera contato operacional na timeline, mensagem humana enviada no Instagram/WhatsApp e visita realizada. Não considera aceite isolado, anotação interna, mensagem automática ou WhatsApp pendente. Não usa `updated_at` como aproximação.

Quando o histórico não comprova uma data, a célula permanece vazia. Não há backfill nem alteração de status ou de datas de leads.

## Visitas e aquisição

**Visitas realizadas no período** conta compromissos com tipo `visita`, status `realizado` e data `starts_at` dentro do período selecionado, vinculados ao lead e ao responsável atual. Não conta reunião, agendamento pendente, cancelamento ou visita anterior à atribuição conhecida. A data usada é a data do compromisso: não existe um campo separado de realização efetiva no cadastro atual.

CSV passa a incluir a indicação de histórico de atendimento pelo Bolsão, já existente no Excel. Origem e canal também têm colunas próprias nos dois formatos; a informação combinada anterior é preservada. A captura do Bolsão não sobrescreve a aquisição original.

`Leads::CommercialReportFactsQuery` carrega os fatos em lote, com escopo explícito por tenant e pelos leads já autorizados. Exportações de captações preservam suas informações e deixam vazias as colunas exclusivas do atendimento de leads. O Excel dimensiona as colunas e a área de título conforme o cabeçalho ampliado.
