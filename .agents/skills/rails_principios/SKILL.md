---
name: rails_principios
description: Use em qualquer tarefa de desenvolvimento Ruby on Rails para aplicar principios de arquitetura Rails, RVM, ActiveJob, Mina, seguranca, multi-tenant, banco de dados, testes e quality gates antes de implementar ou revisar codigo.
---

# Rails Principios

Use este skill quando a tarefa envolver desenvolvimento, revisao, diagnostico ou planejamento em Ruby on Rails.

## Postura inicial

Antes de implementar, entenda o projeto real. Nao assuma stack, gems, banco, fila, autorizacao, deploy ou padrao visual sem verificar os arquivos existentes.

Quando a tarefa for implementar algo novo, corrigir bug ou refatorar codigo existente, aplique tambem o modo Ponytail se o plugin/skill `ponytail` estiver disponivel na sessao. Use-o como filtro de simplicidade: YAGNI, menor diff correto, reutilizacao de codigo local antes de codigo novo, stdlib/nativo antes de dependencia, e nenhuma abstracao especulativa. O Ponytail nao substitui as regras Rails abaixo; ele reduz o escopo da solucao depois que o fluxo real foi entendido.

Verifique, conforme a tarefa exigir:

- `.ruby-version`;
- `.ruby-gemset`;
- `Gemfile`;
- `.env.development` e arquivos `.env` relevantes;
- `config/database.yml`;
- `config/routes.rb`;
- controllers, models, services, jobs, policies e views existentes;
- framework de testes;
- autenticacao e autorizacao;
- padrao visual e organizacao atual das telas.

## Convencoes do workspace do usuario

- Preferir Ruby via RVM quando o projeto tiver `.ruby-version` ou `.ruby-gemset`.
- Nao assumir Sidekiq; verificar ActiveJob e o adapter real antes de criar jobs.
- Quando o projeto usar Mina, respeitar Mina como padrao de deploy/acesso.
- Nao introduzir Kamal, Thruster ou outro deploy stack sem motivo explicito.
- No `m2ti_bi`, consultar `docs/FOUNDATION.md` antes de alterar BI, builders, consultas, visualizacoes, dashboards ou roadmap.

## Arquitetura Rails

- Priorizar Rails CRUD nativo, RESTful e simples.
- Controllers orquestram; nao concentram regra de negocio.
- Models mantem associacoes, validacoes, scopes pequenos e regras coesas do dominio.
- Services/POROs existem para fluxos de negocio reais, nao para CRUD trivial.
- Query Objects entram quando consultas ficam complexas, reutilizaveis ou sensiveis a performance.
- Form Objects entram quando o formulario nao couber bem em um unico model.
- Presenters, decorators, helpers e partials tratam apresentacao, nao regra de negocio.
- Jobs precisam ser idempotentes, seguros para retry e claros nos logs.

Evite abstracao prematura, callbacks com efeitos externos escondidos, monkey patches, nomes genericos, solucoes magicas e codigo que funciona apenas no cenario feliz.

## Seguranca e multi-tenant

- Considerar autenticacao, autorizacao por perfil/permissao e escopo por conta/tenant quando existir.
- Nunca presumir que usuario logado pode acessar qualquer recurso.
- Usar strong parameters.
- Proteger contra mass assignment indevido, SQL injection, exposicao de dados sensiveis e vazamento entre tenants.
- Nao registrar dados sensiveis em logs.
- Tratar erros de forma explicita e segura.

## Banco de dados

- Usar nomes claros.
- Usar `null: false` quando obrigatorio.
- Usar `foreign_key: true` em relacionamentos.
- Adicionar indices para joins, filtros, buscas frequentes e unicidade.
- Usar constraints quando fizer sentido.
- Evitar campos genericos demais e duplicacao de dados sem justificativa.
- Pensar em rollback e reversibilidade.
- Para mudancas arriscadas em producao, separar schema change, backfill, ativacao da regra e limpeza posterior.

## Interface Rails

- Manter o padrao visual existente.
- Preferir Rails views, partials, Turbo e Stimulus antes de complexidade maior.
- Nao transformar CRUD comum em SPA sem necessidade explicita.
- Usar pt-BR/I18n para textos visiveis, labels, mensagens e feedbacks recorrentes.
- Telas operacionais devem ser claras, previsiveis e coerentes com o restante do sistema.

## Testes e validacao

Inclua ou ajuste testes proporcionais ao risco, cobrindo quando aplicavel:

- sucesso;
- erro;
- validacoes;
- autorizacao;
- escopo por tenant/conta;
- services;
- jobs;
- casos extremos.

Priorize testes de comportamento.

Quando possivel, rode os comandos reais do projeto:

- testes;
- lint;
- `bin/rails zeitwerk:check`;
- validacao de migrations;
- build CSS/JS;
- smoke test web quando o fluxo web for afetado.

Se algum comando nao puder ser executado, explique exatamente o motivo.

## Quality gates

Antes de entregar, revise:

- duplicacao;
- complexidade;
- metodos longos;
- classes com muitas responsabilidades;
- N+1 queries;
- queries sem indice;
- autorizacao ausente;
- vazamento entre tenants;
- tratamento de erro;
- logs sensiveis;
- callbacks perigosos;
- testes insuficientes;
- impacto em producao.

Para implementacoes e refatoracoes, inclua nesse quality gate um passe Ponytail: remova codigo que ficou especulativo, una camadas criadas sem necessidade, prefira um ajuste no ponto compartilhado do fluxo em vez de guards espalhados e mantenha somente testes proporcionais ao risco real.

Nao entregue codigo apenas porque funciona. Entregue codigo simples, seguro, consistente, testavel, legivel, sustentavel e alinhado com a arquitetura Rails do projeto.
