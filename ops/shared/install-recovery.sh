#!/usr/bin/env bash
# Executar como root no host correspondente, depois de copiar os arquivos de ops.
set -euo pipefail
case "${1:-}" in
  salute)
    app_dir=/home/salute/deploy
    host=saluteimoveis.com.br
    puma=puma_salute_imoveis_v3_production.service
    queue=solid_queue_salute_imoveis_v3_production.service
    cache=valkey.service
    database=postgresql.service
    ;;
  conexao)
    app_dir=/home/conexao/deploy
    host=conexaobc.com
    puma=puma_conexao_imobiliaria_production.service
    queue=solid_queue_conexao_imobiliaria_production.service
    cache=redis-server.service
    database=postgresql@17-main.service
    ;;
  *) echo 'Use salute ou conexao' >&2; exit 1 ;;
esac
ops_dir=$(cd "$(dirname "$0")/.." && pwd)
backup_dir="/var/backups/unitymob-recovery-$(date +%Y%m%d%H%M%S)"
mkdir -m 0700 -p "$backup_dir"
if [[ -f /usr/local/sbin/salute-memory-guard ]]; then
  cp -a /usr/local/sbin/salute-memory-guard "$backup_dir/"
fi
cp -a /etc/systemd/system "$backup_dir/"
install -m 0755 "$ops_dir/shared/service-recovery.py" /usr/local/sbin/unitymob-service-recovery
install -m 0755 "$ops_dir/salute/salute-memory-guard" /usr/local/sbin/salute-memory-guard
for unit in "$puma" "$queue" "$cache" "$database" nginx.service; do
  systemctl cat "$unit" >/dev/null
  mkdir -p "/etc/systemd/system/$unit.d"
  cat > "/etc/systemd/system/$unit.d/zzzz-recovery.conf" <<'UNIT'
[Unit]
StartLimitIntervalSec=60
StartLimitBurst=5
[Service]
Restart=on-failure
RestartSec=5s
UNIT
done
# Aplicações também voltam após encerramento inesperado com exit code zero.
for unit in "$puma" "$queue"; do
  printf '\nRestart=always\n' >> "/etc/systemd/system/$unit.d/zzzz-recovery.conf"
done
if [[ "$1" == conexao ]]; then
  printf '\nMemoryHigh=2200M\nMemoryMax=2600M\n' >> "/etc/systemd/system/$puma.d/zzzz-recovery.conf"
  printf '\nMemoryHigh=2400M\nMemoryMax=3200M\n' >> "/etc/systemd/system/$queue.d/zzzz-recovery.conf"
fi
cat > /etc/systemd/system/unitymob-service-recovery.service <<UNIT
[Unit]
Description=Unitymob bounded application recovery
After=network.target
[Service]
Type=oneshot
TimeoutStartSec=240
Environment=PUMA_UNIT=$puma
Environment=QUEUE_UNIT=$queue
Environment=PUBLIC_HOST=$host
Environment=STATE_DIR=/run/unitymob-service-recovery
Environment=DEPLOY_MARKER=$app_dir/shared/tmp/deploy-in-progress
ExecStart=/usr/local/sbin/unitymob-service-recovery
UNIT
cat > /etc/systemd/system/unitymob-service-recovery.timer <<'UNIT'
[Unit]
Description=Check Unitymob application recovery every minute
[Timer]
OnBootSec=2min
OnUnitActiveSec=1min
AccuracySec=10s
[Install]
WantedBy=timers.target
UNIT
# Reutiliza o guard existente, sem duplicar a lógica por cliente.
if [[ "$1" == conexao ]]; then
  cp /etc/systemd/system/unitymob-service-recovery.timer /etc/systemd/system/salute-memory-guard.timer
  cat > /etc/systemd/system/salute-memory-guard.service <<'UNIT'
[Unit]
Description=Unitymob memory pressure guard
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/salute-memory-guard
UNIT
fi
mkdir -p /etc/systemd/system/salute-memory-guard.service.d
cat > /etc/systemd/system/salute-memory-guard.service.d/recovery.conf <<UNIT
[Service]
Environment=PUMA_UNIT=$puma
Environment=QUEUE_UNIT=$queue
Environment=STATE_DIR=/run/unitymob-memory-guard
Environment=DEPLOY_MARKER=$app_dir/shared/tmp/deploy-in-progress
UNIT
systemctl daemon-reload
systemctl enable --now unitymob-service-recovery.timer salute-memory-guard.timer
systemctl start unitymob-service-recovery.service
printf 'Backup: %s\n' "$backup_dir"
