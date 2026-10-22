# Publicação com piloto Meta desligado

Aplicação: gateway + Salute + Conexão BC. Não modificar a Meta nem executar retry/replay. Flags META_OAUTH_ENABLED e META_CENTRAL_CONNECT_ENABLED permanecem false; Conexão não recebe allowlist de ativação.

Patches de Nginx devem ser revisados contra a configuração atual, nunca aplicados cegamente. Gateway: nova location OAuth copia o proxy atual. Salute: nova location copia o proxy/proteções atuais; formato de acesso omite query e referer mantendo timing. Conexão: nova location copia @app incluindo limite existente, usando formato seguro específico. Domínios, certificados e callbacks existentes permanecem.

As novas locations usam error_log /dev/null crit para evitar vazamento de código/handoff nos erros de upstream; isso remove detalhe de erros de proxy apenas nessas rotas. Status e tempo continuam no access log, e a aplicação mantém logs sanitizados.

Antes de aplicar: backup privado dos arquivos originais, configuração efetiva e .env; registrar imagem/revisão anterior, dump do banco do gateway. nginx -t antes do reload; falha exige restauração do backup antes de prosseguir. Não incluir backups/segredos no Git.

Migration 20261022190000 é aditiva. Aplicar com a imagem nova em container avulso antes de recriar API e worker; ambos devem usar a mesma revisão. Preservar fila/destinos/tokens e todos os arquivos .env* do servidor. Preservar webhooks e flags já existentes. Rollback funcional por flags desligadas; rollback de imagem anterior não requer remover a tabela nova.

Testes: 120 exemplos completos gateway; 126 exemplos Rails focados/regressões; Zeitwerk e diff check. Imagem linux/amd64 validada isoladamente com rede interna e PostgreSQL efêmero: migration, boot, flag desativada, cancelamento, cookie Secure, resgate e replay. OAuth real e recebimento de lead natural dependem de ativação futura aprovada; saúde HTTP não comprova ingestão CRM.
