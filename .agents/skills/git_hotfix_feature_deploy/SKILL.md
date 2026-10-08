---
name: git_hotfix_feature_deploy
description: Interpreta comandos de fluxo Git, deploy e PR no ciclo feature/develop/master com suporte explícito a NotificaLead production/cyrela/gateway/proxy-global/all, m2ti e homologação (staging).
---

# Git Flow de Hotfix, Feature, Deploy e PR (NotificaLead)

Skill operacional para executar fluxo Git, deploy e PR com seguranca e baixa ambiguidade no ciclo:
- `feature/*` (trabalho longo)
- `develop` (hotfix/integração)
- `master` (produção)
- `staging` (homologação)
- `m2ti` (branch dedicado do stage/base account.m2ti.io)

## Gatilhos

Esta skill aceita estes comandos:
1. `Trabalhar hotfix` (ou `@trabalhar_hotfix`)
2. `Trabalhar feature <nome>` (ou `@trabalhar_feature <nome>`)
3. `Fazer deploy` (ou `@fazer_deploy` / `$fazer_deploy`)
4. `Fazer deploy gateway`, `Fazer deploy proxy-global`, `Fazer deploy cyrela` ou `Fazer deploy all`
5. `Fazer deploy homologacao` (ou `@fazer_deploy_homologacao` / `$fazer_deploy_homologacao`)
6. `Fazer deploy m2ti` (ou `@fazer_deploy m2ti` / `$fazer_deploy m2ti` / `mina m2ti deploy`)
7. `Fazer PR` (ou `$fazer_pr` / `$fazer-pr` / `fazer pr`)

Observação:
- `@trabalhar_feature` sem nome é tratado como o mesmo comando 2 em modo assistido (lista `feature/*` e pede seleção).

## Alvos especiais do NotificaLead

No checkout `/Users/thiagodap.fernandes/worksapces/notificalead`, os alvos de
`$fazer_deploy` sao:

| Alvo | Tipo | Acao |
| --- | --- | --- |
| `production`, `produção`, `legacy`, `matrix`, `principal` | Rails/Mina | promover pacote para `master` e rodar `mina production deploy` |
| `cyrela` | Rails/Mina | promover pacote para `master` e rodar `mina cyrela deploy` |
| `gateway`, `meta-gateway`, `gateway-meta` | Docker Compose | publicar `gateway/` por `rsync`, rebuild/up e validar `/up` + eventos |
| `proxy`, `proxy_global`, `proxy-global` | service/Nginx | publicar `proxy_registry.py`, reiniciar service, validar `nginx -t` + mapa |
| `all` | misto | executar `production`, `cyrela`, `gateway` e `proxy-global`, validando cada alvo |

Para `gateway` e `proxy-global`, nao aplicar fluxo Mina nem tentar resolver como
stage de `config/deploy/*.rb`. Antes de publicar, ler
`docs/deploy_support_maintenance_runbook.md`, fazer a selecao obrigatoria de
pacote e mostrar destino/comandos exatos.

## Contrato dos comandos

### 1) `Trabalhar hotfix`

Objetivo:
- Sair de `feature/*` para `develop` sem levar codigo da feature.
- Se houver dirty tree na feature, salvar stash automatico nomeado.

Resultado esperado:
- branch final `develop`, atualizada com `git pull --ff-only`
- metadados de retorno salvos em `git config --local codex.flow.*`

### 2) `Trabalhar feature <nome>`

Objetivo:
- Ir para a feature especificada.
- Rebase da feature em `develop`.
- Restaurar stash pendente associado a essa feature (quando existir).

Resultado esperado:
- branch final `feature/<nome>`
- feature alinhada com `develop`
- stash restaurado (se aplicavel)

Modo assistido (sem nome):
- Se o comando vier como `@trabalhar_feature` sem nome, listar branches `feature/*` locais/remotas e pedir que o usuario escolha uma entrada.
- A listagem deve ser numerada (`1.`, `2.`, `3.` ...) e o usuario pode responder apenas com o numero.
- Antes de executar mutacao, exibir: `Voce selecionou: feature/... Confirmar? (sim/nao)`.
- Respostas positivas aceitas: `s`, `sim`, `y`, `yes`.
- Respostas negativas aceitas: `n`, `nao`, `não`, `no`.

