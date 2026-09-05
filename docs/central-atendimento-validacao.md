# Validação da central de atendimento

Branch: `codex/central-atendimento`, base `b228c36e`. Worktree separado de `develop`; alterações locais anteriores preservadas. Nenhum commit, push, provisionamento ou deploy executado.

## Verificações executadas

- CRM: 15 testes novos passaram (`spec/requests/support` e `spec/services/support`). Incluem criação, permissões por solicitante/owner, escopo por conta, entrega com retries, deduplicação, eventos atrasados, recusas definitivas, revogação e acesso assistido.
- Central: 22 testes passaram, incluindo login, ativação, TOTP, código por e-mail, SMTP indisponível, expiração/tentativas, os três perfis, conversa, notas internas, estado resolvido e autenticação HMAC.
- Vizinhos: 29 de 30 testes passaram nas suítes de impersonação, perfis e 2FA. A falha em `permissions_profiles_spec.rb:65` (captação da equipe não exibida) foi reproduzida separadamente na base limpa `b228c36e`: 1 exemplo, 1 falha. Não foi corrigida nesta feature.
- `zeitwerk:check`: passou nas duas aplicações.
- Migrations: aplicadas em bancos locais isolados; nenhuma migration em produção.
- Assets CSS/JS: compilação Rails passou nas duas aplicações.
- Mina da central: simulação passou, sem conexão/deploy remoto.
- Navegador: login TOTP, dashboard, fila e conversa foram abertos com dados fictícios; login por e-mail também inspecionado em viewport estreita, sem overflow horizontal.
- SMTP Umbler: autenticação real com STARTTLS confirmada. O fluxo de código foi testado com ActionMailer em modo de testes; entrega à caixa de entrada será confirmada no primeiro login do administrador.

## Limites da validação

Não houve teste em Salute/Conexão de produção, provisionamento do novo servidor, DNS/TLS público, envio push real ou prova de restauração de backup. Esses itens pertencem ao piloto/publicação descritos no runbook. Não alegar que uma compilação ou `/up` prova operação em produção.

## Atualização: registro automático e widget (05/09)

- CRM: **20 testes passaram**. Central: **25 testes passaram**. Incluem autenticação do servidor, replay/assinatura inválida, separação de IDs iguais entre servidores, idempotência sem reativar contas bloqueadas, recuperação da fila, modal e lembretes pessoais.
- Vizinhos: **29 de 30 passaram**, mantendo apenas a falha preexistente de captação já reproduzida na base limpa. Nenhuma nova falha nesse conjunto.
- Zeitwerk e compilação de assets passaram nas duas aplicações; `git diff --check` passou.
- Banco local `unitymob_platform_dual_tenant_local`: migrations aditivas de suporte aplicadas. Sete contas locais, incluindo Salute e Conexão, registradas automaticamente. Nenhuma alteração de banco em produção.
- `dev.unitymob.com.br` passou a servir o worktree da feature pela porta 3001, preservando o checkout original. Central na porta 4020. Workers locais ativos, CRM restrito à fila `support_local`.
- Teste real pelo navegador: usuário QA da Conexão abriu chamado pelo dropdown em modal, permaneceu no dashboard e anexou PNG. O operador recebeu na central, baixou o PNG (HTTP 200, 52.102 bytes), respondeu; o lembrete apareceu no canto inferior direito da plataforma. Usuário respondeu, central mudou para Em atendimento; operador resolveu, e a conta recebeu Resolvido, bloqueou novas mensagens e ofereceu continuação em novo chamado. Entregas pendentes ao final: zero nos dois lados.
- Chamado QA local #1 preservado para conferência. Usuário e operador temporários foram desativados após a validação. Nenhuma mensagem enviada a clientes reais.
- Modal conferida em desktop e viewport mobile de 390 px; sem transbordamento horizontal, conteúdo rolável e fechamento acessível. Reutiliza `ax_quick_modal`/`ax-modal` do CRM. A abertura não aciona mais o preloader de navegação.
- Corrigida a inicialização real de `central/bin/jobs` para usar `SolidQueue::Cli.start(ARGV)`. No macOS local, central usa `--mode=async` devido a crash do driver pg ao fazer fork. Worker do CRM e sua recorrência foram observados processando os eventos de suporte.

Ainda pendentes para produção: provisionamento/configuração por servidor, publicação dos dois aplicativos, armazenamento privado/backup e piloto produtivo. O lembrete no navegador foi comprovado; entrega de push a um dispositivo real não fez parte deste teste.

