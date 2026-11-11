# Instagram Direct dentro do lead

A conversa mantém o composer fora do Turbo Frame de leitura. POST responde com Turbo Streams para mensagens/status; HTML continua com redirecionamento como fallback. Falha de envio mantém o texto. Sucesso limpa somente o mesmo texto que iniciou a requisição, preservando um novo rascunho digitado durante o envio.

InstagramMessage notifica após commit com Action Cable, apenas {refresh:true}, em stream por tenant/lead. A inscrição exige view/leads e o mesmo recorte de dono/equipe do HTTP, compartilhado em Lead.accessible_to_admin. Cada GET revalida esse acesso; revogação/transferência não libera conteúdo pela conexão aberta. Texto, contatos e tokens não são transmitidos no broadcast. Falha do Redis não desfaz a mensagem persistida; ao reconectar ou voltar à aba, o frame busca o estado atual.

A janela24h continua validada por Instagram::Reply antes de chamar a Meta; a interface atualiza a disponibilidade a partir do frame. Não altera API externa, permissões, credenciais, inscrições, callbacks ou piloto central.

Validação: specs de requests, canal e model, regressões Instagram/WhatsApp/acesso e testes Node do controller Stimulus. Produção exige confirmar serviços/Redis/assets e o refresh do frame mantendo rascunho; não enviar mensagens de clientes como smoke test.

Publicação compartilhada somente Salute/Conexão via Mina all; gateway e Central não integram este pacote. Sem migrations.


## Captação contextual e jornada de imóveis

A identificação provisória usa `@username` quando disponível; o nome confirmado em `client_name` prevalece. `CaptureAnswer` aceita nomes curtos ou apresentações explícitas e telefone com DDD dentro de uma frase, recusando perguntas/saudações/descrições como nome. Mensagens consecutivas são consumidas juntas pelo cursor do Direct. Uma resposta fora do cadastro fica pendente enquanto o bot pede, de forma amigável, o nome confirmado e o telefone com DDD que faltarem. Recusa de telefone não libera resposta comercial ou encaminhamento automático; o @ permanece provisório. Jobs repetidos não reenviam a pergunta. Após receber os dados, o bot retoma a dúvida pendente. A equipe mantém a possibilidade de assumir manualmente o atendimento. Quando há pedido de atendimento humano, o cursor do SDR é encerrado. Prompts personalizados permanecem; os antigos textos padrão usam a nova redação.

Somente mensagens enviadas e persistidas geram `instagram_property_event/sent` na timeline. Não criam interesse por si só. Interesse explícito vincula `LeadPropertyInterest` apenas para referência identificável (link/código, ordinal da última lista, ou um único imóvel apresentado). Rejeição de imóvel e pedidos ambíguos não selecionam todas as opções. Geração de sugestões sem envio não registra apresentação.

Links próprios de imóveis, inclusive respostas manuais pelo composer, recebem `ig_ref`: referência assinada para o lead, com propósito específico e validade de 30 dias. A resolução sempre usa o tenant do site e exige contato Instagram ativo. O site não preenche dados do contato no HTML e não expõe nome/telefone via token. A página com referência não é compartilhada em cache, usa referrer policy same-origin e canonical sem o token. Aberturas são registradas apenas com consentimento de navegação; recusa não cria cookie de referência. Referência explícita no formulário ainda pode contextualizar a solicitação enviada pelo visitante.

O cookie assinado e HttpOnly conserva a referência no mesmo navegador para os formulários seguintes. `PropertyJourney.receive!` valida a entrada e concilia sob lock por conta e contato: completa nome/telefone do Instagram, registra a consulta e a conversão no imóvel, preservando a origem e o responsável existentes. Não absorve outro cadastro já identificado nem sobrescreve telefone/e-mail conflitante. Sem referência válida, mantém o intake habitual. O evento de conversão é registrado por contato/imóvel; uma nova solicitação do mesmo contato não infla a contagem de novos leads do site. Formulários configuráveis também carregam a referência para o job de roteamento; continuam exigindo telefone para produzir/complementar um lead.

Uma referência de link é contexto de origem, não prova de identidade: se o contato original ainda não tem telefone/e-mail, o primeiro formulário com dados inéditos completa esse cadastro. Não é possível detectar automaticamente um encaminhamento antes dessa primeira identificação. Depois dela, divergências seguem para um contato distinto. Sem cookie e fora da URL identificada (outro navegador/dispositivo), a conciliação depende dos dados de contato disponíveis.

Sem migrations ou backfill: históricos não são reinterpretados em lote. A limpeza de nomes obviamente capturados como perguntas é limitada às captações ainda pendentes que recebem nova mensagem. Não altera regras de distribuição ou o atendimento já assumido por um usuário.


## Imóvel da campanha e respostas com dados cadastrados

Na regra de campanha, Imóvel da campanha pesquisa código ou título apenas entre imóveis públicos do tenant. O vínculo é consultado também depois da primeira interação; código/link enviado pelo cliente prevalece. Referências recentes na conversa são usadas sem escolher arbitrariamente entre várias opções. Sem identificação segura, o bot pede código ou link e oferece o catálogo do site com a referência do Direct. Não deduz o imóvel pela descrição do anúncio.

