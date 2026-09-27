# Melhorias futuras

Este documento concentra melhorias desejáveis que ainda não devem ser tratadas como comportamento entregue.

## Temas públicos: registry operacional

Estado atual (entregue, ver `docs/public-theme-contract.md`):

- Conta nova nasce no tema `default` (padrão da coluna e `attribute` no model
  `Tenant`); se o nome/slug bater com um tema cadastrado, nasce nele.
- Tema novo: `rails g public_theme <chave> --label="Rótulo" --tenant-slugs=conta`
  cria a folha em `public_site_themes/` e registra em
  `Tenant::PUBLIC_SITE_THEME_METADATA` na variante `default`, herdando todos os
  componentes. `spec/requests/public_themes_contract_spec.rb` passa a cobrir o
  tema sozinho.
- Folhas soltas no diretório são descobertas por `public_site_theme_definitions`.

Ainda futuro:

- Mover o registry (`PUBLIC_SITE_THEME_METADATA`) para YAML ou tabela
  administrativa, com validação contra assets existentes, para não editar o
  model a cada tema.
- Criar tema pela tela administrativa com revisão e deploy, nunca gerando CSS
  em runtime (asset órfão, sem versionamento).
