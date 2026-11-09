# Instagram Direct dentro do lead

A conversa mantém o composer fora do Turbo Frame de leitura. POST responde com Turbo Streams para mensagens/status; HTML continua com redirecionamento como fallback. Falha de envio mantém o texto. Sucesso limpa somente o mesmo texto que iniciou a requisição, preservando um novo rascunho digitado durante o envio.

InstagramMessage notifica após commit com Action Cable, apenas {refresh:true}, em stream por tenant/lead. A inscrição exige view/leads e o mesmo recorte de dono/equipe do HTTP, compartilhado em Lead.accessible_to_admin. Cada GET revalida esse acesso; revogação/transferência não libera conteúdo pela conexão aberta. Texto, contatos e tokens não são transmitidos no broadcast. Falha do Redis não desfaz a mensagem persistida; ao reconectar ou voltar à aba, o frame busca o estado atual.

A janela24h continua validada por Instagram::Reply antes de chamar a Meta; a interface atualiza a disponibilidade a partir do frame. Não altera API externa, permissões, credenciais, inscrições, callbacks ou piloto central.

Validação: specs de requests, canal e model, regressões Instagram/WhatsApp/acesso e testes Node do controller Stimulus. Produção exige confirmar serviços/Redis/assets e o refresh do frame mantendo rascunho; não enviar mensagens de clientes como smoke test.

Publicação compartilhada somente Salute/Conexão via Mina all; gateway e Central não integram este pacote. Sem migrations.


## Captação contextual e jornada de imóveis

A identificação provisória usa `@username` quando disponível; o nome confirmado em `client_name` prevalece. `CaptureAnswer` aceita nomes curtos ou apresentações explícitas e telefone com DDD dentro de uma frase, recusando perguntas/saudações/descrições como nome. Mensagens consecutivas são consumidas juntas pelo cursor do Direct. Uma resposta fora do cadastro é atendida pelo catálogo contextual (se SDR ativo) ou encaminhada à equipe, sem reenviar o pedido de nome/telefone. A recusa de telefone permite seguir pelo Instagram. Quando há pedido de atendimento humano, o cursor do SDR é encerrado. Prompts personalizados permanecem; os antigos textos padrão usam a nova redação.

Somente mensagens enviadas e persistidas geram `instagram_property_event/sent` na timeline. Não criam interesse por si só. Interesse explícito vincula `LeadPropertyInterest` apenas para referência identificável (link/código, ordinal da última lista, ou um único imóvel apresentado). Rejeição de imóvel e pedidos ambíguos não selecionam todas as opções. Geração de sugestões sem envio não registra apresentação.

Links próprios de imóveis, inclusive respostas manuais pelo composer, recebem `ig_ref`: referência assinada para o lead, com propósito específico e validade de 30 dias. A resolução sempre usa o tenant do site e exige contato Instagram ativo. O site não preenche dados do contato no HTML e não expõe nome/telefone via token. A página com referência não é compartilhada em cache, usa referrer policy same-origin e canonical sem o token. Aberturas são registradas apenas com consentimento de navegação; recusa não cria cookie de referência. Referência explícita no formulário ainda pode contextualizar a solicitação enviada pelo visitante.

O cookie assinado e HttpOnly conserva a referência no mesmo navegador para os formulários seguintes. `PropertyJourney.receive!` valida a entrada e concilia sob lock por conta e contato: completa nome/telefone do Instagram, registra a consulta e a conversão no imóvel, preservando a origem e o responsável existentes. Não absorve outro cadastro já identificado nem sobrescreve telefone/e-mail conflitante. Sem referência válida, mantém o intake habitual. O evento de conversão é registrado por contato/imóvel; uma nova solicitação do mesmo contato não infla a contagem de novos leads do site. Formulários configuráveis também carregam a referência para o job de roteamento; continuam exigindo telefone para produzir/complementar um lead.

Uma referência de link é contexto de origem, não prova de identidade: se o contato original ainda não tem telefone/e-mail, o primeiro formulário com dados inéditos completa esse cadastro. Não é possível detectar automaticamente um encaminhamento antes dessa primeira identificação. Depois dela, divergências seguem para um contato distinto. Sem cookie e fora da URL identificada (outro navegador/dispositivo), a conciliação depende dos dados de contato disponíveis.

Sem migrations ou backfill: históricos não são reinterpretados em lote. A limpeza de nomes obviamente capturados como perguntas é limitada às captações ainda pendentes que recebem nova mensagem. Não altera regras de distribuição ou o atendimento já assumido por um usuário.
