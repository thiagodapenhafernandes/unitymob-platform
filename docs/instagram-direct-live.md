# Instagram Direct dentro do lead

A conversa mantém o composer fora do Turbo Frame de leitura. POST responde com Turbo Streams para mensagens/status; HTML continua com redirecionamento como fallback. Falha de envio mantém o texto. Sucesso limpa somente o mesmo texto que iniciou a requisição, preservando um novo rascunho digitado durante o envio.

InstagramMessage notifica após commit com Action Cable, apenas {refresh:true}, em stream por tenant/lead. A inscrição exige view/leads e o mesmo recorte de dono/equipe do HTTP, compartilhado em Lead.accessible_to_admin. Cada GET revalida esse acesso; revogação/transferência não libera conteúdo pela conexão aberta. Texto, contatos e tokens não são transmitidos no broadcast. Falha do Redis não desfaz a mensagem persistida; ao reconectar ou voltar à aba, o frame busca o estado atual.

A janela24h continua validada por Instagram::Reply antes de chamar a Meta; a interface atualiza a disponibilidade a partir do frame. Não altera API externa, permissões, credenciais, inscrições, callbacks ou piloto central.

Validação: specs de requests, canal e model, regressões Instagram/WhatsApp/acesso e testes Node do controller Stimulus. Produção exige confirmar serviços/Redis/assets e o refresh do frame mantendo rascunho; não enviar mensagens de clientes como smoke test.

Publicação compartilhada somente Salute/Conexão via Mina all; gateway e Central não integram este pacote. Sem migrations.


## Captação contextual e jornada de imóveis

### Continuidade da busca e auditoria do SDR

O pedido é consolidado em `other_information.instagram_search` por lead, respeitando o cursor do turno. Mantém os filtros interpretados e os critérios declarados mesmo depois da janela curta enviada à IA. Uma nova busca explícita reinicia os critérios; pedir mais opções preserva a busca. Respostas a perguntas de quartos/orçamento são interpretadas nesse contexto: `3` não vira código de imóvel, e `Até uns 12` em locação significa teto de R$ 12 mil. Código curto continua aceito quando solicitado explicitamente ou com marcador de código.

Locação anual exclui diárias. Orçamento com taxas limita a soma dos valores cadastrados de aluguel, condomínio e IPTU; encargos ausentes ou placeholders não comprovam compatibilidade e excluem o imóvel dessa busca. O total mostrado descreve os valores cadastrados, sem garantir encargos não informados. Os critérios explícitos prevalecem sobre uma interpretação divergente da IA. As permissões de dados da regra e o catálogo público do tenant continuam aplicáveis.

Apresentação explícita e contato voluntário são aproveitados. Uma resposta de região não vira nome durante uma pergunta de localização. Nomes inválidos são descartados apenas no processamento de novos turnos ainda sem responsável. `Anual` confirma a modalidade; pergunta como `Aluguel?` não confirma intenção sozinha. Uma busca suficientemente definida permite concluir a qualificação, mas a distribuição continua exigindo contato válido e a regra configurada da conta. Anúncio indisponível gera uma explicação e a aceitação de alternativas retoma a busca.

Atividades `instagram_sdr_decision` registram o ID da mensagem, filtros, modalidade, IDs públicos encontrados e resultado da decisão. Envio só registra sucesso com mensagem de saída persistida. Falha da auditoria não invalida a transação de atendimento. Não se registram prompts completos, tokens ou dados de contato nesses eventos. Essa evidência vale para turnos processados com a correção; não reconstitui decisões históricas.

Preparação Salute (17/11/2026): regra **18 — Instagram qualificado | Locação | Unitymob**, inativa até publicar e validar esta correção. Usa os oito participantes, ordem, pesos, horários e opções operacionais da fila interna de locação 9, com fila própria; restringe origem `Instagram Direct` e `instagram_qualified=true`, sem formulários Meta. A ativação deve ocorrer junto da publicação. Regras 9 (Meta locação), 16 (venda C2S) e 17 (locação C2S inativa) permanecem intactas. Nenhum lead histórico é redistribuído por esta preparação.

