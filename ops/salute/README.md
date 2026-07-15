# Operacao da Salute

Arquivos versionados para os ajustes de memoria do host de producao. A
instalacao deve preservar os nomes atuais das units e sempre ser seguida por
`systemctl daemon-reload`, reinicio controlado do servico afetado e smoke test.

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