## Acesso de todos os usuários (05/09)

Removida a exigência de permissão `support_tickets.view` do menu e dos endpoints. Usuários autenticados de contas ativas podem abrir e acompanhar seus próprios chamados, inclusive na impersonação administrativa. O proprietário mantém a visão da conta; o controle de acesso assistido da central permanece separado. Removida a opção de permissão do catálogo de perfis para não apresentar um controle sem efeito.

Validação: 23 testes de suporte, registro automático e impersonação passaram. Cobertura inclui criação com a identidade do usuário representado, acesso negado às conversas de outros usuários/contas e bloqueio de conta desativada. Sem migration ou alteração manual de perfis.

## Formulário amigável e SLA (05/09)

- Cinco perguntas em selects, cada uma com Outro e detalhe obrigatório. Telas vêm do menu autorizado do próprio perfil. Título automático; incentivo a print e suporte a colar imagem.
- Contexto assinado vincula usuário/conta/tela. URL sem query, identificador da requisição e referências de erros recentes do mesmo usuário/tenant; sem mensagens de erro, backtraces ou formulários.
- Central: eventos persistidos de recebimento, resposta, mudança de estado/responsável; tempos corridos, espera pelo usuário, metas históricas, relatório Admin com filtros e paginação.
- Presença por confirmações de aba visível, intervalos de até 75 segundos e união de sessões simultâneas. Login após 2FA, logout explícito, expiração e revogação distintos. Conexão não comprova trabalho humano. Sessões anteriores exigem novo login; tickets antigos sem eventos ficam sem medição.
- Testes: 23 exemplos no CRM e 30 na central. Zeitwerk e assets passaram em ambos. Central de testes usa DB_PORT=5433; tentativa sem essa configuração falhou por banco ausente na porta padrão.
- Navegador: chamado QA #2 recebido, atribuído, respondido e resolvido; aviso de conclusão entregue ao CRM. Primeira resposta 4min15s, resolução 4min28s, espera pelo usuário 13s. Dashboard: 1 resposta/1 resolução. Logout registrado; contas QA desativadas. Entregas pendentes: zero em ambos.
- Dashboard em 390px sem overflow horizontal da página; tabelas têm rolagem própria.
- A pedido do usuário, metas locais demonstrativas: alta 60/480 minutos, normal 240/1440, baixa 480/2880 (primeira resposta/resolução). Auditadas com origem demonstration e aviso na interface; nenhum histórico de atividade fabricado.
- Mudanças locais na branch codex/central-atendimento; sem commit, push ou deploy.

## Painel de entrada operacional (05/09)

Substituídos cartões genéricos por fila atual (espera por suporte/usuário, atrasos, prazos em dia e ausência de responsável), próximos 10 atendimentos priorizados, resultados da coorte de 30 dias, equipe ativa com carga/presença e contas com comunicação pendente/falha. Tempos usam horas, minutos e segundos inteiros. Sem histórico/meta suficiente não significa em dia. Área de equipe/contas restrita ao Admin; financeiro mantém sua tela. Painel renderizado na sessão real do administrador no navegador local. Sem alteração de dados ou deploy.

## Caixa de atendimento (05/09)

Fila da central em duas colunas, usando Turbo Frames: filtros/lista à esquerda e conversa à direita. Respostas, notas e controles permanecem no frame; URL independente do chamado continua disponível. Atualização a cada 15 segundos, sem substituir formulário em edição ou interromper áudio em reprodução. No celular, lista/conversa alternam com Voltar à fila.

Anexos com prévia de imagem e player para arquivos de áudio; conteúdo continua sob autenticação/escopo. Áudio transportado pela mesma fila e validado por MIME detectado na entrada. Sem gravação de microfone nesta versão: envio de arquivos MP3/M4A/OGG/WAV/WebM suportados pelo navegador.

34 testes da central e 23 do CRM passaram (57), incluindo resposta em frame, transporte WAV e bloqueio de áudio para financeiro. Assets compilados nos dois aplicativos. Desktop comprovou colunas 340px/restante, URL permanece na fila após seleção. Mobile 390px sem overflow e com alternância lista/conversa. Web e workers locais reiniciados para carregar assets e formatos novos. Sem deploy.

## Referência NotificaLead (05/09)

Tela adaptada após leitura de `notificalead/app/views/support/tickets/show.html.erb`, `_active_outreach_form.html.erb` e controllers. Filtros por ID/nome/e-mail, datas, origem ativa/receptiva, meus chamados e ordenação; responsável no cartão, abas, pré-perguntas/métricas e editor de formatação simples (HTML escapado). Comportamento do cliente preservado e templates centrais separados, compartilhando mensagens, editor e cabeçalho.

