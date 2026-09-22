# WhatsApp: atendimento, fluxos de resposta e automação

Roteiro de publicação e de operação dos módulos de atendimento por botão. Complementa [Deploys](deploys.md).

## Quem faz o quê

| Módulo | Para quê | Perfil de uso |
|---|---|---|
| **Fluxos de Resposta** | Mapeia cada botão do template a uma ação simples: registrar, responder, enviar link, criar tarefa, enviar para fila/usuário ou **iniciar uma automação**. | Simples: qualquer admin configura pela interface. |
| **Automação** (construtor) | Conversa em várias etapas: perguntas com botões/lista/texto, caminhos por resposta, "não entendi" com repetição, passagem para atendente. | Avançado: quem monta jornadas. |
| **Atendimento** (inbox) e **Gestão de atendimentos** | O atendente conversa; o gestor acompanha, transfere e finaliza. | Operação. |

Regra de projeto: opção nova de configuração avançada entra na **Automação**; o Fluxo de Resposta continua enxuto.

## Ordem para colocar uma conta no ar

1. **Integração** (Integrações > WhatsApp): conecte a conta. O token precisa enxergar a WABA de cada número.
2. **Número** (Números de disparo > Adicionar). Ao salvar, o sistema valida o número, **inscreve o app na WABA** (sem isso a Meta não envia webhooks) e registra a rota no gateway. Confira o aviso; use **Testar** e **Reconectar** se algo falhar.
3. **Template** do menu: aprovado, com uso "Fluxos de resposta" ou "Atendimento", na **mesma WABA** do número receptivo. Editar um template aprovado o reenvia à Meta (1 edição por 24h; nome e idioma não mudam).
4. **Fila**: crie a regra de distribuição com os atendentes (ativos, perfil vertical, sem ser dono da conta; com check-in se a regra exigir).
5. **Fluxo de resposta**: escolha o template ao criar (não muda depois), configure os botões e ligue **Usar como receptivo do número**.
6. **Teste**: mande "oi" de um celular, clique em um botão e acompanhe o toast, o sino e o painel do atendente.

## O que muda no deploy

- **Migrações**: `whatsapp_attendances`, `in_app_notifications`, `whatsapp_conversations.whatsapp_sender_number_id` (o `deploy` já roda `db:migrate`).
- **Job recorrente** (`config/recurring.yml`): `Whatsapp::AttendanceWindowSweepJob`, a cada 15 min. Encerra atendimentos cujo cliente não escreve há mais de 24h (janela do WhatsApp).
- **Filas do worker**: `realtime` (webhook e envio) e `default` (varredura, marcador de mensagem externa, repasse).
- **Redis**: o sino, o toast e a atualização em tempo real usam ActionCable via Redis (`REDIS_URL`).
- **Gateway** (`WHATSAPP_WEBHOOK_GATEWAY_URL`, `_INTERNAL_TOKEN`, `_FORWARDING_SECRET`): sem elas a rota do número não é registrada e o dev/produção rejeitam o webhook com 403.
- Sem variável nova de aplicação para atendimento e automação.

## Como o atendimento se comporta

- O clique em botão com envio para atendente abre um **atendimento** com dono (rodízio entre os atendentes marcados). Uma conversa tem no máximo um atendimento aberto.
- Encerra por: **Finalizar** (envia a mensagem de encerramento), o cliente iniciar outro assunto, ou a **janela de 24h** sem resposta do cliente.
- Enquanto há atendimento aberto o menu não volta. Depois de encerrado, texto livre do cliente devolve o menu (intervalo de 30 min; não interrompe conversa com humano nas últimas 12h).
- Transferência: automática (dono indisponível ou, se configurado no botão, sem abrir a conversa no prazo) ou manual, entre os colegas do grupo do botão.
- O prazo de "repassar se não abrir" é campo do próprio botão e **não** usa o bolsão/pocket da regra.

## Automação de conversa

- Botão com a ação **Iniciar automação** entrega a conversa a um fluxo cujo gatilho é "clique em botão do fluxo de resposta". Criar a partir de um template já monta um caminho por botão.
- Etapas: perguntar com botões (até 3), lista (até 10), resposta livre, passar para atendente. As respostas viram anotação no lead quando a conversa passa para um atendente.
- "Não entendi" pode repetir a pergunta até N vezes e depois seguir o caminho "Depois das tentativas".
- O clique que iniciou a conversa não conta como resposta; voltar ao menu cancela a conversa anterior que ainda esperava.

## Diagnóstico rápido

| Sintoma | Causa provável |
|---|---|
| Webhook chega ao dev/produção e volta 403 | Segredo do gateway (`..._FORWARDING_SECRET`) diferente do salvo no espelho/rota. |
| "tenant nao identificado" no log | O `phone_number_id` do evento não está cadastrado em Números de disparo daquela conta. |
| Número conectado mas não recebe | App não inscrito na WABA (use **Reconectar**) ou token sem acesso à WABA. |
| Menu não volta | Nenhum número marcado como receptivo, atendimento ainda aberto, ou humano respondeu nas últimas 12h. |
| Só aparece o texto do cliente | Respostas enviadas por **outro sistema** no mesmo número: a Meta só manda o status. O histórico mostra "Mensagem enviada por fora do sistema". |
| Erro 132001 ao enviar template | Template não existe na WABA do número usado; a conversa passou a responder pelo número que a recebeu. |