A identificação provisória usa `@username` quando disponível; o nome confirmado em `client_name` prevalece. `CaptureAnswer` aceita apresentações e telefone com DDD, sem confundir perguntas com nomes. O SDR responde consultas públicas antes da coleta de contato, inclusive quando a condição de IA salva exige contato. Respostas fixas e condições de encaminhamento continuam respeitando a exigência configurada. Nome/telefone fornecidos voluntariamente são aproveitados; uma dúvida já respondida não é repetida após completar o cadastro. A distribuição automática continua exigindo contato completo. Captações sem SDR preservam seus prompts e fluxo de coleta. A equipe pode assumir manualmente o atendimento.

Somente mensagens enviadas e persistidas geram `instagram_property_event/sent` na timeline. Não criam interesse por si só. Interesse explícito vincula `LeadPropertyInterest` apenas para referência identificável (link/código, ordinal da última lista, ou um único imóvel apresentado). Rejeição de imóvel e pedidos ambíguos não selecionam todas as opções. Geração de sugestões sem envio não registra apresentação.

Links próprios de imóveis, inclusive respostas manuais pelo composer, recebem `ig_ref`: referência assinada para o lead, com propósito específico e validade de 30 dias. A resolução sempre usa o tenant do site e exige contato Instagram ativo. O site não preenche dados do contato no HTML e não expõe nome/telefone via token. A página com referência não é compartilhada em cache, usa referrer policy same-origin e canonical sem o token. Aberturas são registradas apenas com consentimento de navegação; recusa não cria cookie de referência. Referência explícita no formulário ainda pode contextualizar a solicitação enviada pelo visitante.

O cookie assinado e HttpOnly conserva a referência no mesmo navegador para os formulários seguintes. `PropertyJourney.receive!` valida a entrada e concilia sob lock por conta e contato: completa nome/telefone do Instagram, registra a consulta e a conversão no imóvel, preservando a origem e o responsável existentes. Não absorve outro cadastro já identificado nem sobrescreve telefone/e-mail conflitante. Sem referência válida, mantém o intake habitual. O evento de conversão é registrado por contato/imóvel; uma nova solicitação do mesmo contato não infla a contagem de novos leads do site. Formulários configuráveis também carregam a referência para o job de roteamento; continuam exigindo telefone para produzir/complementar um lead.

Uma referência de link é contexto de origem, não prova de identidade: se o contato original ainda não tem telefone/e-mail, o primeiro formulário com dados inéditos completa esse cadastro. Não é possível detectar automaticamente um encaminhamento antes dessa primeira identificação. Depois dela, divergências seguem para um contato distinto. Sem cookie e fora da URL identificada (outro navegador/dispositivo), a conciliação depende dos dados de contato disponíveis.

Sem migrations ou backfill: históricos não são reinterpretados em lote. A limpeza de nomes obviamente capturados como perguntas é limitada às captações ainda pendentes que recebem nova mensagem. Não altera regras de distribuição ou o atendimento já assumido por um usuário.


## Imóvel da campanha e respostas com dados cadastrados

Na regra de campanha, Imóvel da campanha pesquisa código ou título apenas entre imóveis públicos do tenant. O vínculo é consultado também depois da primeira interação; código/link enviado pelo cliente prevalece. Referências recentes na conversa são usadas sem escolher arbitrariamente entre várias opções. Sem identificação segura, o bot pede código ou link e oferece o catálogo do site com a referência do Direct. Legendas preservadas são consultadas integralmente para referências explícitas como `Cód. 9705`; o código validado é salvo no contexto da mensagem para permanecer disponível além do histórico curto. Não deduz o imóvel por semelhança de descrição. Referências são revalidadas no catálogo público da própria conta a cada resposta; imóvel removido não é oferecido novamente.

