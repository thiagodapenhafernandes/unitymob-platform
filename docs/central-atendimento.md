# Central de atendimento Unitymob

A central em `central/` é uma aplicação Rails independente. O engine local `support/` é usado pela central e pelo CRM: modelos, questionário, conversa, anexos, API e entregas têm uma implementação compartilhada. O gateway Sinatra em `gateway/` e seu deploy não participam deste fluxo.

## Uso e limites

- Central: `admin.unitymob.com.br`. Login por senha e segunda etapa obrigatória (TOTP ou código por e-mail). Admin gerencia contas/equipe; suporte atende todas as contas; financeiro tem apenas a área reservada.
- Conta: `/admin/support/tickets`. Proprietário vê todos da própria conta; todos os usuários autenticados abrem e veem os próprios, inclusive durante impersonação. O proprietário consulta a conversa, mas não escreve fingindo ser o solicitante.
- Questionário igual ao NotificaLead: ação tentada, módulo, esperado, ocorrido e impacto. O navegador preserva textos por até 24 horas na aba/sessão; anexos precisam ser selecionados novamente. Nenhum texto do chamado entra em URL.
- Respostas do suporte passam para aguardando usuário; resposta do usuário retoma atendimento. Resolvidos são imutáveis e podem originar outro chamado vinculado. Notas internas nunca são serializadas.
- A conversa atualiza a cada 15 segundos enquanto a página está visível e sem edição em curso. O menu do usuário abre o chamado em modal, sem sair da tela. Um lembrete no canto inferior direito acompanha atendimento, resposta e encerramento, apenas para o solicitante; ao fechar, reaparece em 30 minutos para respostas ou 4 horas para espera, ou antes se houver novidade; push reutiliza a configuração Web Push/FCM da conta.
- Anexos: até 5 por mensagem, JPG/PNG/WebP/PDF, 10 MB cada, MIME conferido pelo conteúdo, armazenamento privado e download autorizado pelo chamado.
- Acesso assistido: botão no chamado, operador identificado, credencial de uso único válida por 60 segundos, sessão de 30 minutos. Sem consentimento nesta versão, conforme decisão do produto; comentários `ponytail:` marcam a futura inclusão.
- A política `Support::AssistedPolicy` enumera controller/ação. Permissões e escopos existentes do usuário continuam sendo aplicados. São permitidos envios, campanhas, propostas e automações. Segurança, alteração de corretores/perfis, integrações, contratos B2B/financeiro, exclusões e exportações em massa ficam bloqueados. Novas ações ficam bloqueadas até classificação explícita.
- Desativar/alterar colaborador enfileira revogação dos acessos nas contas. Desativação/reativação de conta é versionada para resistir a eventos atrasados. Sem conectividade, a sessão local continua limitada aos 30 minutos originais.
- Registros de acesso preservam operador, usuário representado, conta, chamado, ação, registro, request ID e resposta HTTP; não guardam senhas, tokens ou texto sensível de formulários.

## Contrato entre aplicações

`POST /internal/support/v1/events` recebe JSON com `event_id` UUID, `kind`, `ticket` e, quando houver, `message`. CRM envia `create`/`message`; central envia `snapshot`. Cada mensagem tem UUID próprio. O servidor deriva lado e autor de mensagens do cliente, não aceita prioridade/estado/responsável arbitrários. Snapshot contém apenas a mensagem pública relacionada à alteração, não todo o histórico/anexos repetidos.

Headers: `X-Support-Account`, `X-Support-Timestamp` (epoch em segundos) e `X-Support-Signature`, HMAC-SHA256 de `timestamp.corpo_bruto`, com segredo exclusivo da conta. Janela de 5 minutos; HTTPS obrigatório; rotacionar chaves por operação controlada nos dois lados. Sem fallback para tokens do gateway.

Outbox e recibo são persistidos no banco. Transação recebe/aplica/registra UUID; repetição não cria novos registros. Revisão monotônica atualiza estado sem perder mensagens antigas. Entregas de um mesmo chamado respeitam ordem. Falhas são repetidas com backoff até 15 minutos. A recorrência por minuto recupera falhas de enqueue e de processo. A fila usa `default`, já consumida pelo Solid Queue do CRM. `SUPPORT_QUEUE` permite um worker de suporte isolado no desenvolvimento, sem consumir campanhas ou outras tarefas do banco local.

`POST /internal/support/v1/access` usa a mesma autenticação e recebe chamado/operador. O CRM resolve o solicitante local, impede usuário global e emite credencial temporária. `POST /support/access` consome a credencial com troca de sessão; não se baseia em e-mail ou IDs globais de usuários. A exceção CSRF desse POST é protegida pela credencial secreta de uso único; os demais formulários continuam com CSRF.