Migration aditiva `20260905180000` nos quatro bancos locais: origem/tipo/e-mail no ticket e autoria/revisões/remoção lógica da mensagem. Diretório HMAC limitado ao tenant. Contato ativo validado no destino e entregue por outbox ordenado; eventos repetidos não duplicam, revisões antigas não sobrescrevem. Edição por autor/admin de mensagem pública de suporte, apenas enquanto aberto; conteúdo anterior em auditoria. Nenhuma exclusão física.

QA #3: abertura ativa para usuário local 6156, entrega comprovada ao CRM, mensagem editada/removida sincronizada, notas internas ausentes no CRM, etiquetas recebidas, encerramento ao fim. Screenshots e diferenças intencionais em `design-qa.md`. 61 testes passaram. Assets e Zeitwerk verificados. Sem gravação de microfone ou popup bloqueante; aviso pessoal existente. Sem publicação em produção.

## Fila progressiva e atribuição (05/09)

Painel vazio sem caixas aninhadas. Lista com rolagem própria, lotes de 30 por cursor de criação/ID e botão de tentativa se o carregamento falhar. Filtros preservados. A atualização automática da lista pausa durante rolagem ou após expansão para preservar os cartões carregados; o botão Atualizar recarrega a posição atual da fila. A conversa continua consultando atualizações.

Select compartilhado em cada cartão apenas para Admin, com destinos limitados a Suporte ativo. Servidor rejeita atribuição manual por outros perfis (403) e destinos inválidos (422). Correção do responsável em encerrados mantém status e data de conclusão; auditoria registra a mudança. A atribuição automática existente ao responder permanece.

39 testes centrais e 24 da integração passaram (63). JavaScript validado, assets compilados nos dois aplicativos e web local reiniciada. Navegador comprovou 30 → 32 cartões únicos por rolagem e filtro subsequente com um resultado; estado vazio sem overflow em largura de 500px. Os 32 registros temporários de QA foram removidos, sem mensagens ou outbox, e o usuário de QA foi desativado após logout. Sem commit, push ou deploy.

## Sino da central (05/09)

Sino para Admin/Suporte com contador de chamados não resolvidos com mensagens públicas do cliente ainda não vistas por aquele colaborador. Lista até 30 novidades recentes, conta o total, consulta a cada 15 segundos em página visível. Clique registra cursor por colaborador/mensagem e abre `/admin/support/tickets?q=%23ID&selected=ID`, com cartão destacado e conversa no frame. Respostas posteriores voltam ao contador; leitura por outra pessoa não interfere. Notas internas e mensagens do suporte não geram aviso. A consulta não renova atividade humana para métricas de presença.

Migration central `20260905190000` aplicada somente nos bancos locais da central (development/test). 41 testes passaram; testes focados repetidos após ajuste do rótulo de resposta em contato ativo. Assets e Zeitwerk válidos. QA no navegador comprovou contador 1, lista, clique no #36, cartão selecionado, conversa carregada e contador zerado. Registro temporário e leitura removidos, logout e usuário QA desativado. Sem envio externo ou deploy. Aviso dentro da central, sem push com navegador fechado.

## Administrador como atendente (05/09)

Admin ativo incluído como destino válido na atribuição, com perfil junto ao nome. Atribuição manual continua exclusiva do Admin. Botão Assumir atendimento para Admin em chamado aberto que ainda não está atribuído a ele. Reutiliza atualização com auditoria existente. Resposta mantém autoria, responsável e transição para aguardando usuário.

Composer com formatação e upload compartilhado estilizado; em encerrados fica visível com fieldset desabilitado e aviso explícito. Validação de encerramento no servidor permanece. 42 testes da central e 24 do CRM passaram (66), incluindo atribuição/resposta pelo Admin e rejeição de resposta após resolução. Assets compilados, webs locais reiniciadas, navegador comprovou opções Admin e composer desabilitado em #1. QA saiu e foi desativado; nenhum atendimento real enviado. Sem deploy.

## Editor de imagem do NotificaLead (05/09)

