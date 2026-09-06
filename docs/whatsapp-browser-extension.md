# Extensão Unitymob para WhatsApp

O piloto de atendimento 0.3.0 está implementado em `browser-extension/`. Consulte o [guia do piloto](../browser-extension/README.md) para build, ativação, limites e critérios de validação.

A extensão adiciona um cliente de atendimento ao CRM existente: o Chrome identifica o contato e apresenta a ficha; o Rails decide a conta, o escopo de acesso e os dados comerciais. Não há CRM paralelo, sincronização de mensagens ou nova integração de envio.

A autorização possui tabela própria (`browser_extension_grants`) e não reutiliza o JWT mobile. Sessão web autenticada aprova um desafio de uso único; o worker troca o verifier por credencial limitada à extensão. O token fica fora da página do WhatsApp. Cada API revalida as regras de acesso atuais. A conta autorizada permanece visível no painel; mudar de conta no site não troca silenciosamente a conta da extensão.

O painel usa os componentes `ax-*` existentes. O componente compartilhado de formulários ganhou apenas fallbacks para a altura/raio já usados no admin, permitindo uso fora do stylesheet completo. Não foram alterados menus ou fluxos comerciais existentes.

Implantação: migration nova, variáveis explícitas de tenant/ID, pacote Chrome e validação em homologação. Desativação: retirar a conta da variável de habilitação e reiniciar o backend; concessões deixam de autenticar. Preservar a tabela para histórico durante rollback funcional. Exclusão de usuário/dispositivo remove suas concessões pelos relacionamentos dependentes e pela classificação no HardDeleter.

Estado atual: login/aceite/grupos confirmados pelo usuário na versão 0.2.0. A versão 0.3.0 acrescenta cadastro de lead, nota interna e tarefa. Implementação e validação automatizada locais concluídas; falta recarga no Chrome e prova com conversa individual. Publicação em produção não realizada.

## Evidência local desta entrega

- Suite de extensão/API, política de acesso e login web/mobile: **38 exemplos, 0 falhas**.
- `rake security:tenant_isolation`: **46 exemplos, 0 falhas**. Inclui testes que também pertencem à suite acima; os totais não representam exemplos únicos somados.
- `browser-extension/npm test`: **16 testes, 0 falhas**, incluindo contexto e worker.
- `rails zeitwerk:check`: aprovado.
- Build CSS do projeto e build da extensão: aprovados.
- `git diff --check`: aprovado.
- Migration aplicada somente no banco local dedicado `unitymob_whatsapp_extension_test` (PostgreSQL localhost:5433).
- Prévia de 360 px com dados fictícios: campos contidos na largura do painel; cabeçalhos, imóvel vinculado e tarefa legíveis. Nenhum acesso a conversa real nessa validação.
- Artefato `browser-extension/unitymob-whatsapp-0.1.0.zip`: 16 arquivos; manifesto sem permissões genéricas de navegação, sem ponte externa e sem arquivos de sessão ou mocks.

As suites emitem avisos já existentes de depreciação Rails/Rack e OID de geolocalização; não houve falha de validação. O checkout original e seus arquivos em andamento foram preservados. Não houve commit, push, deploy ou ativação em produção.

## Piloto local pelo túnel — 05/09/2026

O usuário instalou a extensão e confirmou a abertura do painel no WhatsApp Web. O túnel SSH existente encaminha `https://dev.unitymob.com.br` para a porta local 3001. Essa porta agora executa o checkout `unitymob-platform-whatsapp-extension` em development, no lugar do servidor do checkout original. A configuração privada de desenvolvimento foi copiada para o `.env.development` ignorado do worktree, com habilitação restrita ao tenant local 72 (Conexão) e ao ID do pacote.

A migration de concessões foi aplicada à base **local** `unitymob_platform_dual_tenant_local`, localhost:5433. A API através do túnel retorna 401 JSON quando não há credencial, conforme esperado. Outros tenants continuam desabilitados. Não houve alteração em produção, no túnel ou nos arquivos de trabalho do checkout original.

A sessão observada no navegador interno estava em impersonação; esse modo não pode aprovar a extensão. O pareamento deve ser autorizado no Chrome por um usuário real da conta local. Abertura confirmada não equivale a pareamento ou consulta comercial já comprovados.

Servidor local: `PORT=3001 rvm 3.2.3 do bundle exec rails server -d -b 127.0.0.1 -p 3001`, executado no worktree da extensão. PID registrado pelo Rails em `tmp/pids/server.pid`; verificar o processo antes de parar. Para voltar ao checkout original, encerrar esse servidor e iniciar o servidor original na mesma porta; a migration aditiva pode permanecer. Nenhum worker adicional foi iniciado.


## Ajuste de entrada — versão 0.2.0

O clique no [U] abre ou ativa o WhatsApp na mesma janela e abre o painel pelo gesto de usuário. O endereço sai da interface; o pacote local aponta diretamente para dev.unitymob.com.br.

