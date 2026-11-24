# Funil por tipo de negócio

Cada conta configura seus próprios funis. O tipo do funil define o padrão de Venda, Locação ou Diária; Venda e locação atende ambas as modalidades. Funis sem tipo específico continuam disponíveis para uso manual.

O lead usa a classificação compartilhada `Leads::EntryClassification`: tipo explícito, dados da entrada, formulário e imóvel de interesse. No cadastro manual e no detalhe, o campo **Tipo de negócio** permite informar essa classificação. Não depende do nome do funil, da origem nem do corretor responsável.

- Na criação, uma modalidade identificada seleciona seu funil ativo configurado. Pareamentos explícitos de etapas salvos na integração têm prioridade e são preservados. Um funil já selecionado compatível com a modalidade também é mantido.
- Sem modalidade identificada ou sem padrão específico em uma entrada automática, mantém o fallback existente da conta. Não se rejeitam entradas de integrações por falta de configuração.
- Uma escolha manual explícita sem funil ativo correspondente retorna erro de configuração.
- Quando a modalidade muda, mantém a etapa equivalente por nome normalizado; sem equivalente, exige a escolha de uma etapa do novo funil. O salvamento é atômico.
- Alterações sem mudança de modalidade não redistribuem leads históricos em massa.
- A seleção sempre usa os funis da própria conta. Escolhas de etapa na interface respeitam as permissões existentes.

Diária tem seu próprio padrão (`default_for_daily`), independente de Locação. A migration `20261124120000` cria esse campo sem alterar configurações de contas existentes. Após publicar, o administrador precisa criar ou classificar seu funil como Diária.
