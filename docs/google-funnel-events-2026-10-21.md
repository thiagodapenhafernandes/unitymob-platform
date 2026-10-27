# Eventos Google por etapa — preparação local

Implementação compartilhada por todas as contas, sem ativação automática. Etapas existentes e novas começam em `Nenhum`. Na configuração de webhook, selecionar explicitamente o destino GTM/STAPE da conta; somente um destino Google por conta, HTTPS e chaves Active Record Encryption obrigatórios. O segredo opcional é criptografado e enviado em `X-Webhook-Secret`; campo vazio mantém o segredo existente.

Mapeamentos: `qualify_lead` → qualificado; `visit` → `working_lead`/visita; `proposal` → `working_lead`/proposta; `closed` → `close_convert_lead`/fechamento. Mapeamentos repetidos mostram aviso após salvar. A configuração é isolada por etapa e funil. Salvar uma etapa não altera inscrições dos webhooks da conta. A inscrição geral `qualified_lead` continua disponível no webhook legado, mas não substitui o mapeamento de conversão da etapa.

O botão Fechado abre um formulário compartilhado entre desktop e mobile com **Comissão real do fechamento (opcional)**. Valor em reais, formato brasileiro, armazenado em centavos, não negativo e auditado. Não usa preço do imóvel ou comissão estimada. O valor precisa ser informado antes do primeiro evento de fechamento: sem comissão, o evento omite `value` e `currency`; com comissão, envia número e BRL. Editar depois não modifica nem reenvia o evento já registrado.

Outbox com unicidade de lead/tipo e snapshot criptografado de payload e destino. Identidade usa o e-mail original do audit de criação; ausência de e-mail original ou modalidade válida registra evento ignorado com motivo. Modalidade venda/aluguel fica fixada no primeiro registro válido. Nome/telefone são opcionais. Horário da transição em America/Sao_Paulo, IDs e payload permanecem estáveis nas tentativas. Importações que suprimem roteamento não geram conversões históricas.

Job assíncrono com uma tentativa inicial e até três repetições (1, 5 e 30 minutos), aceitando somente HTTP 2xx. Registra status/classe do erro, sem corpo de resposta nem identidade nos logs. Não segue redirecionamentos e reaproveita a política contra destinos privados. Desativação ou troca do destino interrompe o envio pendente. Recuperação a cada cinco minutos reenfileira pendências; jobs concorrentes são serializados pelo registro. Uma interrupção depois do aceite remoto pode repetir a chamada: o receptor precisa deduplicar os IDs estáveis, pois não existe transação distribuída entre banco e HTTP.

Fora de produção, o transporte força `diagnostic: true`. Testes isolam HTTP; nenhum evento real, replay, configuração de conta, alteração em produção ou deploy foi executado. As duas migrations precisam ser aplicadas no futuro deploy. Aceitação pelo GTM/STAPE e Google Ads depende de validação externa posterior; não foi demonstrada por estes testes.

Validação local: 104 exemplos Rails e 3 testes JavaScript sem falhas; Zeitwerk e build CSS aprovados. Migration da comissão revertida e reaplicada somente no banco de testes. A suíte completa e a aceitação externa não foram executadas.


## Evento e ação por etapa — evolução de 27/10/2026

O editor de etapas e a criação de funil reutilizam o mesmo componente para Meta
e Google. Cada provedor tem evento e **Quando disparar** independentes:

- Ao entrar na etapa (`stage_entered`): mantém o comportamento anterior.
- Ao marcar como qualificado (`qualified`): primeira avaliação qualificada do
  corretor ou gestor, conforme a ação já disponível no card. Distribuir ou
  colocar Em Atendimento não qualifica o lead.
- Ao concluir uma visita (`visit_completed`): compromisso do tipo visita muda
  para realizado; agendamento, reunião e edição de observações não contam.
- Ao enviar uma proposta (`proposal_sent`): proposta muda para enviada; criar
  rascunho ou aceitar uma proposta não representa esse evento.
- Ao concluir o negócio (`deal_closed`): transição para uma etapa configurada
  como ganha. Configurar na etapa de destino do fechamento. Não usa o nome
  da etapa para selecionar o evento.

A ação é avaliada na etapa atual do lead, com escopo por conta e funil e somente
em etapas ativas. No Google, cada evento aceita entrada de etapa ou a ação
correspondente (qualificação, visita, proposta ou fechamento). Na Meta, o evento
pode ser associado explicitamente a qualquer ação da lista. Deduplicação,
identidade original, UID e snapshot Google permanecem nos mecanismos existentes.
O instante da visita/proposta é o da ação, não o da última edição do lead.

Integração ausente ou sem credenciais utilizáveis deixa os controles desabilitados
com uma explicação e mantém configurações anteriores. Com integração configurada,
mas pausada, o mapeamento pode ser preparado sem ativar o envio. Google considera
o destino HTTPS e a disponibilidade da criptografia; Meta considera datasets e
token não expirado da conta. Estado ativo exige também a ativação correspondente.
Essa verificação não faz chamada externa nem comprova permissões no provedor.
Outras integrações não são inferidas por haver uma conexão com o mesmo fornecedor:
GTM/Google Ads, GA4, Meta Ads e WhatsApp têm controles próprios.

Callbacks das ações Google registram a outbox na transação local; os da Meta
agendam depois do commit. Nenhum envio síncrono é adicionado às ações comerciais.
Importações com roteamento suprimido não geram eventos. Etapas sem evento não
herdam conversões de uma inscrição global nem de outro funil.

A migration `20261027160000` adiciona os dois seletores de momento com padrão de
entrada da etapa, preservando mapeamentos existentes. Não preenche leads,
não altera eventos históricos e não ativa contas. Nesta preparação, aplicação e
reversão são verificadas somente nos bancos locais; produção permanece intacta.
