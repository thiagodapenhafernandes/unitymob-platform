# Não lidos no título da aba

O admin reutiliza InAppNotificationsChannel para avisar todas as abas. O total é sempre calculado no servidor por usuário e tenant: notificações pessoais não lidas do sino, incluindo novas mensagens Direct e WhatsApp destinadas ao responsável. Avisos operacionais de atendimento continuam avisos distintos das mensagens.

O título conserva o texto da conta/página e recebe `(N) ` quando o total é positivo. A conexão/reconexão e o foco consultam novamente o total; navegação Turbo inicializa o novo título. Não há incremento local nem polling periódico.

Direct cria notificações apenas para novas mensagens recebidas, para o responsável ativo com acesso ao lead; sem responsável atribuído, usa o proprietário da conexão Meta da página. Saídas e históricos existentes não geram pendências. O frame visível, em aba com foco, confirma leitura via POST autenticado usando o maior ID exibido; mensagens posteriores ao cursor continuam não lidas. A leitura em uma aba avisa as demais pelo mesmo canal. WhatsApp notifica o destinatário do atendimento existente e preserva as regras de leitura do atendente. Acesso de gestor a outras conversas não soma pendências de terceiros. Sino e título usam a mesma consulta pessoal, e o sino oferece paginação para os itens antigos.

Sem migrations, novas dependências, mudança em credenciais ou configuração da Meta. Publicação nos clientes Salute e Conexão BC; Gateway e Central fora do pacote.

O sino apresenta ícone de origem (Instagram/WhatsApp/Sistema), remetente, prévia escapada de até160 caracteres, horário e indicador de não lida. Mensagens novas guardam o snapshot; registros anteriores recuperam o conteúdo em lote pela mensagem referenciada, validando a conta e o vínculo do lead/conversa, sem backfill. A mesma partial renderiza o carregamento inicial e as atualizações/paginação.

## Contexto de cada aviso

O rótulo de evento é independente da origem, do estágio do funil e da leitura. Exemplo: `Instagram Direct · Nova resposta`, remetente, prévia e horário. Ler o aviso não modifica o contexto nem o estágio do lead.

| Contexto | Gatilho existente utilizado |
| --- | --- |
| Novo lead | Atribuição direta inicial ou distribuição ao responsável |
| Lead atribuído | Reatribuição manual |
| Lead redistribuído | Distribuição após expiração do prazo anterior |
| Lead retornou | Distribuição sticky para o responsável anterior |
| Novo interesse | Nova consulta agregada ao lead existente |
| Prazo de atendimento expirado | Perda de vez; aviso genérico ao antigo dono, sem nome ou link do lead |
| Aguardando contingência | Encaminhamento pendente para a gestão já destinatária, somente com acesso ao lead |
| Nova mensagem | Entrada Direct/WhatsApp sem contexto de resposta |
| Nova resposta | Primeira entrada após saída na conversa; WhatsApp exige saída enviada/entregue/lida ou citação explícita de saída |
| Novo atendimento | Abertura pelo fluxo WhatsApp |
| Atendimento transferido | Transferência manual ou automática existente |
| Troca de assunto solicitada | Solicitação do cliente no fluxo WhatsApp |
| Atendimento encerrado | Finalização, troca de assunto ou janela expirada; motivo permanece no texto |
| Nova tarefa | Tarefa criada pelo fluxo WhatsApp |
| Carteira recebida | Reatribuição agregada existente de carteira |
| Aviso | Outros tipos, sem adivinhar significado pelo texto |

Eventos de lead reaproveitam os gates e destinatários do dispatcher, mas não dependem de assinatura Web Push. As notificações com referência a lead são filtradas novamente na leitura pelo acesso atual. Pool/shark tank preserva o fluxo atual de aceite e mascaramento, sem gerar preview de contato antes da atribuição. Não se criam avisos de proposta/venda/visita sem um emissor já integrado ao sino.

Os eventos novos guardam a classificação em metadata; os legados não são reprocessados. Mensagens antigas sem classificação continuam “Nova mensagem”, e atendimentos antigos preservam o título descritivo. A classificação de resposta é contexto de conversa, não prova de resposta a uma pergunta específica. Nenhum refresh, novo contador, alteração de rascunho ou mudança no fluxo Meta é necessário.