### 3) `Fazer deploy`

Objetivo:
- Sempre pedir confirmacao obrigatoria antes de qualquer acao.
- Exibir resumo contextual automatico (branch, status, commits, arquivos, caminho).
- Sem alvo explícito, significa production principal.

Regras:
- Se branch atual for `develop`: tratar como deploy de hotfix e promover `develop -> master`, push e deploy.
- Se branch atual for `develop` e houver dirty tree: não bloquear e não sugerir stash; commitar no próprio `develop` e seguir o fluxo.
- Se branch atual for `feature/*`: so continua apos confirmacao explicita do usuario; promove feature inteira para `develop`, depois `develop -> master`, push e deploy (com equalizacao final em `develop`).
- Em `feature/*` com dirty tree: tratar com contexto, priorizando commit da feature; só bloquear/sugerir stash quando houver risco real de publicar conteúdo indevido.
- Se branch atual for `master`: deploy do estado atual de `master`.
- Comando final de production principal: `bundle exec mina production deploy`.
- Servidor production principal: `account.notificalead.com.br`.
- Usuario SSH/deploy production principal: `account.notificalead.com.br`.

Antes de promover para `master`, sincronizar com GitHub: buscar remotos,
atualizar bases e integrar atualizações remotas no pacote aprovado. Resolver
conflitos quando a resolução for clara pelo código/testes; se exigir decisão de
produto ou risco de apagar trabalho de terceiros, parar com os hunks conflitantes
e pedir decisão.

### 4) `Fazer deploy homologacao`

Objetivo:
- Fazer deploy em staging sem promover `feature/*` para `develop`.
- Em `feature/*`, publicar exatamente a feature atual em homologação.

Regras:
- Confirmacao explicita obrigatoria.
- Working tree deve estar limpa.
- Equalizar a feature com `develop` antes de deploy:
  1) atualizar `develop` (`pull --ff-only`)
  2) voltar para feature atual
  3) `git rebase develop`
- Deploy em homologacao sempre acontece na branch `staging`:
  - promover `feature -> staging`
  - executar `bundle exec mina staging deploy` estando em `staging`
- Nunca fazer merge `feature -> develop` nesse fluxo.

### 5) `Fazer deploy m2ti`

Objetivo:
- Deployar o stage `m2ti` em `account.m2ti.io`.
- Usar o usuario de deploy `m2ti.io`.
- Manter coerencia com subdominios de contas como `talentos.m2ti.io`.

Regras:
- Confirmacao explicita obrigatoria.
- Nao promover para `master`.
- Nao executar `bundle exec mina production deploy`.
- Branch oficial do stage `m2ti`: `m2ti`.
- Se branch atual for `m2ti`: commitar mudanças locais no proprio `m2ti` quando houver dirty tree, fazer push de `m2ti` e executar `bundle exec mina m2ti deploy`.
- Se branch atual for `feature/*`: pedir confirmacao explicita para integrar a feature em `m2ti` antes do deploy `m2ti`; se confirmado, merge `feature -> m2ti`, push `m2ti`, executar `bundle exec mina m2ti deploy`; se nao confirmado, parar.
- Se branch atual for `develop` ou `master`: bloquear por padrao e pedir para voltar a `m2ti`, porque M2TI não usa a linha principal `develop -> master`.
- SSH esperado: `ssh root@m2ti.io` e `ssh m2ti.io@m2ti.io`.

### 6) `Fazer PR`

Objetivo:
- Preparar o pacote selecionado e abrir PR no GitHub em vez de promover para
  `master` ou executar Mina.

Regras:
- Confirmacao explicita obrigatoria antes de commit, push ou criação do PR.
- Aplicar a seleção obrigatória de conteúdo.
- Executar `git fetch --prune origin`, atualizar a base com `pull --ff-only` e
  integrar atualizações remotas antes do push.
- Base padrão do PR: `develop`. Usar `master` somente se o usuário pedir PR
  direto para produção.
- Se a branch atual for `develop` ou `master`, criar uma branch curta para o PR
  antes de commitar.
- Se a branch atual for `feature/*`, commitar/pushar a própria feature quando o
  pacote aprovado corresponder a ela; caso contrário criar branch nova.