`PropertyAnswer` responde sem exigir telefone e usa uma lista de fatos do imóvel público: preços anunciados, localização pública, nome cadastrado do edifício, finalidade atual, área, quartos, suítes, vagas e indicações positivas de financiamento/parcelamento. Nome do edifício obedece à permissão de localização; finalidade obedece à permissão de detalhes. Flags falsas por padrão não viram negativas comerciais. A IA retorna IDs dos fatos relevantes em JSON estruturado; o texto final é montado exclusivamente com os valores cadastrados, sem reaproveitar uma resposta livre gerada pelo modelo. Dados de proprietário, documentos internos, saldo devedor e valores mínimos não integram esse contexto.

O texto de Condições de negociação só entra se autorizado explicitamente na regra da campanha e somente para o imóvel vinculado. O controle exige acesso global a imóveis ou dono da conta. O operador deve manter nesse campo apenas termos que possam ser compartilhados ao autorizar seu uso. Não há inferência de entrada, juros, desconto, aprovação bancária ou aceite de proposta. Quando a informação pedida não está confirmada, o bot registra o encaminhamento, interrompe o SDR automático e sinaliza o corretor responsável; se não houver responsável, tenta o roteamento habitual. Sem contato completo, registra a pendência para atendimento humano sem disparar distribuição externa nem repetir a cobrança de dados.

Não há configuração automática de campanhas ou reenvio de respostas antigas. Sem migrations.

## Atendimento configurável e distribuição no encaminhamento

A aba `/admin/meta_integrations#meta-direct-capture-tab` inclui padrões iniciais por perfil, válidos para campanhas e contatos orgânicos. Configurações salvas têm precedência sobre os padrões, inclusive desativações explícitas. As campanhas herdam campos não definidos do padrão do perfil; o vínculo da campanha é contexto inicial e não impede buscar outro imóvel, código ou link desta mesma conta. A origem de aquisição permanece preservada.

Cada condição tem prioridade, identificação por expressões ou contexto com IA, ativação, permissão de IA, exigência de contato e ação (resposta fixa, IA ou encaminhamento). A primeira condição aplicável vence, independentemente da etapa de coleta. Consultas de IA ao catálogo não exigem nome/telefone prévios. A exigência de contato continua aplicável às condições de resposta fixa e encaminhamento; uma exceção configurada pode liberá-las antes da coleta. Distribuição automática exige contato válido. Condições sem permissão de IA não geram resposta com IA. Até 20 condições; mensagens limitadas a 1.000 caracteres.

`serving` mantém o lead sem corretor e bloqueia roteamento e contingência durante o atendimento da IA. Apenas o encaminhamento conclui esse estado e chama a distribuição habitual, mantendo elegibilidade e restrições das filas. Se nenhum corretor puder receber o encaminhamento, `handoff_pending` permite novas tentativas pela distribuição/contingência e mantém o SDR pausado: mensagens novas ou retries não repetem o aviso nem reiniciam a qualificação. Atribuição a qualquer corretor pausa todos os envios automáticos, mesmo sem mensagem humana. Assumir manualmente continua disponível. Conversões no site completam os dados e retomam o job, sem distribuir prematuramente.

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

A condição genérica de IA (`always`) consulta o catálogo, sem encaminhar apenas
porque identificou intenção comercial ou contato completo. Condições explícitas
de encaminhamento da conta mantêm prioridade. O e-mail opcional mantém seu prazo
e a possibilidade de pular. Sem contato completo, o SDR pode responder dúvidas
públicas normalmente. Após o encaminhamento, as filas
continuam exigindo página, modalidade, campanha, horários e participantes elegíveis.
Sem correspondência ou corretor elegível, o contato fica pendente, sem atribuição
forçada. Assumir manualmente prepara o mesmo contexto de origem e modalidade.
Não há backfill ou redistribuição em massa, nem ampliação do acesso a leads de
outros corretores. Sem migrations.


## Qualificação suficiente, retorno e destinos

