# Não lidos no título da aba

O admin reutiliza InAppNotificationsChannel para avisar todas as abas. O total é sempre calculado no servidor por usuário e tenant: notificações pessoais não lidas do sino, incluindo novas mensagens Direct e WhatsApp destinadas ao responsável. Avisos operacionais de atendimento continuam avisos distintos das mensagens.

O título conserva o texto da conta/página e recebe `(N) ` quando o total é positivo. A conexão/reconexão e o foco consultam novamente o total; navegação Turbo inicializa o novo título. Não há incremento local nem polling periódico.

Direct cria notificações apenas para novas mensagens recebidas, para o responsável ativo com acesso ao lead; sem responsável atribuído, usa o proprietário da conexão Meta da página. Saídas e históricos existentes não geram pendências. O frame visível, em aba com foco, confirma leitura via POST autenticado usando o maior ID exibido; mensagens posteriores ao cursor continuam não lidas. A leitura em uma aba avisa as demais pelo mesmo canal. WhatsApp notifica o destinatário do atendimento existente e preserva as regras de leitura do atendente. Acesso de gestor a outras conversas não soma pendências de terceiros. Sino e título usam a mesma consulta pessoal, e o sino oferece paginação para os itens antigos.

Sem migrations, novas dependências, mudança em credenciais ou configuração da Meta. Publicação nos clientes Salute e Conexão BC; Gateway e Central fora do pacote.

O sino apresenta ícone de origem (Instagram/WhatsApp/Sistema), remetente, prévia escapada de até160 caracteres, horário e indicador de não lida. Mensagens novas guardam o snapshot; registros anteriores recuperam o conteúdo em lote pela mensagem referenciada, validando a conta e o vínculo do lead/conversa, sem backfill. A mesma partial renderiza o carregamento inicial e as atualizações/paginação.
