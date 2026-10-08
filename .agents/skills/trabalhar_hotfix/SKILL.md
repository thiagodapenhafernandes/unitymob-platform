---
name: trabalhar_hotfix
description: Atalho para iniciar ciclo de hotfix com guardrails (sair de feature para develop com stash seguro quando necessario). Use quando o usuario pedir @trabalhar_hotfix, $trabalhar_hotfix ou $trabalhar-hotfix.
---

# Atalho: Trabalhar Hotfix

Use este atalho quando o usuario pedir:
- `@trabalhar_hotfix`
- `$trabalhar_hotfix`
- `$trabalhar-hotfix`
- `trabalhar hotfix`

## Ação

1. Interpretar como comando de hotfix do fluxo oficial.
2. Executar o procedimento da skill principal:
- `../git_hotfix_feature_deploy/SKILL.md`
- Fluxo A em `../git_hotfix_feature_deploy/references/flow-mapping.md`

## Regras

1. Respeitar guardrails da skill principal.
2. Se estiver em `feature/*` suja: stash automático nomeado.
3. Branch final esperada: `develop`.