## Preparação local e testes

Use RVM 3.2.3. O CRM precisa do `config/database.yml` local normalmente ignorado pelo Git. Use banco isolado para os testes desta feature, sem migrar bancos de outras tarefas.

```sh
DB_NAME_TEST=unitymob_support_client_test RAILS_ENV=test bundle exec rails db:create db:schema:load db:migrate
DB_NAME_TEST=unitymob_support_client_test bundle exec rspec spec/requests/support spec/services/support
```

Na pasta `central/`:

```sh
bundle install
RAILS_ENV=test DB_PORT=5433 bundle exec rails db:create db:migrate
DB_PORT=5433 bundle exec rspec spec
RAILS_ENV=test DB_PORT=5433 bundle exec rails zeitwerk:check assets:precompile
```

## Provisionamento e ativação

Publicação requer aprovação específica do pacote e alvo. Não houve provisionamento nem deploy durante a implementação.

1. Preparar servidor próprio com Ruby 3.2.3/RVM, PostgreSQL, Nginx, usuário `unitymob` e acesso de leitura ao repositório. Referência inicial: 2 vCPU/4 GB de memória, ajustando por métricas.
2. Criar banco/usuário exclusivos; preencher `central/.env.example` em `/home/unitymob/central/shared/central/.env` com permissões 0600. Gerar `SECRET_KEY_BASE` e chaves Rails de criptografia independentes. Nunca reutilizar credenciais do gateway.
3. Criar armazenamento privado para suporte; configurar variáveis `SUPPORT_STORAGE_*` na central e nos CRMs. Usar buckets separados por aplicação. Nunca apontar para o CDN público dos imóveis. Backup diário do PostgreSQL e política de retenção/versionamento dos anexos precisam ser ativados e restauração verificada antes do piloto.
4. Apontar DNS `admin.unitymob.com.br` ao novo IP, emitir TLS e instalar os modelos em `central/ops/`, ajustando apenas paths reais do RVM. Liberar somente 80/443 publicamente; PostgreSQL e Puma ficam privados. Nos CRMs, permitir corpo de até 72 MB nos endpoints internos de suporte.
5. Na pasta `central/`, publicar com `CENTRAL_HOST=<host> CENTRAL_BRANCH=<branch_aprovada> bundle exec mina deploy`. Verificar revisão, symlink, serviços, worker/recorrência e `/up`. Este comando não é um stage de `mina all deploy`.
6. Criar o primeiro admin com `SUPPORT_ADMIN_NAME` e `SUPPORT_ADMIN_EMAIL` no ambiente e `bundle exec rails support:bootstrap`. Entregar o link pessoalmente; senha/TOTP são configurados no link de 1 hora. Recuperação é um novo link emitido por outro administrador. O perfil Admin também acessa a área Financeiro, ainda reservada.
7. Provisionar a identidade do servidor no ambiente do CRM: `SUPPORT_INSTANCE_ID` (único e estável por instalação/ambiente), `SUPPORT_INSTANCE_SECRET` (aleatório, ao menos 32 caracteres) e `SUPPORT_CENTRAL_URL`. Na central, `SUPPORT_TRUSTED_INSTANCES` é um JSON com `{ "id-do-servidor": { "secret": "segredo-provisionado", "endpoint": "https://dominio-do-crm" } }`. Essa configuração pertence ao provisionamento do servidor, nunca ao cadastro de cada conta ou à interface do usuário. O endpoint é exclusivo da infraestrutura confiável, não é aceito do payload de cadastro.
8. A criação de uma conta enfileira seu registro; a recorrência por minuto descobre automaticamente contas existentes e recupera falhas de fila/conectividade. As credenciais de cada conta são distintas, derivadas por HMAC da identidade servidor/tenant; IDs locais iguais em servidores diferentes não colidem. Repetições são idempotentes e nunca reativam uma conta desativada pelo administrador. `support:connect` agora apenas antecipa essa reconciliação automática; não exige parâmetros por conta.
9. O módulo é acessível a todos os usuários autenticados da conta, sem permissão adicional por perfil. O proprietário mantém a visão dos chamados da própria conta. Realizar piloto na Salute: abrir chamado com anexo pelo menu do usuário, responder na central, conferir o lembrete/push, interromper conectividade em ambiente controlado e confirmar recuperação, testar acesso assistido e expiração. Repetir na Conexão após aceite.

