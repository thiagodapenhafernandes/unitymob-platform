# Operacao da Salute

Arquivos versionados para os ajustes de memoria do host de producao. A
instalacao deve preservar os nomes atuais das units. Alteracoes de unit exigem
`systemctl daemon-reload`; alterar somente um script de timer nao exige reiniciar
Puma ou Solid Queue. Sempre executar o smoke test correspondente.

- `salute-memory-guard`: evita reciclar repetidamente workers Puma durante um
  pico legitimo. Exige duas amostras, memoria disponivel de no maximo 30% e
  cooldown de cinco minutos.
- `solid-queue-runtime-memory.conf`: limita o cache Rails de cada processo do
  Solid Queue a 16 MB, sem alterar filas, threads ou prioridade operacional.
- `solid-queue-media-autoscale`: sobe no maximo um worker extra e temporario
  apenas para a fila `media` quando o backlog fica alto/antigo, e derruba esse
  worker quando a fila normaliza ou quando ha pressao de memoria/swap.

Instalacao sugerida do autoscale:

```sh
sudo install -m 0755 ops/salute/solid-queue-media-autoscale /usr/local/sbin/solid-queue-media-autoscale
sudo tee /etc/systemd/system/solid-queue-media-autoscale.service >/dev/null <<'UNIT'
[Unit]
Description=Solid Queue media autoscale guard

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/solid-queue-media-autoscale
UNIT
sudo tee /etc/systemd/system/solid-queue-media-autoscale.timer >/dev/null <<'UNIT'
[Unit]
Description=Run Solid Queue media autoscale guard

[Timer]
OnBootSec=2min
OnUnitActiveSec=1min
AccuracySec=10s
Unit=solid-queue-media-autoscale.service

[Install]
WantedBy=timers.target
UNIT
sudo systemctl daemon-reload
sudo systemctl enable --now solid-queue-media-autoscale.timer
```

Thresholds padrao: liga com `READY_HIGH=1500` ou job mais antigo que
`OLDEST_HIGH_SECONDS=900`; desliga com `READY_LOW=300`; nao liga ou derruba
o extra se `MemAvailable < 700 MB` ou swap usado passar de `1200 MB`.

## Recuperacao de memoria sem fechar a porta HTTP

O guard preserva as amostras, thresholds e cooldowns existentes. Quando precisa
recuperar memoria de um Puma ativo com mais de um worker, recicla somente o
maior worker com TERM. Os demais continuam atendendo e o master pre-carregado
substitui o processo que terminou, sem reinicializar Rails para todo o cluster.
Na pressao agregada, essa acao respeita tanto o cooldown global quanto o do
worker; se o worker acabou de ser reciclado, aguarda em vez de reiniciar tudo.
Antes do sinal, confere que o PID ainda pertence ao mesmo master.

Sem mais de um worker, o Puma ativo usa `systemctl reload` (ExecReload/USR2),
que preserva o listener mas pode aumentar a latencia enquanto Rails carrega.
Nao usar stop/start para essa recuperacao: em 12/11/2026 isso deixou a porta
9292 ausente por 23 segundos e produziu 105 respostas 502. O USR2 seguinte
evitou os 502, mas trouxe espera de ate 21,8 s (8 s drenando requisicoes e
13 s carregando Rails). Puma inativo e Solid Queue conservam o restart.
Falha no sinal/reload nao cai silenciosamente em restart destrutivo.

A unit deve manter `ExecReload=/bin/kill -USR2 $MAINPID`. Esta regra e de
recuperacao da release em execucao; o deploy Mina continua iniciando o bundle
da release atual pelo procedimento de `docs/deploys.md`.

Validacao local: `python3 ops/salute/test_memory_guard.py` e
`bash -n ops/salute/salute-memory-guard`. Instalacao isolada do script:

```sh
sudo cp -a /usr/local/sbin/salute-memory-guard /usr/local/sbin/salute-memory-guard.backup-AAAAMMDDHHMMSS
sudo install -m 0755 ops/salute/salute-memory-guard /usr/local/sbin/salute-memory-guard
```

Nao executar o instalador completo de recovery para trocar apenas esse script.
A versao instalada e usada na proxima execucao do timer. Conferir healthchecks,
portas e log do guard. Para validar reciclagem sob requisicoes sem provocar
falta real de RAM, executar uma copia controlada com `STATE_DIR` temporario,
`REQUIRED_SAMPLES=1`, `THRESHOLD_PERCENT=100`, `MAX_PUMA_WORKER_RSS_KB` alto
(para exercitar a pressao agregada) e `QUEUE_UNIT` igual a `PUMA_UNIT`
(os dois consumos ficam iguais e o alvo continua sendo o Puma). Usar marcador
temporario para impedir a execucao concorrente dos
timers reais, e omitir `DEPLOY_MARKER` somente nessa copia controlada. Nao
alterar thresholds/state do guard instalado. Monitorar HTTP e latencia, exigir
mesmo master e substituicao de somente um worker; limpar marcador/state ao
termino. Rollback: reinstalar o backup do script, sem reiniciar a aplicacao.

Referencia do mecanismo: https://github.com/puma/puma/blob/v6.6.1/docs/restart.md