O login é iniciado no painel por Entrar na Unitymob e usa a janela segura de `chrome.identity.launchWebAuthFlow`. O login web/TOTP volta à continuação da extensão somente quando há contexto válido e não expirado. O POST autenticado com CSRF emite um código assinado de curta duração no callback fixo do ID da extensão. A troca exige esse código e o verifier; não é possível usar somente um desafio obtido de um link. Referência: https://developer.chrome.com/docs/extensions/reference/api/identity . Abertura pelo gesto: https://developer.chrome.com/docs/extensions/reference/api/sidePanel .

Depois do login, o painel mostra o texto dos termos do piloto e um checkbox inicialmente desmarcado. A API bloqueia leitura comercial até registrar data/versão/hash do aceite na concessão. A inspeção de contexto WhatsApp também fica bloqueada no worker até o aceite. Sessões anteriores precisam aceitar os termos. A migration 20260906013000 foi aplicada somente no banco local do piloto e no banco isolado de testes.

Validação desta alteração: 31 exemplos Rails de extensão/login web/mobile, 22 testes JavaScript, build do pacote e Zeitwerk aprovados. O texto exibido nos termos é específico deste piloto; não houve publicação de termos legais definitivos nem alteração dos termos dos sites. Validação visual usa mocks; o teste completo da nova versão instalada depende da recarga manual da extensão pelo usuário, pois a ferramenta de navegador bloqueou acesso a chrome://extensions.

A prévia local com mocks confirmou login → termos (checkbox desmarcado e botão desabilitado) → atendimento após aceite. A versão instalada 0.2.0 ainda precisa ser recarregada no Chrome para validação real do clique e da janela de autenticação.


## Atendimento — versão 0.3.0

Prioridade escolhida pelo usuário: criar lead, registrar notas e agendar tarefas. Os três formulários foram implementados usando os componentes compartilhados e confirmação explícita do contato. Os endpoints usam as permissões e modelos existentes, com atribuição ao usuário conectado e escopo por conta/equipe. Cadastro manual mantém o funil inicial, callbacks, notificações e automações do CRM; nota interna não vira tentativa de contato; tarefa do tipo Visita não cria um Appointment.

Recibos em `browser_extension_operations` são gravados na mesma transação dos registros. Timeout/retry conserva a chave, impede duplicação e rejeita mudança de conteúdo na mesma tentativa. Metadados de autoria usam `source: browser_extension`. Notas e dados dos formulários são filtrados dos logs. A versão v2 dos termos exige novo aceite; permissões de escrita são independentes e revalidadas no servidor.

Migration 20260906023000 aplicada somente aos bancos locais do piloto e isolado de testes. Pacote descompactado atualizado no mesmo `browser-extension/dist/`, zip `unitymob-whatsapp-0.3.0.zip`. Sem novas permissões Chrome. Servidor local do worktree reiniciado na porta 3001 para receber a configuração de logs; túnel preservado.

Validação: 38 exemplos Rails (extensão, login web e mobile), 27 testes JavaScript, Zeitwerk, build da extensão e diff check aprovados. Prévia de 360 px com dados fictícios confirmou criar lead → nota salva → tarefa exibida com data/hora. Essa prévia não grava no CRM. Nenhum lead, nota ou tarefa foi criado em dados reais durante os testes. Falta validação do fluxo completo no WhatsApp instalado após recarga; nenhum deploy, commit ou push realizado.

## Investigação de imobiliária do contato — 0.3.2

A suspeita sobre os leads 1980, 2342 e 3463 foi investigada no banco local, no payload importado e nas duas bases de produção, com consultas em transações READ ONLY. A conclusão inicial de classificação errada no banco local foi refutada: os três registros existem também na base `imobiliariaconexao`, tenant 72, com a empresa de origem C2S `CONEXAO BC POR TONINHO RONCAGLIO`. Dois têm responsáveis da Conexão e um não tem responsável; todos estavam descartados. O mesmo telefone aparece em outros registros na Salute, e a pessoa é corretora da Salute. Identidade do contato e propriedade do atendimento são relações diferentes.

A consulta da extensão restringe `leads.tenant_id = grant.tenant_id`, inclusive para o usuário com escopo all, e agrupa corretamente os predicados OR dos telefones. Nenhum registro foi transferido, removido ou alterado, localmente ou em produção. Backup preventivo local foi criado em `tmp/tenant-repair-20260905-224659/before.dump`, com permissões 0600, antes de concluir a investigação.

Ajuste 0.3.2: resultados explicam que a busca é por telefone dentro da imobiliária conectada; cada opção e ficha mostram responsável, origem e data de cadastro. O backend inclui somente esses campos adicionais e faz preload dos responsáveis na resolução. Teste específico cobre o mesmo nome/telefone em duas imobiliárias com usuário de escopo all, sem retornar ou permitir abrir o lead externo. As permissões existentes não foram ampliadas.
