# Deploy Conexao Imobiliaria

Este stage publica o `unitymob-platform` no servidor usado pela Conexao
Imobiliaria.

## Stage Mina

```bash
rvm 3.2.3 do bundle exec mina conexaoimobiliaria deploy
```

O stage fica em `config/deploy/conexaoimobiliaria.rb` e usa:

- host: `157.245.253.175`
- usuario SSH: `bc.imobiliariaconexao.com.br`
- path: `/home/bc.imobiliariaconexao.com.br/deploy`
- branch: `master`
- repo: `git@github.com:thiagodapenhafernandes/unitymob-platform.git`

## Estado verificado antes da migracao

Em 2026-08-04, o servidor ainda rodava o app legado
`conexao-imobiliaria` na release 231:

- Puma daemonizado direto, sem unit systemd da aplicacao.
- Porta interna `127.0.0.1:9292`.
- Ruby remoto do processo legado: `ruby-3.3.0@conexao-imobiliaria`.
- Sem Solid Queue no app legado.
- Sem `ruby-3.2.3` instalado no RVM do usuario de deploy.
- Crontab legado com `whenever` e `monitor_puma.sh`.

Nao copie esse modelo para o `unitymob-platform`. Este projeto usa Ruby 3.2.3,
Puma via systemd e Solid Queue via systemd.

## Pre-requisitos no servidor antes do primeiro deploy

Instalar Ruby compativel com o Gemfile:

```bash
rvm install 3.2.3
rvm 3.2.3@default do gem install bundler
```

Garantir os diretorios compartilhados que o deploy do `unitymob-platform`
espera:

```bash
mkdir -p /home/bc.imobiliariaconexao.com.br/deploy/shared/storage
mkdir -p /home/bc.imobiliariaconexao.com.br/deploy/shared/tmp/sockets
```

Em 2026-08-04 estes dois diretorios ainda nao existiam no layout legado.

Criar o environment file do Puma, preservando apenas variaveis nao secretas ou
apontando para o `.env` compartilhado quando necessario:

```bash
sudo install -o root -g root -m 0644 /dev/null /etc/sysconfig/puma_conexao_imobiliaria_production
```

Criar a unit do Puma:

```ini
[Unit]
Description=Puma HTTP Server for conexao-imobiliaria
After=network.target

[Service]
Type=simple
User=bc.imobiliariaconexao.com.br
WorkingDirectory=/home/bc.imobiliariaconexao.com.br
EnvironmentFile=/etc/sysconfig/puma_conexao_imobiliaria_production
ExecStart=/usr/local/rvm/bin/rvm-shell 3.2.3@default -c "cd /home/bc.imobiliariaconexao.com.br/deploy/current && bundle exec puma -C config/puma.rb"
Restart=always
KillMode=process

[Install]
WantedBy=multi-user.target
```

Criar a unit do Solid Queue:

```ini
[Unit]
Description=Solid Queue for conexao-imobiliaria
After=network.target

[Service]
Type=simple
User=bc.imobiliariaconexao.com.br
WorkingDirectory=/home/bc.imobiliariaconexao.com.br
Environment=RAILS_ENV=production
ExecStart=/usr/local/rvm/bin/rvm-shell 3.2.3@default -c "cd /home/bc.imobiliariaconexao.com.br/deploy/current && bundle exec bin/jobs start"
Restart=always
RestartSec=5
KillMode=process

[Install]
WantedBy=multi-user.target
```

Habilitar os services:

```bash
sudo systemctl daemon-reload
sudo systemctl enable puma_conexao_imobiliaria_production
sudo systemctl enable solid_queue_conexao_imobiliaria_production
```

O deploy reinicia estes nomes de service:

- `puma_conexao_imobiliaria_production`
- `solid_queue_conexao_imobiliaria_production`

Se eles nao existirem, o Mina deve falhar no restart em vez de publicar um app
sem worker de fila.

Antes do primeiro deploy real, revisar o bare repo em
`/home/bc.imobiliariaconexao.com.br/deploy/scm`: ele foi criado pelo app legado
e apontava para `conexao-imobiliaria`. O stage novo busca diretamente o repo
`unitymob-platform`, mas o corte deve tratar esse deploy como substituicao do
app legado no mesmo path.
