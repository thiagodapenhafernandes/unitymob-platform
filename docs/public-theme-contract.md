# Contrato de temas do site público (v1)

> Meta confirmada (2026-09-24): **Opção A** — um HTML canônico, N folhas CSS por
> tema, cada tema não-global amarrado à(s) conta(s) via `tenant_slugs`, `default`
> como fallback universal. Layout atual de Salute/Conexão preservado como verdade
> visual; referência de restore em
> `/Users/thiagodap.fernandes/worksapces/public-layout-backup-20260924-fptc/`.

## Hooks semânticos (aditivos, sem risco visual)

Classes de *papel* no markup público. Temas novos estilizam estas classes;
nunca markup novo, helpers ou branches por chave:

| Hook | Onde |
| --- | --- |
| `ps-topbar` / `ps-brand` / `ps-nav` | `shared/_header` |
| `ps-hero` | `home/_hero` |
| `ps-card` / `ps-card-body` / `ps-price` | `habitations/_card` |
| `ps-footer` | `shared/_footer` |

Âncoras existentes mantidas: classe `public-site-theme--<chave>` e
`data-public-site-theme` no `<body>`, folha via `Tenant#public_site_stylesheet`.

## Paleta como API

O layout público emite no `:root`: `--color-primary`, `--color-secondary`,
`--color-accent`, `--color-hero-button`, `--color-hero-button-text`.
Temas referenciam essas vars em vez de cores fixas — a aba Paleta continua
valendo em qualquer tema.

## Adicionar um tema

Soltar `<chave>.css` em `app/assets/stylesheets/public_site_themes/`.
`Tenant.public_site_theme_definitions` descobre o arquivo (rótulo humanizado
quando fora de `PUBLIC_SITE_THEME_METADATA`) e o `select` da aba Modelo visual
passa a oferecê-lo, respeitando `available_public_site_themes`. Salvar usa o
fluxo existente (`PublicIdentitiesController#update_theme!`).

## Escopo por tenant

Todo tema não-global declara `tenant_slugs` em `PUBLIC_SITE_THEME_METADATA`:
o tema só aparece no `select` das contas listadas. Amarração atual:

| Tema | `tenant_slugs` |
| --- | --- |
| `saluteimoveis`, `salute_luxury` | `salute` |
| `conexaoimobiliaria` | `conexao` |
| `default` | global (fallback de todas as contas) |

A conta também enxerga o tema inferido pelo nome e o que já está em uso, então
renomear a conta nunca esconde o tema atual. `salute_luxury` é variante com
shell próprio (`public_theme/luxury_shell`, classes `sl-*`); os demais temas
estilizam os hooks `ps-*` do markup compartilhado.

## Fora do contrato (futuro)

Portar o luxury do `unitymob-crm` (composers + controller + fontes) como
consumidor deste contrato; convenção de prefixo por tenant para liberar temas
fora do trio conhecido.