Motor reaproveitado de `notificalead/app/javascript/lib/image_editor.js`, isolado em IIFE para Sprockets, sem modificar algoritmos de desenho/exportação. Integração baseada em `support_ticket_controller.js` (handleFileChange/editor/sendBlob) e layout fullscreen de `views/support/tickets/show.html.erb`. Ícones Bootstrap Icons 1.10.5 incorporados como SVG com licença em `support/BOOTSTRAP_ICONS_LICENSE.txt`; nenhum CDN no navegador.

Uma única imagem PNG/JPEG/WebP selecionada ou colada na resposta da central abre o editor automaticamente. Mesmas ferramentas: lápis, texto inline, seta, retângulo/elipse com preenchimento, recorte, desfoque, borracha, mover, cor, espessura, undo/redo e zoom. Fundo preto, ferramentas superiores, painel lateral, controles inferiores e mensagem opcional com envio verde. Vários arquivos/PDF/áudio seguem o anexo normal, como na seleção múltipla do NotificaLead. Cancelar preserva o arquivo original (ajuste deliberado para evitar perda). Envio exporta PNG e reutiliza rota/autorização/transporte existentes. Erro de envio mantém edição e legenda; fieldset encerrado não abre editor.

42 testes centrais e 24 do CRM passaram. JS validado e assets compilados nos dois aplicativos; webs locais reiniciadas. QA de navegador: abertura automática, 9 ferramentas, desenho, desfazer/refazer, falha 422 simulada mantendo edição/retry, envio real na central isolada e retorno ao mesmo frame. PNG persistido 800x600, 19.322 bytes, 841 pixels vermelhos da anotação; legenda preservada. Cancelar reteve arquivo. Conta #743/chamado #37 tinham destino loopback `127.0.0.1:9`, sem cliente externo; dados, eventos, entrega e anexo temporários removidos. Logout e usuário QA desativado. Sem deploy.

## Escrita proporcional na imagem (05/09)

Ajuste restrito à entrada de texto: textarea sem dimensões/padding excessivos, largura medida com a mesma fonte do canvas, altura pelas linhas e transform usando canvasToScreen (inclui redução e zoom). Fonte/família/peso iguais à exportação. Quebras de linha desenhadas no canvas em intervalos de 1,2 da fonte, também refletidas no hitbox. Resize recalcula posição/escala; listener removido ao fechar.

QA navegador em imagem 2400x1600: preview em escala 0,71625, aplicado com duas linhas e largura visual coerente (caixa 139px incluindo margem, glifos 133px). Após zoom: escala do canvas 0,85950 igual ao preview; altura medida 28,874px versus esperada 28,879px. Sem envio de mensagem ou alteração no chamado #38. Syntax JS/diff válidos; assets compilados e webs locais reiniciadas. Logout/desativação do QA ao final.

## Catálogo de etiquetas (05/09)

Referências: NotificaLead SupportLabel, Support::LabelsController, Support::TicketLabelsController e support_labels_manager_controller.js. Catálogo central compartilhado com nome, cor e descrição; Admin/Suporte criam, editam, excluem com confirmação e aplicam/removem por checkbox. Financeiro bloqueado. Cor #RRGGBB validada e contraste automático. Badges nos cartões, contador da aba e aplicação reativos. Mantido contrato de nomes em support_tickets.labels para compatibilidade HMAC com as contas; renomear/excluir propaga nomes em transação, com auditoria/revisão/outbox. Aplicação em encerrados bloqueada; alteração global de catálogo atualiza metadados sem mexer no estado/data/SLA. Limite total de 300 caracteres preservado.

Migration central 20260905200000 aplicada em development/test, importando nomes existentes com cor neutra editável. 45 testes centrais + 24 CRM passaram (69), incluindo permissões, cor inválida, duplicata, aplicação idempotente, renomeação, exclusão, auditoria e entrega. QA navegador criou etiqueta temporária, mudou cor laranja para azul e excluiu; Urgente existente preservada/aplicada no #38. Assets compilados; central local reiniciada. Usuário QA desativado após logout. Sem deploy.

## Preferências pessoais da fila (05/09)

Status, origem ativa/receptiva, Meus chamados e ordenação salvos automaticamente por PATCH autenticado no JSONB staffs.queue_preferences. Enum e quatro campos obrigatórios validados. Restauração ao entrar na fila sem query; links explícitos de notificações/indicadores preservados. Busca, datas e conta seguem temporários. Sem alteração de acesso ou sessão do colaborador. Migration central 20260905210000 nos bancos locais development/test. 47 testes centrais passaram, incluindo isolamento entre usuários, persistência, valores inválidos e financeiro bloqueado. JS/diff válidos; assets compilados e central local reiniciada. Sem deploy.