A central só confia em servidores provisionados: conta nova não precisa de ação humana; um servidor desconhecido não pode cadastrar contas. Não copiar a identidade de produção para bancos restaurados de desenvolvimento. Ao mover um servidor, preservar identidade/chave e atualizar seu endpoint confiável. Credenciais previamente cadastradas permanecem válidas; a reconciliação não troca a identidade de chamados existentes.

## Rollback e observação

Aplicar migrations antes de ativar contas. Para interromper o piloto, desativar a configuração de suporte da conta; preservar tabelas, mensagens e outbox. Não executar rollback destrutivo das tabelas com chamados reais. Reverter código somente mantendo acesso às entregas pendentes e sem interromper o gateway.

Monitorar entregas pendentes/idade da mais antiga, erros de workers, latência HTTP e falhas de autenticação. Health HTTP indica processo vivo; a validação operacional exige também entrega completa e worker ativo. Mudanças anteriores em `develop` permanecem fora deste pacote.

## Login por e-mail e Umbler

O administrador local `contato@unitymob.com.br` usa `verification_method=email`, com a senha solicitada armazenada somente como hash. Credenciais SMTP e chaves de criptografia ficam no `.env.development` ignorado pelo Git, com modo 0600. Esse usuário foi criado no banco `unitymob_central_development`, não em produção nem no banco de testes.

SMTP: `smtp.umbler.com:587`, autenticação normal, STARTTLS obrigatório com validação de certificado. Fonte: [configuração oficial da Umbler](https://help.umbler.com/hc/pt-br/articles/204936355-Acessando-e-configurando-os-e-mails-manualmente). A autenticação SMTP foi validada; testes automatizados usam transporte de testes e não enviam e-mails reais.

Fluxo: senha correta → envio ao e-mail cadastrado → tela de código → sessão completa. Código de seis dígitos, válido por 10 minutos, uma utilização, no máximo cinco tentativas e intervalo de um minuto entre envios. O desafio é vinculado à sessão que apresentou a senha; não há sessão autenticada antes de acertar o código. Não registrar corpo de e-mails de autenticação nem colocar códigos em argumentos de jobs. Falha SMTP mantém o acesso fechado e permite nova tentativa.

Credenciais locais não fazem parte do pacote de deploy. Em produção será necessário cadastrar o administrador e configurar as variáveis SMTP no servidor aprovado.

## Execução local com o túnel

A feature roda em `unitymob-central-atendimento`, branch `codex/central-atendimento`. O banco local existente é `unitymob_platform_dual_tenant_local`; somente as migrations aditivas de suporte foram aplicadas nele. `https://dev.unitymob.com.br` continua chegando à porta 3001, agora servida pelo worktree da feature. A central local usa a porta 4020. O checkout `unitymob-platform/develop` e seu WIP foram preservados.

Os `.env.development` ignorados pelo Git contêm a identidade `unitymob-local` e as credenciais da infraestrutura. No desenvolvimento, a origem HTTP é aceita apenas para loopback (`127.0.0.1`/`localhost`); produção continua exigindo HTTPS.

O worker do CRM usa `SUPPORT_QUEUE=support_local`, com os arquivos de configuração locais `/tmp/unitymob-support-queue.yml` e `/tmp/unitymob-support-recurring.yml`, para processar somente suporte. Inicialização: `SOLID_QUEUE_CONFIG=/tmp/unitymob-support-queue.yml SOLID_QUEUE_RECURRING_SCHEDULE=/tmp/unitymob-support-recurring.yml rvm 3.2.3 do bundle exec ruby bin/jobs`. Na central, usar `rvm 3.2.3 do bundle exec ruby bin/jobs --mode=async` no macOS; o modo async evita o crash nativo do driver PostgreSQL após fork observado neste ambiente. O serviço Linux mantém o comando padrão `bin/jobs`.

### Medição de atendimento e presença

Admin acessa `/sla`: primeira resposta média/P90, resolução média, espera pelo usuário, responsáveis, atividade por perfil e sessões. Datas selecionam o recebimento dos chamados na central. Conta/colaborador filtram atendimentos; perfil filtra equipe e sessões. Presença é global.

Metas por prioridade em minutos corridos valem para novos tickets ou mudanças de prioridade, preservando o alvo histórico. Não há calendário de expediente nesta versão. Dados anteriores à instrumentação ficam sem medição.

Uma aba visível confirma conexão a cada 30s; após 75s sem confirmação, deixa de aparecer online. Tempo soma somente intervalos confirmados, sem duplicar sessões. Ausência de heartbeat não é logout. Login, saída explícita, expiração e revogação são distintos. Atividade de requisição não equivale a tempo trabalhado.
