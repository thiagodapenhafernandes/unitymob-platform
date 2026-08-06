# Melhorias futuras

Este documento concentra melhorias desejáveis que ainda não devem ser tratadas como comportamento entregue.

## Provisionamento de tema público por tenant

### Estado atual

- A criação de uma nova conta provisiona tenant, dono da conta, perfis básicos e domínio opcional.
- O site público escolhe a folha visual por `Tenant#public_site_stylesheet`.
- O tema é resolvido por convenção a partir de `slug`/`name`, removendo hífens, quando existe uma chave correspondente em `Tenant::PUBLIC_SITE_THEMES`.
- Se não existir tema específico cadastrado, o fallback atual é `saluteimoveis`.

### Lacuna

Criar uma nova conta ainda não cria automaticamente uma folha CSS pública dedicada. Para um tenant como `nova-imobiliaria`, ainda seria necessário adicionar manualmente:

- uma entrada de tema no registry de temas públicos;
- o asset `app/assets/stylesheets/public_site_themes/novaimobiliaria.css`;
- o deploy contendo esse novo asset.

### Direção recomendada

Não gerar arquivos CSS diretamente no botão de criação de conta em runtime. Isso tende a criar asset órfão, dificultar deploy, versionamento e revisão.

O caminho mais seguro é criar um fluxo explícito e versionado de provisionamento de tema, por exemplo:

```bash
rails tenants:public_theme:create[nova-imobiliaria]
```

Esse fluxo deveria:

- normalizar o slug para a chave do tema (`nova-imobiliaria` -> `novaimobiliaria`);
- gerar `app/assets/stylesheets/public_site_themes/novaimobiliaria.css` a partir de um template base;
- registrar o tema em um registry versionado;
- validar se o asset existe antes de permitir salvar o tema;
- manter fallback controlado para `saluteimoveis`;
- incluir teste garantindo que o tenant novo carrega o CSS esperado.

### Possível evolução estrutural

Avaliar mover `Tenant::PUBLIC_SITE_THEMES` para uma configuração mais operacional, como YAML ou tabela administrativa, mantendo validação contra assets existentes. Isso reduziria a necessidade de editar o model para cada novo tenant com site próprio.

### Critérios de aceite futuros

- Criar tema público dedicado por comando ou tela administrativa sem edição manual dispersa.
- Garantir que cada tenant carregue somente sua folha CSS.
- Impedir salvar um tema apontando para asset inexistente.
- Preservar fallback da Salute sem regressão.
- Cobrir o fluxo com spec de model/request.
