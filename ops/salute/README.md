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
recuperar memoria do Puma ativo, executa `systemctl reload` (ExecReload/USR2),
que preserva o listener durante o hot restart. Nao usar stop/start para essa
recuperacao: em 12/11/2026 isso deixou a porta 9292 ausente por 23 segundos e
produziu 105 respostas 502. Puma inativo e Solid Queue conservam o restart.
Um reload que falha nao cai silenciosamente em restart destrutivo.

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
portas e log do guard; para validar USR2 sob requisicoes, monitorar status HTTP e
latencia antes, durante e depois de um reload controlado. Rollback: reinstalar
o backup do script, sem reiniciar a aplicacao.

Referencia do mecanismo: https://github.com/puma/puma/blob/v6.6.1/docs/restart.md
