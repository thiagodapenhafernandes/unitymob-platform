---
name: fazer_deploy
description: Atalho para deploy seguro ou abertura de PR com confirmação obrigatória e resumo contextual, suportando NotificaLead production/cyrela/gateway/proxy-global/all, m2ti, homologação, PR e guardrails por branch.
---

# Atalho: Fazer Deploy

Use este atalho quando o usuario pedir:
- `@fazer_deploy`
- `$fazer_deploy`
- `$fazer-deploy`
- `$fazer_pr`
- `$fazer-pr`
- `fazer deploy`
- `fazer pr`
- `fazer deploy production`
- `fazer deploy produção`
- `fazer deploy gateway`
- `fazer deploy proxy-global`
- `fazer deploy cyrela`
- `fazer deploy all`
- `fazer deploy m2ti`
- `fazer deploy <stage>`
- `mina production deploy`
- `mina m2ti deploy`
- `mina <stage> deploy`

## Unitymob: clientes, Central e Gateway

No repositório `unitymob-platform`, ler `docs/deploys.md` antes de resolver o alvo.
Esta seção tem prioridade sobre o fluxo genérico e os alvos de outros projetos.

- `all`: somente os clientes Salute e Conexão, Mina multistage da raiz.
- `central`: commit do pacote na develop, promoção/push para master e Mina
  dentro de `central/`: `CENTRAL_HOST=167.99.239.17 CENTRAL_BRANCH=master rvm 3.2.3 do bundle exec mina deploy`.
- `gateway`: mesmo preparo Git, mas publicar apenas `gateway/` a partir do commit
  com rsync e Docker Compose, seguindo o dry-run e validações de `docs/deploys.md`.
- `saluteimoveis` / `conexaoimobiliaria`: somente o cliente indicado.

`central` e `gateway` não são stages Mina da raiz. Não executar `mina central`,
`mina gateway` ou `mina production` neste projeto. Não ampliar `all` para incluir
os outros componentes. Considerar código compartilhado ao avaliar deploy pendente.
Antes da mutação, apresentar pacote, revisão, destino e comando e aplicar a
seleção de escopo abaixo. Essa seleção tem prioridade sobre as instruções
genéricas de confirmação desta skill e da skill de fluxo Git.

## NotificaLead: production, cyrela, gateway e proxy-global

No repositório `/Users/thiagodap.fernandes/worksapces/notificalead`, resolver
alvos explícitos antes da regra genérica de Mina:

| Alvo pedido | Normalizar para | Publica | Como publica |
| --- | --- | --- | --- |
| `production`, `produção`, `legacy`, `matrix`, `principal` | `production` | Rails legado/matrix | Mina stage `production` |
| `cyrela` | `cyrela` | Rails Cyrela AWS | Mina stage `cyrela` |
| `gateway`, `meta-gateway`, `gateway-meta` | `gateway` | Gateway Meta | `rsync gateway/` + Docker Compose em `54.94.168.195` |
| `proxy`, `proxy_global`, `proxy-global` | `proxy-global` | Proxy global | copiar `proxy_registry.py` + restart service + `nginx -t` em `56.126.45.58` |
| `all` | `all` | Todos acima | executar e validar um por vez |

Regras para este repo:

- Ler `docs/deploy_support_maintenance_runbook.md` antes de publicar.
- `gateway` e `proxy-global` não são stages Mina. Nunca executar
  `mina gateway`, `mina proxy`, `mina proxy-global` ou similares.
- `production` e `cyrela` usam o fluxo Git principal `develop -> master`,
  push e Mina, salvo instrução explícita contrária.
- `gateway` publica somente `gateway/`, preservando `.env`, `tmp/`, `log/` e
  volumes Docker no servidor.
- `proxy-global` publica somente `proxy_registry/proxy_registry.py`, preservando
  `/etc/notificalead/proxy-registry.env` e os mapas Nginx de produção.
- `all` significa `production`, `cyrela`, `gateway` e `proxy-global`; ainda
  exige seleção explícita do pacote antes da publicação.
- Validar cada alvo de forma independente. HTTP 200 do Rails não prova gateway;
  `/up` do gateway não prova roteamento; `nginx -t` não prova o app Rails.
