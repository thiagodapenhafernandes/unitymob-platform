# Piloto central Meta no gateway — revisão antes da publicação

Atualização: 22/10/2026. Implementação local, não publicada. Piloto operacional somente Salute/tenant1; código compartilhado preparado para Salute e Conexão, flags desativadas por padrão. Não houve mudança na Meta, produção, tokens, domínios ou webhooks nesta etapa.

## Fluxo implementado e reaproveitamento

1. Usuário autenticado e com permissão de Integrações inicia um POST no CRM.
2. O CRM registra uma tentativa no gateway, autenticada por segredo exclusivo da instância e vinculada a tenant, usuário e nonce.
3. O navegador recebe um ticket opaco; o gateway abre o OAuth da Meta e valida o retorno por state e sessão do navegador.
4. O gateway troca o código por credencial no servidor, guarda o resultado cifrado e devolve ao endereço canônico do CRM somente um handoff opaco.
5. O CRM resgata esse handoff por HTTPS autenticado, uma única vez, com o mesmo tenant, usuário e nonce. Confere identidade, permissões e ativos antes de substituir qualquer token.
6. O CRM reutiliza ConnectionCompletion e MetaSyncJob: seleção de ativos, sincronização e inscrições continuam nos caminhos existentes. O callback legado usa a mesma conclusão, sem as novas exigências do piloto.

Do TikTok são reaproveitados o gateway existente, HTTPS, sessão, registro de tentativa com validade de dez minutos e retorno ao CRM. São usados também o limitador e a limpeza já existentes. As rotas, tabela de state e callbacks do TikTok não foram modificados. A Meta tem armazenamento próprio porque troca o código no gateway e entrega a credencial por resgate interno; não reutiliza o registro de outro provedor nem envia token na URL.

## Proteções e compatibilidade

- Flags desligadas por padrão e allowlist explícita por tenant; piloto só tenant1.
- Permissão manage/integracoes, sessão autenticada e origem canônica obrigatórias no CRM.
- Gateway autentica cada instância e restringe os tenants autorizados.
- Ticket, state, nonce e handoff armazenados por hash; credencial cifrada AES-256-GCM e apagada no consumo. Expiração em dez minutos; limpeza horária discovery:cleanup.
- Cookie do gateway reutiliza HttpOnly, SameSite=Lax e Secure em produção.
- Resgate único testado inclusive com duas requisições concorrentes.
- URLs de retorno sem token; query strings filtradas, Cache-Control:no-store e Referrer-Policy:no-referrer. Antes de publicar, conferir também Nginx sem query strings nos dois servidores.
- Mesmo usuário Facebook, mesmo app e preservação de todos os escopos concedidos anteriormente. Debug do token final (inclusive após troca por longo prazo) confere os IDs dos ativos em granular_scopes; perda/restrição não substitui o token atual.
- Falha de consulta, resposta inválida, cancelamento, expiração ou falha de enfileiramento não autorizam substituição silenciosa da integração.
- Uma reconexão concorrente é detectada sob lock; o piloto não sobrescreve a credencial que outro fluxo acabou de atualizar.
- Botão e POST legados mantidos. Testes comprovam botão piloto ausente quando desligado e presença do login legado em ambos os estados.
- Não altera endpoints de WhatsApp/Meta/TikTok, não reenfileira históricos e não executa CAPI no fluxo OAuth. MetaSyncJob continua usando a sincronização de ativos existente; cadastro de rotas Meta não reprocessa eventos históricos.

O piloto solicita os escopos Ads/Lead Ads atuais: email (opcional), pages_show_list, pages_read_engagement, pages_manage_ads, pages_manage_metadata, ads_management, leads_retrieval e business_management. Uma integração que já exija Instagram e não conceda os mesmos acessos/ativos será recusada com a credencial anterior preservada. Não acrescentar escopos ou trocar tokens para contornar essa trava.

## Configuração preparada, não aplicada

Gateway, além de META_APP_SECRET, SESSION_SECRET e DISCOVERY_SECRET existentes:

```dotenv
META_OAUTH_ENABLED=false
META_OAUTH_APP_ID=1766223014200910
META_OAUTH_PUBLIC_ORIGIN=https://webhooks.unitymob.com.br
META_OAUTH_ENCRYPTION_KEY=<64 caracteres hex aleatórios exclusivos>
META_OAUTH_INSTANCES={"salute":{"enabled":true,"origin":"https://saluteimoveis.com.br","tenant_ids":["1"],"token":"<segredo exclusivo de pelo menos 32 caracteres>"}}
```

Salute:

```dotenv
META_CENTRAL_CONNECT_ENABLED=false
META_CENTRAL_CONNECT_TENANT_IDS=1
META_CENTRAL_CONNECT_URL=https://webhooks.unitymob.com.br
META_CENTRAL_CONNECT_INSTANCE=salute
META_CENTRAL_CONNECT_TOKEN=<mesmo segredo exclusivo da instância>
```

APP_HOST deve ser a origem HTTPS canônica da Salute. FACEBOOK_APP_ID continua1766223014200910; FACEBOOK_APP_SECRET permite conferir os ativos via debug_token. Não reutilizar tokens globais de webhook. Conexão BC permanece com o piloto desligado.

Callback futuro a acrescentar, somente após aprovação explícita, preservando os atuais:
`https://webhooks.unitymob.com.br/oauth/meta/callback`.

## Pacote para publicação futura

