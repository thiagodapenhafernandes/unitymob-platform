# Proteção contra saturação do Gateway

Preparado em 20/10/2026. Ainda não aplicado em produção. Alvo exclusivo:
`root@webhooks.unitymob.com.br`, `/opt/unitymob-whatsapp-gateway`.
Não executar retries nem reenviar eventos como parte deste procedimento.

## Evidência de 09/10/2026

- Host atual: 1 CPU, 961 MiB de RAM; Nginx na porta 443, Puma em
  `127.0.0.1:4010`. A documentação antiga citava Apache.
- Das 12h às 14h de Brasília, o access log registra 64.540 POSTs para
  `/webhooks/whatsapp`: 34.851 respostas 200, 28.673 respostas 499,
  771 respostas 401 e 245 respostas 500. Pico: 1.126 requisições/minuto
  às 12h33. Houve também 6.040 registros de rotas Meta no período.
- Das 12h30 às 13h20, o banco preserva 37.044 eventos de status WhatsApp.
  Destes, 34.645 pertencem ao phone_number_id `513696701833917` e 2.361 ao
  `649374078254590`, ambos sem rota. São 31.683 combinações distintas de
  mensagem/status/timestamp: não se pode tratar todos como duplicatas.
- 26.102 status indicam falha de envio na origem. Códigos brutos:
  131047 (14.579), 131049 (9.762), 131026 (1.678) e 130472 (83).
  Não foram consultadas as contas Meta para identificar o disparo originador.
- `/var/log/nginx/error.log.3.gz` contém 2.731 alertas de
  `768 worker_connections are not enough`, inclusive às 12h34min06s,
  cinco segundos antes do primeiro evento ZAP analisado.
- O espelho de desenvolvimento está ativo, com último sucesso registrado em
  05/10 e falhando atualmente com HTTP 401. O código tentava esse destino
  síncrono para cada evento, antes da entrega oficial, com timeout de abertura
  e leitura de 3 segundos cada. Logs atuais mostram respostas WhatsApp de
  aproximadamente 0,4 segundo, mas não há timing por etapa preservado do dia 09.

Diagnóstico: rajada de status de contas sem rota, com repetições, disputou o
mesmo processo e proxy usados pelo ZAP. O espelho síncrono com falha é um
amplificador verificável no código e estado atual; sua contribuição exata
em 09/10 não pode ser medida retrospectivamente. A saturação do Nginx é
comprovada; a ligação com cada EOF TLS é a hipótese mais forte, sem captura
individual das negociações TLS. Não atribuir o incidente a certificado vencido.

## Pacote preparado

1. Entrega oficial WhatsApp/Meta antes do espelho de desenvolvimento.
2. Espelho com uma tentativa simultânea por destino e pausa de 60 segundos
   após falha. Reserva atômica no banco existente, sem migration; tentativa
   abandonada pode ser retomada após 60 segundos. Eventos continuam sendo
   persistidos e encaminhados oficialmente. Cópias de desenvolvimento puladas
   durante pausa/concorrência não são reenviadas depois.
3. `nginx-capacity.patch`: `worker_connections` 768 → 4096,
   `worker_rlimit_nofile` 8192 e keepalive ocioso de 15 segundos. O hard limit
   atual do serviço é 524288; não precisa mudar systemd. Conexões incluem
   cliente e upstream, portanto 4096 não significa 4096 entregas simultâneas.
4. Log sem query string continua omitindo query string; acrescenta somente
   `$request_time`, `$upstream_response_time` e `$upstream_status`.

Prioridade: reduzir I/O desnecessário do espelho, depois ampliar a margem do
proxy e medir. Somente ampliar o Nginx poderia transferir a fila para o Puma.
Não foi alterado roteamento de contas, autenticação, persistência, deduplicação
ou retry oficial. O alto volume de registros de rotas é carga secundária a
investigar separadamente, sem mudar a sincronização de clientes neste pacote.

## Validação já feita

Banco exclusivamente local `unitymob_gateway_test`. Cenário com 100 eventos e
destino HTTP 401: 100 tentativas antes, 1 após a correção (99% menos tentativas
externas nesse cenário). Isso não é uma medição de throughput em produção.
Testes também cobrem timeout, retomada após pausa, modelo desatualizado e
entrega oficial/persistência durante falha do espelho.

O patch passou em `patch --dry-run -p1 -d /` no host alvo. A configuração
candidata passou no `nginx -t` em cópias temporárias, incluindo os certificados
e vhost atuais. Nada foi instalado/recarregado. Revalidar se houver drift.

## Aplicação futura, após autorização de publicação

Publicar **somente o Gateway** pelo fluxo de `docs/deploys.md`. Inventariar e
revisar o pacote antes de commit/push/deploy; não incluir outros WIPs. Publicar
a proteção do espelho antes de ampliar o proxy. Não executar a tarefa
`webhooks:retry_failed`.

Depois da publicação do Gateway, copiar o patch revisado para um arquivo
temporário no host e aplicar como root, após backup:

```sh
backup_dir=$(mktemp -d /root/unitymob-nginx-backup.XXXXXX)
cp -a /etc/nginx/nginx.conf "$backup_dir/nginx.conf"
cp -a /etc/nginx/conf.d/unitymob-no-query-log.conf "$backup_dir/unitymob-no-query-log.conf"
printf 'Backup: %s\n' "$backup_dir"
patch --dry-run -p1 -d / < /tmp/unitymob-nginx-capacity.patch
patch -p1 -d / < /tmp/unitymob-nginx-capacity.patch
nginx -t && systemctl reload nginx
```

Se `nginx -t` falhar, restaurar imediatamente os dois arquivos do backup e
validar novamente; não recarregar uma configuração inválida. Preservar o path
do backup e a revisão/imagem anterior do Gateway para rollback.

Validar somente com leituras e tráfego natural: `/up` com verificação TLS,
serviços, limite de arquivos dos novos workers, conexões e memória. Comparar
499/5xx, tempos de resposta e novos alertas de `worker_connections`. Conferir
eventos naturais por provedor e sua chegada ao CRM; `/up` sozinho não prova
entrega. Não gerar carga em produção nem postar payloads reais para teste.

Rollback do proxy: restaurar os dois arquivos do backup, executar `nginx -t`
e só então `systemctl reload nginx`. Rollback do aplicativo: imagem anterior,
sem migration. Voltar ao aplicativo anterior restaura o risco de espelho lento.

Limite: não há garantia contra qualquer pico futuro ou qualquer falha TLS.
Se o gargalo persistir após remover esse I/O e medir, planejar fila durável
para encaminhamento/espelho e isolamento de capacidade entre provedores;
não trocar por threads em memória que possam perder eventos no restart.