- Abrir PR com `gh pr create` quando `gh` estiver autenticado. Se não estiver,
  mostrar título, base, branch, corpo e comando/URL para criação manual e parar.
- Não executar deploy, não fazer merge em `master` e não usar `push --force`.

## Seleção do conteúdo antes do deploy

Em qualquer fluxo de deploy ou PR desta skill, aplicar primeiro a seção
“Seleção obrigatória do conteúdo do deploy” de
[../fazer_deploy/SKILL.md](../fazer_deploy/SKILL.md).
Listar os pacotes pendentes e perguntar se o usuário quer subir tudo ou selecionar
itens, antes de commit, merge, push ou deploy. A escolha de stage não substitui a
escolha de conteúdo. Uma escolha explícita sobre lista atual não precisa ser
reconfirmada; não inferir o escopo apenas pela última demanda da conversa.

## Sincronização com GitHub

Antes de merge em branch compartilhada, push, deploy ou PR:

1. Executar `git fetch --prune origin`.
2. Comparar branch local, upstream, base e alvo final com `git status -sb`,
   `git rev-list --left-right --count` e logs curtos.
3. Atualizar bases com `git pull --ff-only` quando possível.
4. Integrar atualizações remotas antes de publicar.
5. Resolver conflitos claros no checkout, validar e continuar.
6. Se o conflito for ambíguo ou envolver descarte de trabalho de terceiros,
   parar e mostrar arquivos/hunks conflitantes.

## Guardrails obrigatorios

1. `git fetch --prune origin` antes de merge/push/deploy/PR.
2. `git pull --ff-only` em `develop`/`master` e na base do stage/PR.
3. Nunca usar `git push --force` automaticamente.
4. Merge em branch compartilhada sempre com `--no-ff`.
5. Em conflito: resolver quando seguro pelo código/testes; se ambíguo, interromper, reportar conflito e nao continuar.
6. Dirty tree:
- `Trabalhar hotfix`: stash automatico.
- `Fazer deploy` em `develop`: nunca bloquear por dirty tree; commitar no `develop` e seguir deploy.
- `Fazer deploy` em `feature/*`: avaliar risco; preferir commit na própria feature antes da promoção, e só bloquear/sugerir stash com risco real.
7. Deploy padrao sem alvo explicito: production principal com `bundle exec mina production deploy`.
8. Deploy `m2ti`: `bundle exec mina m2ti deploy`, partindo do branch `m2ti`, sem tocar `develop` nem `master`.
9. Homologacao em feature: merge `feature -> staging` seguido de `bundle exec mina staging deploy` na branch `staging`.
10. PR: não executar Mina nem promover para `master`; pushar branch e abrir PR após confirmação.

## Estado local (persistencia)

Persistir via `git config --local`:
- `codex.flow.origin-branch`
- `codex.flow.stash-ref`
- `codex.flow.started-at`
- `codex.flow.last-hotfix-deploy-commit` (opcional)

Stash padrao:
- mensagem: `skill/hotfix-return:<feature>:<timestamp>`

## Tabela de decisao por comando/branch

### Comando `Trabalhar hotfix`
- Em `feature/*`: stash (se dirty), salvar contexto, trocar para `develop`, atualizar `develop`.
- Em `develop`: apenas atualizar `develop`.
- Em `master`: bloquear e pedir confirmacao se usuario realmente quer abrir hotfix em `develop`.

### Comando `Trabalhar feature <nome>`
- Em qualquer branch: localizar/criar tracking da feature, atualizar `develop`, rebase feature em `develop`, restaurar stash relacionado, limpar contexto.
- Sem `<nome>` (ex.: `@trabalhar_feature`): listar `feature/*`, pedir selecao e so depois executar o fluxo.

### Comando `Fazer deploy`
- Em `develop`: fluxo C (promocao e deploy de hotfix), com commit automatico no `develop` se houver mudanças pendentes.
- Em `feature/*`: fluxo D (promocao completa com confirmacao explicita).
- Em `master`: fluxo E (deploy direto).

### Comando `Fazer deploy homologacao`
- Em `feature/*`: fluxo F (equalizacao `develop -> feature`, merge em `staging` e deploy pela branch `staging`).
- Em `develop`: fluxo G (deploy staging do estado atual de `staging`), somente se solicitado explicitamente.
- Em `master`: bloquear por padrao e pedir branch explicita para homologacao.