Gateway: .env.example, Rakefile, app/gateway_app.rb, app/meta_oauth_routes.rb, app/models/meta_oauth_attempt.rb, app/services/meta_oauth.rb, migration20261022190000 e specs correspondentes.

CRM compartilhado: Admin::MetaConnectionsController, Meta::CentralConnectionClient, Meta::ConnectionCompletion, integração da conclusão no callback legado, Facebook::PermissionCheck (consulta paginada/status e debug_token), rota meta_connection, filtro de parâmetros e partial do botão reutilizado no onboarding e nas permissões. Specs cobrem os caminhos novos e legados.

Ficam fora deste pacote os WIPs de db/structure.sql, yarn.lock, package-lock.json, outputs, caches, testes do perfil de analista e demais documentos da análise Meta. Não commitar o checkout inteiro por inferência.

## Publicação proposta — não executada

1. Revisar pacote e exclusões; conferir a imagem Docker em ambiente isolado antes de produção.
2. Backup e migration do gateway (20261022190000), publicar gateway com flag desligada e validar saúde, fila e os webhooks atuais. Não executar tarefas de retry.
3. Publicar o código compartilhado nos dois CRMs, com flags desligadas; conferir revisões, serviços, login, integração legada, Instagram e webhooks. `mina all deploy` inclui somente Salute e Conexão; gateway é independente.
4. Só em etapa explicitamente aprovada, acrescentar o callback na Meta e habilitar o piloto na Salute. Não alterar os callbacks existentes nem habilitar na Conexão.
5. Realizar OAuth real com ativos autorizados, conferindo permissões e IDs antes/depois, seleção preservada, cancelamento e sincronização. Confirmar depois um lead natural por ID no CRM, sem reenviar históricos.
6. CAPI é validação separada: aprovação do Marketing API Access Tier e acesso ao dataset continuam necessários; centralizar o OAuth não corrige sozinho o erro270.

Rollback funcional: desligar ambas as flags; botão e conexão legados continuam ativos. Não remover a tabela com processos novos em execução. Nenhum rollback de token automático nem revogação de autorização externa.

## Validação executada

- Gateway:120 exemplos, suíte completa, PostgreSQL dedicado unitymob_meta_pilot_test. Inclui OAuth Meta, resgate concorrente, isolamento, expiração, cancelamento, limites e regressões TikTok/WhatsApp/Lead Ads/delivery. Nesta retomada foram adicionados casos de handoff expirado, ciphertext corrompido e resgate por outra instância autorizada.
- Rails:126 exemplos aprovados nesta retomada (91 do piloto/legado/permissões/sincronização e 35 de regressões TikTok/Instagram). Inclui a melhoria de formulários já publicada, sem misturá-la ao pacote pendente do piloto.
- Migration gateway:down/up comprovado somente no banco dedicado; coluna nonce_digest e índices restaurados.
- Zeitwerk:aprovado. git diff --check:aprovado.
- Boot HTTP local com RACK_ENV=production, segredo de sessão efêmero e banco dedicado: /up respondeu200; /oauth/meta/start respondeu404 com piloto desligado. Processo encerrado após o smoke. Isso valida boot nativo, não substitui build/container.
- Docker/container:aprovado em VM Colima local dedicada, imagem linux/amd64 (arquitetura do destino), sha256:f039fe2980d511ce983ab96db36061a469becd3bd5c1f32b873d57bde56fef3f. Banco PostgreSQL efêmero, rede interna sem saída e sem portas publicadas, credenciais sintéticas. Boot padrão, migration, flag desligada, autorização/cookie Secure via proxy HTTPS simulado, cancelamento, resgate e replay aprovados. Sem .env real na imagem; containers/rede removidos. Evidências e roteiro em outputs/meta-pilot-predeploy/.
- OAuth real e smoke em produção:pendentes de publicação/configuração aprovadas. Chamadas ao provedor nos testes são simuladas; não confundir com autorização real da Meta.

### Pendências antes de publicar/ativar

1. Teste Docker isolado concluído. Antes do deploy, fechar commit/pacote exclusivo e relacionar a revisão à imagem; o build testado é do contexto local com manifesto de hashes, não de commit fechado.
2. Conferência Nginx realizada somente em leitura: gateway já omite queries no access log; Salute registra $request/$http_referer. Error log padrão pode expor query em falha de upstream, reproduzido isoladamente. Patches locais preparados para acesso sem query/referer e error log restrito nas rotas novas. Exigem revisão, backup e nginx -t no destino antes de eventual aplicação; nada foi alterado em produção.
3. Preparar os segredos exclusivos e conferir origens/allowlists no ambiente de destino, mantendo flags desligadas. Configuração não aplicada nesta retomada.
4. Após aprovação explícita para ativar, acrescentar somente o callback novo na Meta e validar OAuth real na Salute, preservando identidade, permissões, ativos e seleção; conferir cancelamento e rollback por flags. A aprovação da análise Meta não equivale ao teste desse OAuth.
5. Confirmar ingestão de um lead natural após ativação, sem reenvio histórico. CAPI/erro270 segue separado e depende de acesso ao dataset e Marketing API Access Tier.

## Contexto da análise Meta

O próprio usuário enviou em22/10/2026 a submissão2059260608230481 do app1766223014200910, com Marketing API Access Tier e os três pedidos Instagram. Acompanhamento separado já configurado. Instagram real da Conexão BC foi demonstrado com @tpenh; esse teste não é do piloto central nem confirmação de acesso avançado. Nada na implementação local modifica a submissão em andamento.
