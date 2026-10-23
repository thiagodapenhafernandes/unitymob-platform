# Não lidos no título da aba

O admin reutiliza InAppNotificationsChannel para avisar todas as abas. O total é sempre calculado no servidor por usuário e tenant: avisos não lidos do sino, novas mensagens Direct notificadas ao usuário com acesso ao lead e mensagens WhatsApp não lidas no escopo do inbox. Avisos operacionais de atendimento continuam avisos distintos das mensagens.

O título conserva o texto da conta/página e recebe `(N) ` quando o total é positivo. A conexão/reconexão e o foco consultam novamente o total; navegação Turbo inicializa o novo título. Não há incremento local nem polling periódico.

Direct cria notificações apenas para novas mensagens recebidas, para usuários ativos com acesso ao lead. Saídas e históricos existentes não geram pendências. O frame visível, em aba com foco, confirma leitura via POST autenticado usando o maior ID exibido; mensagens posteriores ao cursor continuam não lidas. A leitura em uma aba avisa as demais pelo mesmo canal. WhatsApp preserva as regras de leitura do atendente existentes.

Sem migrations, novas dependências, mudança em credenciais ou configuração da Meta. Publicação nos clientes Salute e Conexão BC; Gateway e Central fora do pacote.