### Comando `Fazer deploy m2ti`
- Em `m2ti`: fluxo H (push `m2ti` e deploy `m2ti`).
- Em `feature/*`: fluxo I (confirmar integracao feature -> m2ti, push `m2ti` e deploy `m2ti`).
- Em `develop` ou `master`: bloquear por padrao; `m2ti` deve sair do branch dedicado `m2ti`.

### Comando `Fazer PR`
- Em `feature/*`: fluxo J (atualizar base, alinhar feature, pushar branch e abrir PR).
- Em `develop` ou `master`: fluxo J criando branch curta antes do commit/PR.
- Em `m2ti` ou `staging`: pedir base explicitamente antes de abrir PR.

## Mensagem de confirmacao obrigatoria para deploy

Antes de executar `Fazer deploy`, `Fazer deploy m2ti`, `Fazer deploy homologacao` ou `Fazer PR`, montar e mostrar:
1. Branch atual.
2. `clean/dirty`.
3. Ultimos commits relevantes (`git log --oneline -n 5`).
4. Arquivos alterados (`git status --short`).
5. Caminho de promocao:
- `develop -> master -> deploy`
- `feature/<x> -> develop -> master -> deploy`
- `master -> deploy`
- `feature/<x> -> staging -> deploy homologacao`
- `m2ti -> deploy m2ti`
- `feature/<x> -> m2ti -> deploy m2ti`
- `branch -> PR para develop`
- `branch -> PR para master`
6. Alvo e comando:
- production principal: `bundle exec mina production deploy`
- m2ti: `bundle exec mina m2ti deploy`
- homologacao: `bundle exec mina staging deploy`
- PR: `gh pr create ...`

Pergunta obrigatoria:
- "Confirmo que devo seguir exatamente neste caminho?"

Sem confirmacao explicita: encerrar sem mutacao.

Nota de UX operacional:
- Em `develop`, não insistir em mensagens de bloqueio por árvore suja/stash ao usuário; apenas informar que será feito commit no `develop` antes da promoção.

## Sobre autocomplete

1. A skill suporta parsing de comandos com prefixo `@` e `$` imediatamente.
2. "Autocomplete visual" (dropdown em tempo real) depende do cliente de chat/IDE.
3. Quando o cliente nao oferecer autocomplete nativo, usar autocomplete assistido:
- `@trabalhar_feature` -> skill lista `feature/*` disponiveis e aguarda selecao.
- Preferir menu numerado e aceitar resposta curta do usuario (ex.: `3`).
- Apos o numero, sempre pedir confirmacao final da feature selecionada.
- Confirmacao deve aceitar sinonimos curtos de sim/nao para reduzir friccao.

## Fora de escopo

Nao interpretar comandos diferentes dos oficiais acima. Se o texto do usuario nao casar com esses comandos, pedir reformulação para um dos comandos oficiais.

## Fluxos operacionais (comandos)

Para detalhes completos e variacoes, leia:
- `references/flow-mapping.md`
- `references/failure-playbook.md`

Resumo:
1. Fluxo A: hotfix vindo de `feature/*`.
2. Fluxo B: retorno para `feature/<nome>`.
3. Fluxo C: deploy em `develop`.
4. Fluxo D: deploy em `feature/*` (confirmado).
5. Fluxo E: deploy em `master`.
6. Fluxo F: deploy homologacao em `feature/*` via `staging` sem promocao para `develop`.
7. Fluxo H/I: deploy `m2ti` via branch dedicado `m2ti`, sem promocao para `develop` nem `master`.
8. Fluxo J: preparar branch e abrir PR sem deploy.

## Validação rapida (apos cada comando)

1. `git branch --show-current` confere branch esperada.
2. `git status -sb` coerente com resultado esperado.
3. Quando houve push: reportar hash e branch remota.
4. Quando houve deploy: reportar status final do comando `mina`.

## Referencias

Abrir somente quando necessario:
- `references/source-docs.md` para origem das regras no projeto.
- `references/flow-mapping.md` para passos detalhados por cenário.
- `references/failure-playbook.md` para incidentes e rollback operacional.
