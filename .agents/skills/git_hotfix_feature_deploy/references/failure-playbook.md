# Failure Playbook

## Conflitos de merge ou rebase

1. Reportar arquivos em conflito com `git status --short`.
2. Resolver no checkout quando a resolução for clara pelo código e pelos testes.
3. Rodar a validação mínima relevante antes de continuar.
4. Se houver decisão de produto, risco de descartar trabalho de terceiros ou dúvida real, parar.
5. Nao fazer push, PR ou deploy enquanto houver conflito pendente.

## Pull `--ff-only` falhou

1. Reportar que a branch local divergiu da remota.
2. Nao fazer merge automático sem confirmação.
3. Sugerir inspeção com `git log --oneline --left-right --graph <branch>...origin/<branch>`.

## Deploy falhou

1. Reportar comando executado, branch, hash e trecho relevante do erro.
2. Nao tentar rollback automático sem confirmação.
3. Se produção foi afetada, priorizar diagnóstico do estado remoto e logs do deploy.

## Dirty tree inesperada

1. Identificar arquivos alterados.
2. Separar alterações coerentes com o fluxo de alterações suspeitas.
3. Em `develop` durante deploy, preferir commit no próprio `develop`.
4. Em `feature/*`, commitar a feature ou bloquear se houver risco de publicar conteúdo indevido.
