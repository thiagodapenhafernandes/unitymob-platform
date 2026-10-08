---
name: trabalhar_feature
description: Atalho para retomar/selecionar feature com rebase em develop e restore de stash de hotfix. Use quando o usuario pedir @trabalhar_feature, $trabalhar_feature_ ou trabalhar feature <nome>.
---

# Atalho: Trabalhar Feature

Use este atalho quando o usuario pedir:
- `@trabalhar_feature`
- `$trabalhar_feature`
- `@trabalhar_feature_`
- `$trabalhar_feature_`
- `trabalhar_feature_`
- `trabalhar feature <nome>`
- `listar features` (dentro do contexto desta skill)

Compatibilidade legada:
- `$trabalhar-feature`
- `trabalhar-feature`

Gatilhos de modo assistido (listagem):
- `trabalhar_feature_`
- `$trabalhar_feature_`
- `@trabalhar_feature_`

Regra canônica:
- O sufixo `_` no final de `trabalhar_feature_` e o gatilho padrao para listar features.
- Sem o sufixo `_`, a skill espera `trabalhar feature <nome>` para executar troca/rebase direto.

## Acao

1. Interpretar como comando de retorno/selecao de feature do fluxo oficial.
2. Executar o procedimento da skill principal:
- `../git_hotfix_feature_deploy/SKILL.md`
- Fluxo B em `../git_hotfix_feature_deploy/references/flow-mapping.md`

## Modo assistido

1. Se vier com o gatilho `trabalhar_feature_` (ou equivalentes com `$`/`@`), executar:
```bash
git fetch --prune origin
{
  git for-each-ref --format='%(refname:short)' refs/heads/feature/;
  git for-each-ref --format='%(refname:short)' refs/remotes/origin/feature/;
} | sed 's#^origin/##' | sort -u
```
2. Exibir lista `feature/*` em menu numerado.
3. Aceitar escolha por numero (ex.: `3`) e mapear para a branch.
4. Confirmar selecao antes de mutacao:
- `Voce selecionou: feature/... Confirmar? (sim/nao)`
- positivos: `s`, `sim`, `y`, `yes`
- negativos: `n`, `nao`, `no`
5. So executar fluxo de troca/rebase apos confirmacao positiva.

Escopo:
- Esse comportamento de listagem dinamica so acontece no contexto do atalho `trabalhar_feature`.
