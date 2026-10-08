# Flow Mapping

Este arquivo detalha os fluxos citados pela skill `git_hotfix_feature_deploy`.

## Fluxo A: Trabalhar hotfix vindo de `feature/*`

1. Verificar branch atual com `git branch --show-current`.
2. Se houver alterações locais na feature, criar stash nomeado:
   `git stash push -u -m "skill/hotfix-return:<feature>:<timestamp>"`.
3. Persistir contexto com `git config --local codex.flow.*`.
4. Trocar para `develop`.
5. Executar `git fetch --prune origin` e `git pull --ff-only`.
6. Validar branch final `develop` e status.

## Fluxo B: Trabalhar feature

1. Resolver ou selecionar `feature/<nome>`.
2. Executar `git fetch --prune origin`.
3. Atualizar `develop` com `git checkout develop` e `git pull --ff-only`.
4. Trocar/criar tracking da feature.
5. Executar `git rebase develop`.
6. Restaurar stash associado, quando existir.
7. Validar branch final e status.

## Fluxo C: Fazer deploy a partir de `develop`

1. Exibir resumo obrigatório e pedir confirmação explícita.
2. Se houver alterações locais, commitar no próprio `develop`.
3. Executar `git fetch --prune origin`, comparar `develop` com `origin/develop` e atualizar com `git pull --ff-only`.
4. Trocar para `master`, comparar com `origin/master` e atualizar com `git pull --ff-only`.
5. Fazer merge `develop -> master` com `--no-ff`; resolver conflitos claros, validar e continuar, ou parar se a resolução exigir decisão de produto.
6. Fazer push de `master`.
7. Executar `bundle exec mina production deploy`.
8. Voltar para `develop`, equalizar com `master` quando necessário e validar.

## Fluxo D: Fazer deploy a partir de `feature/*`

1. Exibir resumo obrigatório e pedir confirmação explícita.
2. Avaliar dirty tree; preferir commit na própria feature antes de promoção.
3. Executar `git fetch --prune origin`, atualizar `develop` e alinhar feature com a base/remoto conforme o estado do repo exigir.
4. Fazer merge `feature -> develop` com `--no-ff`; resolver conflitos claros, validar e continuar, ou parar se a resolução exigir decisão de produto.
5. Fazer push de `develop`.
6. Seguir Fluxo C para promover `develop -> master` e deployar produção.
7. Equalizar branches finais e validar.

## Fluxo E: Fazer deploy a partir de `master`

1. Exibir resumo obrigatório e pedir confirmação explícita.
2. Working tree deve estar limpa.
3. Executar `git fetch --prune origin`, comparar com `origin/master` e `git pull --ff-only`.
4. Executar `bundle exec mina production deploy`.
5. Reportar hash e status final.

## Fluxo F: Fazer deploy homologacao a partir de `feature/*`

1. Exibir resumo obrigatório e pedir confirmação explícita.
2. Exigir working tree limpa.
3. Atualizar `develop` com `git pull --ff-only`.
4. Voltar para feature e executar `git rebase develop`.
5. Trocar para `staging`, atualizar e fazer merge `feature -> staging` com `--no-ff`; resolver conflitos claros, validar e continuar, ou parar se a resolução exigir decisão de produto.
6. Executar `bundle exec mina staging deploy` estando em `staging`.
7. Nunca fazer merge da feature em `develop` nesse fluxo.

## Fluxo G: Fazer deploy homologacao fora de `feature/*`

1. Exibir resumo obrigatório e pedir confirmação explícita.
2. Confirmar branch e intenção, porque homologação foi desenhada para publicar feature em `staging`.
3. Se aprovado, atualizar `staging`, integrar a origem desejada com `--no-ff`, resolver conflitos claros quando houver e executar `bundle exec mina staging deploy`.

## Fluxo H: Fazer deploy m2ti a partir de `m2ti`

1. Exibir resumo obrigatório e pedir confirmação explícita.
2. Se houver alterações locais, commitar no próprio `m2ti`.
3. Executar `git fetch --prune origin`.
4. Atualizar `m2ti` com `git pull --ff-only`.
5. Fazer push de `m2ti`.
6. Executar `bundle exec mina m2ti deploy`.
7. Validar health do servidor `account.m2ti.io` quando possível:
   - `https://account.m2ti.io/up`
   - `https://account.m2ti.io/health/ready`
   - `https://account.m2ti.io/health/business`
8. Reportar release/hash final.

Notas:
- Este fluxo não toca `develop` nem `master`.
- SSH esperado: `ssh root@m2ti.io` e `ssh m2ti.io@m2ti.io`.
- Usuario de deploy: `m2ti.io`.

## Fluxo I: Fazer deploy m2ti a partir de `feature/*`

1. Exibir resumo obrigatório e pedir confirmação explícita para integrar a feature em `m2ti`.
2. Avaliar dirty tree; preferir commit na própria feature antes da integração.
3. Executar `git fetch --prune origin`.
4. Atualizar `m2ti` com `git pull --ff-only`.
5. Voltar para feature e alinhar com `m2ti` quando necessário.
6. Fazer merge `feature -> m2ti` com `--no-ff`; resolver conflitos claros, validar e continuar, ou parar se a resolução exigir decisão de produto.
7. Fazer push de `m2ti`.
8. Executar `bundle exec mina m2ti deploy`.
9. Validar health do servidor `account.m2ti.io` quando possível.

Notas:
- Este fluxo não toca `develop` nem `master`.
- Se o usuário não confirmar a integração da feature em `m2ti`, parar sem mutação.

## Fluxo J: Fazer PR

1. Aplicar a seleção obrigatória do pacote e exibir resumo obrigatório.
2. Confirmar base do PR:
   - padrão `develop`;
   - `master` somente se o usuário pedir PR direto para produção;
   - em `m2ti` ou `staging`, pedir base explicitamente.
3. Executar `git fetch --prune origin`.
4. Atualizar a base com `git checkout <base>` e `git pull --ff-only`.
5. Preparar branch:
   - se veio de `feature/*` e o pacote pertence à feature, voltar para ela;
   - se veio de `develop`/`master` ou o pacote não pertence à feature atual, criar branch curta a partir da base.
6. Integrar a base atualizada na branch do PR por rebase ou merge, seguindo o padrão do repositório.
7. Resolver conflitos claros no checkout, validar e continuar; se ambíguo, parar com arquivos/hunks conflitantes.
8. Commitar somente o pacote aprovado.
9. Mostrar título, corpo do PR, base, branch, commits e arquivos; pedir confirmação.
10. Fazer push da branch.
11. Abrir PR com `gh pr create --base <base> --head <branch>` quando `gh` estiver autenticado.
12. Se `gh` não estiver autenticado, mostrar o comando/URL para criação manual e parar sem inferir estado do GitHub.

Notas:
- Este fluxo não executa Mina.
- Este fluxo não faz merge direto em `master`.
- Nunca usar `git push --force` automaticamente.
