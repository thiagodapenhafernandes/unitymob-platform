# Conexão — classificação de entrada e datas de reentrada

Correções locais, sem deploy, redistribuição ou união de cadastros históricos.

## Entrada Meta

- Resposta afirmativa a uma pergunta explícita de interesse em imóveis/terrenos à venda passa a identificar venda. Respostas negativas, indefinidas, perguntas negadas e consentimento genérico de contato não autorizam inferir modalidade. Dados estruturados explícitos e natureza administrativa preservam sua prioridade; campanhas não são usadas como modalidade.
- A referência no prefixo de um formulário, como `Form - 3909 Atlântico Shopping Residence`, pode identificar o imóvel da própria conta. Código explícito não encontrado ou referências conflitantes/múltiplas não autorizam escolher outro imóvel pelo nome.
- A seleção de regra continua usando origem, formulário, exclusões, recebimento, filtros e participantes existentes. O caso Refuge permanece no destino exclusivo já configurado, sem trocar a regra para Todos.

## Datas

- `Leads::EntryPeriodQuery` compartilha o filtro por cadastro original ou evento `inquiry_complemented`, com o escopo autorizado recebido. Eventos de outra conta não participam.
- Tabela, kanban e PWA mostram a entrada e, havendo reentrada, o cadastro original. Com período selecionado, mostram a última consulta dentro daquele período; uma consulta posterior não substitui a data exibida na pesquisa antiga.
- Tabela/kanban ordenam pela mesma data. A consulta das datas é feita em lote, sem buscar o histórico por card. CSV usa a entrada do período, mantendo seu contrato de colunas. XLSX e relatório comercial incluem as reentradas, preservando a regra existente de aceite do bolsão.
- Alteração cadastral, envio de notificação ou redistribuição interna não viram nova consulta. `created_at`, responsáveis, aceites, imóveis originais e históricos não são reescritos. Estatísticas de aquisição original mantêm sua semântica.

## Casos históricos

A auditoria somente leitura da conta Conexão (72) confirmou falha `ambiguous_business_type` nos leads 6850, 6851 e 6852. A simulação com venda encontrou respectivamente as regras 23, 23 e 22, com participantes elegíveis. Nenhuma atribuição foi executada.

O cadastro 1097 preserva criação em 21/02/2026 e consulta Guanabara em 12/10/2026. Há outro recebimento correspondente do RD às 10h23; ambos os eventos permanecem na trilha, sem deduplicação retroativa entre provedores. Os quatro cadastros com o mesmo telefone não foram unidos. A conciliação histórica e a recuperação dos leads sem responsável exigem uma execução separada e auditada.

## Validação

- 64 exemplos focados em classificação, job Meta, regras exclusivas, consultas de período, renderização, paginação, mobile e limites de consultas/desempenho: zero falhas.
- Bateria ampliada: 154 exemplos, cinco falhas. As mesmas cinco falhas foram reproduzidas na revisão publicada `6b28eb90`, nos exemplos `spec/requests/admin/leads_spec.rb:269,321,1070,1110,1145`. Não foram alteradas suas expectativas nem os comportamentos anteriores de filtros/painéis ocultos.
- Zeitwerk e `git diff --check`: aprovados. Não houve alteração de CSS/JavaScript, portanto seus builds não foram necessários. Não houve teste autenticado do pacote novo em produção nem envio de mensagens.
