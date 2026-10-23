# Instagram Direct dentro do lead

A conversa mantém o composer fora do Turbo Frame de leitura. POST responde com Turbo Streams para mensagens/status; HTML continua com redirecionamento como fallback. Falha de envio mantém o texto. Sucesso limpa somente o mesmo texto que iniciou a requisição, preservando um novo rascunho digitado durante o envio.

InstagramMessage notifica após commit com Action Cable, apenas {refresh:true}, em stream por tenant/lead. A inscrição exige view/leads e o mesmo recorte de dono/equipe do HTTP, compartilhado em Lead.accessible_to_admin. Cada GET revalida esse acesso; revogação/transferência não libera conteúdo pela conexão aberta. Texto, contatos e tokens não são transmitidos no broadcast. Falha do Redis não desfaz a mensagem persistida; ao reconectar ou voltar à aba, o frame busca o estado atual.

A janela24h continua validada por Instagram::Reply antes de chamar a Meta; a interface atualiza a disponibilidade a partir do frame. Não altera API externa, permissões, credenciais, inscrições, callbacks ou piloto central.

Validação: specs de requests, canal e model, regressões Instagram/WhatsApp/acesso e testes Node do controller Stimulus. Produção exige confirmar serviços/Redis/assets e o refresh do frame mantendo rascunho; não enviar mensagens de clientes como smoke test.

Publicação compartilhada somente Salute/Conexão via Mina all; gateway e Central não integram este pacote. Sem migrations.
