---
name: unitymob-architecture-audit
description: Auditoria de arquitetura e mapeamento de reutilização na Unitymob (read-only primeiro): responsabilidades dispersas, duplicação, centralização em serviços/componentes compartilhados e roadmap documentado em docs/architecture/.
---

# Unitymob Architecture Audit

Iniciativa de Architecture Audit + Reusability Mapping para o `unitymob-platform`
(Rails + PostgreSQL + CRM multi-tenant). Descobre o que está espalhado pelo
sistema e poderia ser consolidado em serviços, componentes, módulos ou
bibliotecas compartilhadas — com evidências reais do código, sem modificar nada
na primeira fase.

## Skills combinadas (instalar antes de rodar)

| Skill | Papel nesta iniciativa |
|---|---|
| `architecture-audit` | Descoberta principal: fricção arquitetural e responsabilidades dispersas |
| `sync-repository` | Duplicação, código morto, complexidade e drift código-docs |
| `architecture` | ADRs para cada decisão de centralizar ou não |
| `architectural-refactor` | Só na fase 2: transformar o diagnóstico em plano executável |
| `doc-coauthoring` | Estruturar a documentação gerada |

Ler o corpo de cada skill antes de usá-la nesta iniciativa.

## Fase 1 — Auditoria somente-leitura (padrão)

1. Inventariar os domínios: Leads, Distribuição, Integrações, WhatsApp,
   Permissões, Auditoria, Notificações, Frontend admin.
2. Para cada oportunidade, registrar: implementação atual, arquivos envolvidos
   (com `arquivo:linha`), dependências, proposta de centralização, benefícios,
   riscos e prioridade.
3. Distinguir sempre **duplicação técnica** (trechos parecidos que podem ficar
   separados) de **duplicação de responsabilidade** (a mesma regra de negócio
   implementada de jeitos diferentes — ex.: criação de lead via webhook, API,
   importação ou integração externa).
4. Não modificar código, migrations, dados ou configuração. Não abrir PRs.

## Fase 2 — Roadmap (somente com aprovação explícita)

Com o diagnóstico aprovado, usar `architectural-refactor` para dividir em
etapas verificáveis sem alterar comportamento, e `doc-coauthoring` para a
documentação final.

## Saída versionada

```
docs/
└── architecture/
    ├── architecture-overview.md
    ├── module-inventory.md
    ├── duplicated-responsibilities.md
    ├── reusable-services.md
    ├── dependency-map.md
    ├── refactoring-roadmap.md
    └── decisions/
        └── ADR-001-centralizar-criacao-de-leads.md
```

## Regras Unitymob

- Respeitar multi-tenancy: centralizar nunca pode vazar dados entre contas.
- Reutilizar antes de criar: checar `app/services`, concerns, `Admin::UiHelper`,
  `ax-*` e partials compartilhadas antes de propor algo novo.
- Cada achado precisa de evidência (arquivo, linha, trecho). Hipótese sem
  evidência vai para uma seção separada de "suspeitas".
- Reportar em pt-BR.
