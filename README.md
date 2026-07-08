# README

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...
Após reiniciar, o Devise estará carregado e tudo funcionará! O painel admin estará acessível em:

URL: http://localhost:3000/admin
Login: admin@saluteimoveis.com.br
Senha: salute2024
123456

AUTOSSH_GATETIME=0 autossh -4 -M 0 -NT \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -o TCPKeepAlive=yes \
  -o ExitOnForwardFailure=yes \
  -R 3001:127.0.0.1:3001 \
  root@72.61.221.253
## Admin Sidebar: Mapa Antes/Depois

### Antes
- Dashboard
- Imóveis
- Construtoras
- Leads
- Regras
- Páginas SEO
- Configurações
  - Home Page
  - Layout
  - Rodapé
  - Contatos
  - SEO
  - Banners
  - Seções Home
  - Webhooks
  - Meta API
- Administração (admin)
  - Usuários
  - Perfis
  - Atributos Dinâmicos

### Depois (fluxo operacional)
- Dashboard
- Imóveis
- Construtoras
- Catálogos Dinâmicos
- Leads
- Distribuição de Leads
- Marketing e Conteúdo
  - Landing Pages
  - SEO Técnico
  - Banners
  - Seções da Home
  - Contato do Site
  - Aparência - Layout
  - Aparência - Rodapé
  - Home
- Integrações
  - Meta Leads
  - Webhooks
  - Vista Soft
- Administração (admin)
  - Usuários
  - Perfis

### Observações
- Não foram criadas novas rotas.
- O item Vista Soft reutiliza a listagem de imóveis com contexto de sincronização (`sort=last_sync_at&direction=desc`).
- A visibilidade de Administração continua condicionada a `current_admin_user.admin?`.

## Módulo de Proprietários e Spaces

### Novo módulo Admin: Proprietários
- Rota: `/admin/proprietors`
- O módulo substitui o acesso de construtoras no menu do admin.
- Cada proprietário possui `role`:
  - `owner`, `developer`, `builder`, `real_estate_agency`, `broker`, `partner`, `investor`
- Upload de imagem de perfil via ActiveStorage (`profile_image`).
- Imóveis (`habitations`) agora aceitam vínculo opcional por `proprietor_id`.

### Fluxo flexível no cadastro de imóvel
- Se `proprietor_id` vier preenchido, os campos legados de proprietário no imóvel são sincronizados automaticamente.
- Se `proprietor_id` vier vazio, mas os campos legados (nome/e-mail/celular/código vista) forem preenchidos, o sistema tenta criar/vincular um proprietário automaticamente.

### DigitalOcean Spaces (ActiveStorage)
- Serviço configurado em `config/storage.yml` como `do_spaces`.
- Ambientes `development` e `production` usam:
  - `ACTIVE_STORAGE_SERVICE` (se definido)
  - senão, `do_spaces` quando `VISTASOFT_SPACES_MIRROR_ENABLED=true`
  - fallback para `local`

### Rake dedicado para imagens de imóveis
- Task: `bundle exec rake images:sync_habitations_to_spaces`
- Variáveis opcionais:
  - `BATCH_SIZE=100` (tamanho do lote por ciclo)
  - `DRY_RUN=true`
  - `LOOP=true` (cadência contínua)
  - `SLEEP_SECONDS=3` (pausa entre ciclos)
  - `CURSOR_FILE=tmp/spaces_habitation_images_cursor.yml` (checkpoint)
  - `RESET_CURSOR=true` (reinicia do começo)
  - `START_ID=123` (força ponto inicial)
  - `ONLY_WITHOUT_ATTACHMENTS=false` (default)
  - `MAX_CYCLES=0` (0 = sem limite)
  - `STOP_WHEN_DONE=true` (encerra ao acabar)

Exemplo:

```bash
DRY_RUN=true BATCH_SIZE=50 bundle exec rake images:sync_habitations_to_spaces
```

Cadência para rodar em background sem travar:

```bash
LOOP=true BATCH_SIZE=50 SLEEP_SECONDS=2 bundle exec rake images:sync_habitations_to_spaces
```

Reprocesso de falhas registradas:

```bash
bundle exec rake images:retry_failed_habitations_to_spaces
```

### Pós-refresh do banco local: fotos de imóveis

Quando o banco local é atualizado com dados de produção, as fotos podem quebrar
se os registros `active_storage_blobs` apontarem para arquivos que não existem
no ambiente local. Rode o diagnóstico antes de abrir as telas:

```bash
bundle exec rake db_refresh:property_photo_health
```

Para aplicar o reparo pós-refresh:

```bash
APPLY=true bundle exec rake db_refresh:repair_property_photos
```

A task registra os serviços de storage dinâmicos, copia arquivos ausentes do
storage compartilhado de produção quando encontrar blobs `local` e reaproveita
`images:repair_missing_habitation_photo_blobs` para objetos que tenham origem
recuperável.
