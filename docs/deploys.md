# Deploys de produção — Unitymob

Referência operacional atualizada em 05/09/2026. Todos os componentes estão no
repositório `thiagodapenhafernandes/unitymob-platform`, mas são aplicações e
publicações independentes.

## Site institucional

O site `public/site` é estático e publicado separadamente no Apache de `unitymob.com.br`. Procedimento completo, backup e rollback: [deploy-site.md](deploy-site.md). `mina all deploy` não atualiza esse DocumentRoot.

## Escolher o alvo

| Pedido ao Codex | Publicação | Comando / diretório |
| --- | --- | --- |
| `$fazer_deploy all` | Salute e Conexão, em sequência | Raiz: `rvm 3.2.3 do bundle exec mina all deploy` |
| `$fazer_deploy saluteimoveis` | Somente Salute | Raiz: `rvm 3.2.3 do bundle exec mina saluteimoveis deploy` |
| `$fazer_deploy conexaoimobiliaria` | Somente Conexão | Raiz: `rvm 3.2.3 do bundle exec mina conexaoimobiliaria deploy` |
| `$fazer_deploy central` | Somente Central de Atendimento | `central/`: `CENTRAL_HOST=167.99.239.17 CENTRAL_BRANCH=master rvm 3.2.3 do bundle exec mina deploy` |
| `$fazer_deploy gateway` | Somente Gateway | Procedimento Docker Compose abaixo |

`all` **não inclui Central nem Gateway**. `central` e `gateway` são alvos
interpretados pela skill, não stages do Mina da raiz. Não executar
`mina central deploy`, `mina gateway deploy` ou `mina production deploy` na raiz.
Um pedido para publicar todos os componentes exige listar explicitamente os
três grupos e sua sequência, considerando dependências da mudança.

## Git e preparação (todos os alvos)

1. Conferir branch, arquivos modificados, diff, remoto e commits pendentes.
2. Identificar o pacote autorizado; não incluir mudanças não relacionadas silenciosamente.
3. Rodar testes proporcionais, revisar migrations e compatibilidade com componentes não publicados.
4. Em `develop`, commitar o pacote nela. Fazer `git fetch --prune origin` e
   `git pull --ff-only origin develop`.
5. Trocar para `master`, executar `git pull --ff-only origin master`, promover
   com `git merge --no-ff develop` e enviar ambas as branches ao remoto.
6. Equalizar `develop` com `master`, sem force push. Conflitos exigem resolução antes do deploy.
7. Informar revisão, alvo, servidor, path e comando. Respeitar a autorização
   explícita já fornecida para o pacote/alvo, sem novo ciclo de confirmação.

Commit/push no monorepo não reinicia as outras aplicações. A publicação é
limitada ao alvo escolhido, mas inclui todo código que esse alvo carrega:
`support/` é compartilhado entre Central e clientes, e a Central também usa
assets compartilhados. Avaliar esses caminhos antes de afirmar que um alvo
está atualizado. Não copiar bancos, sessões, anexos ou segredos locais.

## Clientes: Mina multistage na raiz

| Stage | SSH | Diretório | Serviços systemd |
| --- | --- | --- | --- |
| saluteimoveis | `salute@143.110.138.67` | `/home/salute/deploy` | `puma_salute_imoveis_v3_production`, `solid_queue_salute_imoveis_v3_production` |
| conexaoimobiliaria | `conexao@app.conexaobc.com` | `/home/conexao/deploy` | `puma_conexao_imobiliaria_production`, `solid_queue_conexao_imobiliaria_production` |

Configuração: `config/deploy.rb` e `config/deploy/*.rb`; branch `master`.
Verificar `<diretório>/current/.mina_git_revision`, symlink `current`, serviços,
`https://saluteimoveis.com.br/up` ou `https://app.conexaobc.com/up`, além do fluxo alterado.

## Central: Mina próprio

```bash
cd central
CENTRAL_HOST=167.99.239.17 CENTRAL_BRANCH=master rvm 3.2.3 do bundle exec mina deploy
```