`PropertyAnswer` só atende contato com nome confirmado e telefone válido e usa uma lista de fatos do imóvel público: preços anunciados, localização pública, área, quartos, suítes, vagas e indicações positivas de financiamento/parcelamento. Flags falsas por padrão não viram negativas comerciais. A IA retorna IDs dos fatos relevantes em JSON estruturado; o texto final é montado exclusivamente com os valores cadastrados, sem reaproveitar uma resposta livre gerada pelo modelo. Dados de proprietário, documentos internos, saldo devedor e valores mínimos não integram esse contexto.

O texto de Condições de negociação só entra se autorizado explicitamente na regra da campanha e somente para o imóvel vinculado. O controle exige acesso global a imóveis ou dono da conta. O operador deve manter nesse campo apenas termos que possam ser compartilhados ao autorizar seu uso. Não há inferência de entrada, juros, desconto, aprovação bancária ou aceite de proposta. Quando a informação pedida não está confirmada, o bot registra o encaminhamento, interrompe o SDR automático e sinaliza o corretor responsável; se não houver responsável, tenta o roteamento habitual. Sem contato completo, preserva a captação antes desse encaminhamento.

Não há configuração automática de campanhas ou reenvio de respostas antigas. Sem migrations.

## Atendimento configurável e distribuição no encaminhamento

A aba `/admin/meta_integrations#meta-direct-capture-tab` inclui padrões iniciais por perfil, válidos para campanhas e contatos orgânicos. Configurações salvas têm precedência sobre os padrões, inclusive desativações explícitas. As campanhas herdam campos não definidos do padrão do perfil; o vínculo da campanha é contexto inicial e não impede buscar outro imóvel, código ou link desta mesma conta. A origem de aquisição permanece preservada.

Cada condição tem prioridade, identificação por expressões ou contexto com IA, ativação, permissão de IA, exigência de contato e ação (resposta fixa, IA ou encaminhamento). A primeira condição aplicável vence, independentemente da etapa de coleta. O padrão exige nome e telefone; uma exceção configurada pode responder antes da coleta. Encaminhamento automático sempre exige contato válido. Condições sem permissão de IA não geram resposta com IA. Até 20 condições; mensagens limitadas a 1.000 caracteres.

`serving` mantém o lead sem corretor e bloqueia roteamento e contingência durante o atendimento da IA. Apenas o encaminhamento conclui esse estado e chama a distribuição habitual, mantendo elegibilidade e restrições das filas. Se nenhum corretor puder receber o encaminhamento, `handoff_pending` permite novas tentativas pela distribuição/contingência e a IA continua disponível para novas mensagens. Atribuição a qualquer corretor pausa todos os envios automáticos, mesmo sem mensagem humana. Assumir manualmente continua disponível. Conversões no site completam os dados e retomam o job, sem distribuir prematuramente.

Mensagens de dados pendentes, identificação do imóvel e encaminhamento são editáveis, assim como as instruções de atendimento. A lista de dados públicos autorizados filtra fatos enviados ao modelo e também recomendações/cartões. Condições de negociação continuam exigindo autorização adicional por imóvel; nunca são liberadas por uma permissão genérica. Sem confirmação no cadastro, encaminha ao corretor.

O indicador de digitação é enviado antes da geração da resposta, usando o endpoint da página para Facebook Login, com apenas `recipient` e `sender_action`. Tem ativação e duração mínima de 0–5 segundos configuráveis e encerramento garantido em caso de erro. Falhas da Meta registram apenas classe/código do erro e não impedem a resposta. Validação visual de entrega depende do aplicativo Instagram e não é simulada enviando mensagens a clientes reais.


## Encaminhamento comercial do Direct (11/11/2026)

Entradas orgânicas também registram a página Meta autorizada da própria conta,
sem depender de campanha/anúncio. O contexto é reconstruído ao liberar um contato
antigo usando a conta Instagram vinculada; não aceita página de outro tenant,
inativa ou desmarcada na integração. Não inventa campanha para corretores que
recebem apenas campanhas específicas.

Uma manifestação afirmativa do cliente (por exemplo, `Comprar` ou `Quero alugar`)
registra `business_type` e o ID da mensagem em
`instagram_capture.business_type_message_id`. Perguntas, negativas, respostas
ambíguas, nomes de campanhas e sugestões do bot não identificam modalidade.
A extração considera até as últimas 20 mensagens recebidas e preserva modalidade
explícita já cadastrada.

Com nome e telefone válidos e natureza comercial identificada, a condição genérica
de IA (`always`) encaminha à equipe, em vez de manter a qualificação indefinidamente.
Condições específicas configuradas pela conta mantêm prioridade. O e-mail opcional
mantém seu prazo/possibilidade de pular. Contatos incompletos permanecem na captura;
sem modalidade, o SDR pode continuar a triagem. Após o encaminhamento, as filas
continuam exigindo página, modalidade, campanha, horários e participantes elegíveis.
Sem correspondência ou corretor elegível, o contato fica pendente, sem atribuição
forçada. Assumir manualmente prepara o mesmo contexto de origem e modalidade.
Não há backfill ou redistribuição em massa, nem ampliação do acesso a leads de
outros corretores. Sem migrations.