`Instagram::Qualification` guarda evidência conservadora em `other_information.instagram_qualification`: modalidade Venda/Locação mais imóvel ativo com próximo passo explícito, ou uma busca com critérios mínimos. Legendas, menções, reações e perguntas isoladas não qualificam. Uma nova busca encerra a referência do imóvel anterior; recusas e captação do proprietário não disparam esse encaminhamento. O catálogo é consultado para responder à solicitação antes da coleta dos contatos faltantes. Depois da qualificação suficiente e do contato completo, a automação informa o encaminhamento e deixa a distribuição habitual decidir elegibilidade, fila e destino. Condições personalizadas de resposta fixa/encaminhamento e fluxos sem SDR mantêm suas regras.

O resumo é compartilhado pela conversa do lead, nota da timeline, variável já existente `lead_other_or_link` do template WhatsApp e observação de exportação C2S. Links seguros de telefone/e-mail continuam protegidos; o resumo sem contatos acompanha o link seguro de detalhes. Modalidade explícita do destino C2S tem prioridade sobre a modalidade inferida.

Quando um telefone/e-mail é informado, `ContactIdentity` reutiliza `Leads::Intake.matches` com o modo configurado na conta (`phone`, `phone_or_email`, `phone_and_email`). Um único cadastro operacional compatível recebe a identidade e o histórico de um provisório ainda sem responsável/efeitos operacionais. Dono, origem, status e regra do cadastro canônico são preservados. A auditoria original é imutável e continua vinculada ao ID anterior, registrado na nota de conciliação; atividades e mensagens acompanham o cadastro reaproveitado. Contatos ambíguos, perfis já vinculados e provisórios com vínculos operacionais não são unidos automaticamente. Não há match por nome ou @, nem busca entre contas.

Novas mensagens geram o aviso na linha existente da listagem e no sino; o responsável recebe push pelo dispatcher/configuração já existente. Acesso e leitura usam o mesmo escopo usuário/conta do lead. O cursor de leitura não apaga uma mensagem posterior. Não se redistribui um lead já atribuído.

A exportação global aguarda o encerramento da captação. Na Salute/configuração C2S, novos leads recebem modalidade e observação na criação. Leads já importados/exportados usam `SyncInstagramQualificationJob` para anexar o resumo com `PUT /leads/:id`, sem POST de criação, alteração de corretor ou status. Digest/checkpoint evita repetir a mesma atualização. Como o append remoto não oferece chave de idempotência confirmada, timeout fica `uncertain` e exige conciliação antes de reenviar o mesmo resumo. As simulações automatizadas usam as regras reais de fila e isolamento local; chamadas Meta, WhatsApp, push e C2S são isoladas, sem entrega real.


### Recorte de configuração verificado em 15/11/2026

Consulta somente leitura aos dois ambientes: Conexão possui regra Meta de Venda em rodízio com pocket; Locação não tem Meta habilitado. Salute tem C2S conectado com espelhamento, exportação global desligada e uma regra C2S de Locação exclusiva de campanha WhatsApp; não há regra de Instagram/C2S nem regra padrão de fallback. Por isso, preservando a configuração atual, um novo Instagram qualificado da Salute fica para encaminhamento manual. A criação no C2S foi simulada com destino Instagram explicitamente habilitado no teste; sua ativação na conta é uma configuração operacional separada. Atualizações de contexto em leads C2S já existentes são permitidas quando o espelhamento está habilitado, independentemente da exportação global de novos leads. Nenhuma configuração de produção foi alterada nesta implementação.

### Ativação do destino Instagram → C2S

Para habilitar uma conta sem ampliar a exportação global, configurar duas regras Meta/C2S, uma `venda`/`Compra` e outra `locacao`/`Aluguel`, limitadas às páginas selecionadas. Usar conjuntamente os filtros `origin = Instagram Direct` e `instagram_qualified = true`. O segundo é calculado por `Lead#instagram_qualified_for_delivery?`: identidade Instagram, qualificação suficiente, captura concluída/encaminhada e nome/telefone válidos. Não depende de uma flag manual que possa ficar desatualizada. Conversas ainda em atendimento, compartilhamentos sem intenção, recusa de telefone e outras fontes não correspondem a essas regras. Não ativar exportação global nem reaproveitar/modificar a regra exclusiva da campanha WhatsApp. Habilitar as regras não executa replay ou redistribuição do histórico.