- Configuração: `central/config/deploy.rb`.
- SSH: `unitymob@167.99.239.17`; diretório: `/home/unitymob/central`.
- Aplicação Rails dentro da release: `current/central`.
- Serviços: `unitymob-central-web`, `unitymob-central-jobs`.
- Segredos e arquivos persistentes ficam em `shared`, conforme a configuração Mina.
- Mina instala dependências, executa migrations, Zeitwerk, compila assets e reinicia serviços.

Validar `current/.mina_git_revision`, release/symlink, ambos os serviços e
`https://admin.unitymob.com.br/up`. Conferir também login e o recurso alterado.
Não consumir acesso assistido real nem enviar respostas a chamados como smoke test
sem autorização para essas ações; preferir testes isolados e consultas de leitura.

## Gateway: Docker Compose, sem Mina

- SSH: `root@webhooks.unitymob.com.br` (IP observado: `159.223.105.26`).
- Diretório: `/opt/unitymob-whatsapp-gateway`.
- Serviço Compose: `whatsapp-gateway`; container: `unitymob-whatsapp-gateway`.
- Porta local: `127.0.0.1:4010`; proxy Apache; endpoint `/up` público.
- Fonte: `gateway/`; instruções adicionais em `gateway/README.md`.

A partir da raiz, após publicar o commit em `origin/master`, gerar um pacote
somente com arquivos versionados. Primeiro revisar o dry-run:

```bash
gateway_revision=$(git rev-parse origin/master)
gateway_package=$(mktemp -d /tmp/unitymob-gateway-deploy.XXXXXX)
git archive "$gateway_revision" gateway/ | tar -x -C "$gateway_package"
rsync -azn --delete --itemize-changes \
  --exclude '.env' --exclude '.deployed_revision' --exclude 'vendor/bundle' \
  --exclude 'log/' --exclude 'tmp/' \
  "$gateway_package/gateway/" root@webhooks.unitymob.com.br:/opt/unitymob-whatsapp-gateway/
```

Revisar exclusões e arquivos extras reais do servidor antes de remover `-n`:
`--delete` remove arquivos fora do pacote que não estejam protegidos. Preservar
qualquer configuração ou armazenamento exclusivo encontrado no servidor.
Registrar revisão/imagem anterior e garantir backup antes de migrations relevantes.
Então repetir o rsync sem `-n` e executar:

```bash
ssh root@webhooks.unitymob.com.br 'cd /opt/unitymob-whatsapp-gateway && docker compose build whatsapp-gateway && docker compose up -d whatsapp-gateway && docker compose exec -T whatsapp-gateway bundle exec rake db:migrate'
```

Esse procedimento reinicia o serviço antes das migrations: para mudanças de schema,
planejar compatibilidade e ordem de ativação; não executar cegamente em mudanças destrutivas.
Não enviar webhooks reais nem reprocessar eventos como teste de deploy.

Validar `https://webhooks.unitymob.com.br/up`, estado/reinícios do container,
logs de inicialização e comportamento afetado. Somente após sucesso, registrar:

```bash
printf '%s\n' "$gateway_revision" | ssh root@webhooks.unitymob.com.br 'cat > /opt/unitymob-whatsapp-gateway/.deployed_revision'
```

O marcador é uma convenção para próximas publicações, não prova de deploy antigo.
Se não existir, comparar checksums dos arquivos versionados e a imagem/container
em execução; não inferir a revisão pela data dos arquivos.

## Encerramento e falhas

- Reportar alvo, revisão, release (Mina) ou imagem/revisão (Gateway), testes e smoke checks.
- HTTP 200 em `/up` não comprova o recurso: verificar o comportamento específico.
- Se um alvo falhar, informar quais concluíram e quais ficaram pendentes.
- Não repetir migrations/alterações destrutivas automaticamente. Rollback deve considerar
  compatibilidade do banco e a revisão/imagem anterior, além do código.