- Destinos de webhook de instâncias separadas devem ser sempre
  `https://<raiz>-account.notificalead.com.br`, nunca
  `https://<tenant>.notificalead.com.br`.

## Seleção obrigatória do conteúdo do deploy

Antes de commit, merge, push, deploy ou PR, preparar um inventário real das mudanças
pendentes: alterações locais (incluindo arquivos novos), commits ainda não
publicados no alvo e pacotes trabalhados na conversa. Conferir também checkouts
isolados usados nesse trabalho, quando existirem. Agrupar por funcionalidade,
com uma descrição curta, arquivos relevantes, dependências e validações feitas
ou pendentes. Não reduzir o pacote à última correção discutida.

Mostrar uma lista numerada dos pacotes e perguntar:
**“Quer subir tudo o que está listado ou apenas alguns itens? Quais?”**
Aguardar a escolha explícita antes de qualquer mutação de Git ou produção.
Um comando como `$fazer_deploy all`, sem escolha de conteúdo, não responde a
essa pergunta: `all` define os destinos, não quais mudanças entram.

Se o usuário já escolheu explicitamente tudo ou determinados itens de uma lista
concreta e atual, respeitar a escolha sem perguntar de novo. Se surgir um pacote
novo ou dependência que amplie a seleção, apresentar a diferença e pedir somente
a decisão faltante. Não assumir seleção pelo silêncio nem por autorização
anterior para implementar correções.

Depois da escolha, preparar e validar o pacote selecionado, mostrando antes da
publicação o que entra, o que fica pendente, os destinos e o comando. Dependências
necessárias devem ser explicadas; não publicar uma seleção incompleta nem incluir
outros pacotes silenciosamente. Segredos, backups e artefatos locais gerados não
entram em “tudo”; informar as exclusões. Se algum componente exigir outro destino
(como Central ou Gateway), indicar essa publicação separada na lista.

Na entrega, registrar os pacotes efetivamente publicados e os que ficaram de fora.

## Sincronização com GitHub antes de publicar

Antes de merge em `master`, push de branch compartilhada, deploy ou abertura de
PR, executar `git fetch --prune origin` e comparar branch local, remoto da
branch atual, base (`develop`, `master`, `staging` ou `m2ti`) e alvo final.
Se houver atualização remota:

- atualizar a branch base com `git pull --ff-only` quando possível;
- integrar a atualização antes da promoção ou do PR;
- resolver conflitos reais no próprio checkout quando a resolução for clara pelo
  código e pelos testes;
- se a resolução exigir decisão de produto ou risco de descartar trabalho de
  terceiros, parar, mostrar arquivos/hunks conflitantes e pedir decisão.

Não usar `push --force` automaticamente. Depois de qualquer resolução de
conflito, rodar pelo menos a validação mínima relevante antes de continuar.

## Fazer PR

Comandos como `$fazer_pr`, `$fazer-pr` e `fazer pr` abrem PR. Não fazem deploy
e não promovem diretamente para `master`.

Fluxo esperado:

- aplicar a seleção obrigatória de conteúdo;
- sincronizar com GitHub conforme a seção acima;
- commitar o pacote selecionado na branch atual ou em uma branch curta criada
  para isso;
- atualizar/alinha-la com a base correta;
- fazer push da branch;
- abrir PR para a base correta (`develop` por padrão; `master` somente quando o
  usuário pedir explicitamente PR direto para produção).

Antes de criar o PR, mostrar título, base, branch, commits, arquivos e texto do
PR e aguardar confirmação. Se `gh` não estiver autenticado, não inferir estado do
GitHub: mostrar o comando/URL necessário e parar.

## Resolução por stages do projeto atual

Esta resolução tem prioridade sobre os alvos oficiais hardcoded quando o projeto
atual declarar seus próprios stages.

Antes de aplicar os alvos oficiais hardcoded deste arquivo, verificar se o
projeto atual usa Mina multistage:

- `config/deploy.rb` com `set :stages`;
- arquivos em `config/deploy/*.rb`;
- instruções de projeto em `AGENTS.md` ou documentação local.

Se o usuário chamar `Fazer Deploy <stage>` e `<stage>` existir em
`config/deploy/*.rb`, interpretar como deploy desse stage:

