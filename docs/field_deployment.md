# Deploy da feature Field (check-in geolocalizado)

Este documento descreve o que precisa estar no servidor antes do primeiro deploy
que inclui as migrations da feature Field.

## 1. PostGIS no PostgreSQL

CentOS Stream 10 + PostgreSQL 16:

```bash
sudo dnf install -y epel-release
sudo dnf install -y postgresql16-contrib postgresql16-postgis-3 postgresql16-postgis-3-devel
sudo systemctl restart postgresql-16
```

Verificar que a extensão carrega:

```bash
sudo -u postgres psql salute_imoveis_v3_production -c "CREATE EXTENSION IF NOT EXISTS postgis; SELECT PostGIS_Version();"
```

Se der erro de biblioteca, reinstale `postgis-3` com a mesma versão major do
Postgres instalado.

## 2. MaxMind GeoLite2 (antifraude opcional)

1. Crie uma conta grátis em https://www.maxmind.com/en/geolite2/signup.
2. Gere uma License Key e exporte como variável de ambiente antes do deploy:

```bash
echo 'export MAXMIND_LICENSE_KEY="..."' >> ~/.bashrc
source ~/.bashrc
```

3. Baixe a base pela primeira vez (mina deploy pode rodar isso no post-deploy):

```bash
cd /var/www/salute_imoveis_v3/current
bundle exec rake geoip:download
bundle exec rake geoip:test   # smoke test
```

Se a base não for baixada, o sinal `ip_geo_mismatch` simplesmente não dispara —
os outros 4 sinais do antifraude continuam funcionando.

Agende download mensal via cron para manter a base atualizada:

```
0 5 1 * * cd /var/www/salute_imoveis_v3/current && bundle exec rake geoip:download
```

## 3. Ícones do PWA

Os ícones em `public/field-icons/icon-{192,512}.png` são genéricos
(pino de mapa azul). Peça ao designer versões definitivas:

- **icon-192.png** — 192×192, PNG com transparência.
- **icon-512.png** — 512×512.
- Ambos devem funcionar como "maskable" (conteúdo dentro do safe zone ≈80%).

## 4. Feature flag

Depois do deploy, ative a feature via:

- **Admin UI** (preferido): /admin/field_settings/edit → toggle "Check-in ativado".
- **Console**: `Setting.set("field_checkin_enabled", "true")`.

Com flag desligada, todas as rotas `/field/*` retornam 404 e o filtro em
`/admin/distribution_rules` fica inoperante (regras existentes continuam ok).

## 5. Solid Queue + recurring

A unit systemd `solid_queue_salute_imoveis_v3_production` roda o supervisor do
`solid_queue`, que automaticamente inicia:

- Dispatchers (de `config/queue.yml`)
- Workers (queues: dwv, checkin, *)
- **Scheduler** (lê `config/recurring.yml` — tarefas `field_auto_checkout_shift_end`
  a cada minuto e `field_stale_active_checkin` a cada 5min)

Verifique que está rodando:

```bash
sudo systemctl status solid_queue_salute_imoveis_v3_production
sudo journalctl -u solid_queue_salute_imoveis_v3_production -n 100 --no-pager
```

## 6. Checklist antes de ativar em produção

- [ ] PostGIS confirmado (`SELECT PostGIS_Version();`)
- [ ] Migrations rodaram (`20260420130000` até `20260420180000`)
- [ ] Pelo menos 1 loja cadastrada em /admin/stores com coordenadas + raio + turnos
- [ ] Corretores marcados com `field_agent_enabled = true` + `default_store`
- [ ] Solid Queue com scheduler rodando
- [ ] (Opcional) GeoLite2 baixada
- [ ] Teste manual: abrir /admin/sign_in em celular, depois /field, check-in com GPS
- [ ] Ativar flag `/admin/field_settings`
- [ ] Monitorar /admin/field/check_ins e /admin/field/audit_logs nas primeiras horas