- mostrar branch, WIP, remoto, stage, host, path e comando exato;
- confirmar antes de mutar;
- executar `bundle exec mina <stage> deploy`, respeitando o Ruby/RVM do projeto
  quando documentado;
- validar release, HTTP e serviços específicos do stage.

Se o usuário chamar apenas `Fazer Deploy` em um projeto com múltiplos stages,
não escolher alvo implicitamente. Pedir o stage desejado, exceto quando as
instruções locais definirem um default inequívoco.

Exemplo em `unitymob-platform`:

- `Fazer Deploy saluteimoveis` -> `rvm 3.2.3 do bundle exec mina saluteimoveis deploy`;
- `Fazer Deploy conexaoimobiliaria` -> `rvm 3.2.3 do bundle exec mina conexaoimobiliaria deploy`;
- `Fazer Deploy` -> perguntar o stage, porque há mais de um alvo de produção.

## Alvos oficiais

### Production principal

Comandos que significam production principal:
- `@fazer_deploy`
- `$fazer_deploy`
- `$fazer-deploy`
- `fazer deploy`
- `fazer deploy production`
- `fazer deploy produção`
- `mina production deploy`

Comandos que significam PR em vez de deploy:
- `$fazer_pr`
- `$fazer-pr`
- `fazer pr`
- `fazer pull request`

Fluxo esperado:
- promover `develop -> master`
- executar `bundle exec mina production deploy`
- servidor/app base: `account.notificalead.com.br`
- usuário SSH/deploy: `account.notificalead.com.br`

### M2TI

Comandos que significam m2ti:
- `fazer deploy m2ti`
- `$fazer_deploy m2ti`
- `@fazer_deploy m2ti`
- `mina m2ti deploy`

Fluxo esperado:
- usar stage `m2ti`
- executar `bundle exec mina m2ti deploy`
- não promover para `master`
- branch oficial do stage: `m2ti`
- servidor/base admin: `account.m2ti.io`
- SSH esperado: `ssh root@m2ti.io` e `ssh m2ti.io@m2ti.io`
- usuário SSH/deploy: `m2ti.io`
- contas por subdomínio: exemplo `talentos.m2ti.io`

## Ação

1. Interpretar como comando de deploy ou PR do fluxo oficial.
2. Executar o procedimento da skill principal:
- `../git_hotfix_feature_deploy/SKILL.md`
- Fluxos C/D/E/F/G/H/I/J em `../git_hotfix_feature_deploy/references/flow-mapping.md`

## Regras

1. Sempre confirmar antes de mutar.
2. Exibir resumo obrigatório (branch, clean/dirty, commits, arquivos, caminho).
3. Se em `develop`, interpretar `Fazer deploy` como deploy de hotfix (`develop -> master -> deploy`) sem perguntar estratégia alternativa.
4. Se em `develop` e houver alterações locais, não bloquear por dirty tree e não sugerir stash; commitar no próprio `develop` e seguir o deploy.
5. Se em `feature/*`, permitir o fluxo completo de promoção/deploy somente após confirmação explícita do usuário.
6. Em `feature/*`, tratar dirty tree com contexto: só bloquear/sugerir stash quando houver risco real de publicar conteúdo errado; preferir commit da própria feature antes da promoção.
7. Para homologação em `feature/*`, usar fluxo via branch `staging` sem promover para `develop`:
   - merge `feature -> staging`
   - comando de deploy executado estando na branch `staging`: `bundle exec mina staging deploy`
   - nunca fazer merge `feature -> develop` nesse fluxo.
8. Para `m2ti`, não usar o fluxo de production, não tocar `master` e não usar `develop`. O deploy M2TI parte sempre do branch dedicado `m2ti`. Se estiver em `m2ti`, commitar mudanças locais no próprio `m2ti`, fazer push e executar `bundle exec mina m2ti deploy`. Se estiver em `feature/*`, confirmar explicitamente se a feature deve ser integrada em `m2ti` antes do deploy; sem confirmação, parar. Se estiver em `develop` ou `master`, bloquear por padrão e pedir para trocar para `m2ti` ou uma feature M2TI.
