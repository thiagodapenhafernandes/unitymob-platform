# Cadastro de imóveis por categoria

Implementação na branch `codex/cadastro-imoveis-categorias`, baseada em `develop` (`2a88bdf3`). Referência funcional: `mapas_mentais_cadastro_imoveis.html` e o mapa original. O formulário mantém o shell, tipografia, cores, grades, componentes `ax-*`, navegação mobile e fluxos operacionais existentes.

## Grupos e comportamento

| Grupo / categoria | Comportamento |
| --- | --- |
| Imóveis residenciais | Apartamento, Casa, Casa em Condomínio, Chácara, Cobertura, Loft, Sobrado, Sítio e Diferenciado. Preserva cadastro residencial. Campos de terreno disponíveis nas casas; valores antigos de apartamentos permanecem acessíveis. |
| Galpão / Galpão em Condomínio | Tipo de galpão em dropdown, áreas construída e de armazenagem, alturas, operação, layout, classificação, piso/capacidade, zoneamento, elétrica e docas. Checklists de características e infraestrutura conforme mapa. |
| Sala Comercial / Ponto Comercial / Loja | `salas_qtd` aparece como Número de ambientes; `andares_qtd` vai para Visão geral como Número de pavimentos. A infraestrutura fica na aba Características; sua aba separada desaparece. Mesmos campos de armazenamento, sem duplicar inputs. |
| Prédio Comercial | Mantém cadastro unitário comercial e os dados existentes de edifício e capacidade. Não vira empreendimento automaticamente. |
| Casa Comercial / Condomínio Industrial | Preserva os componentes e campos existentes; a troca para galpão ou loja ativa as regras correspondentes. |
| Área / Terreno / Terreno em Condomínio | Lote, quadra, setor, frente/testada, fundo, duas laterais e topografia. Rua interna é informada no complemento do endereço existente, sem uma nova coluna nem sobrescrita automática. Áreas não são calculadas a partir das medidas. |
| Condomínio / Empreendimento | Retira a aba Características e move título, descrição, destaques e IA para Infraestrutura. |

O vínculo com empreendimento conserva a regra existente: trocar o vínculo herda os dados do novo empreendimento; editar sem trocar o vínculo preserva valores preenchidos da unidade. Não foi criada uma segunda implementação dessa herança.

## Campos, validação e troca de categoria

- Grupo fixo depois de definido. `apartamentos` continua aceito como alias legado de `imoveis_residenciais`; abrir ou salvar outros campos não reescreve o grupo antigo.
- Dados técnicos novos opcionais. Quantidades inteiras não negativas; medidas/capacidades positivas. Na edição administrativa, a mesma validação se aplica às quantidades e áreas existentes alteradas, sem bloquear valores legados intocados.
- A opção Outra operação exige complemento. Retirar Outra operação desativa o complemento; antes de salvar, selecioná-lo de novo recupera o texto no formulário.
- Seleções múltiplas: operação, layout, zoneamento e instalações elétricas. Tipo de galpão aparece em dropdown no cadastro administrativo e na captação, mas continua salvo em `caracteristicas`; classificação, piso e alimentação são exclusivos nos checklists existentes; topografia usa seu seletor existente. Conflitos legados não são apagados nem impedem a edição de outros grupos. Classe A e Classe A+ permanecem distintas.
- Mobiliado e Sem mobília são exclusivos, com validação também no servidor.
- Trocar para categoria incompatível pede confirmação quando existem valores preenchidos. Cancelar restaura a seleção. Aceitar oculta/desabilita os campos incompatíveis sem apagar os valores do navegador; voltar antes de salvar os recupera.
- Ao salvar, os valores incompatíveis saem dos campos ativos e ficam no histórico existente. Valores compatíveis permanecem. Se outro campo impede salvar, a instância recupera os valores retirados para reapresentar o formulário.
- A confirmação não contorna permissões: campos bloqueados impedem uma troca que exigiria retirá-los.
- Não há limpeza em massa, conversão de checkbox para número ou migração de conteúdo antigo por suposição. Categorias e topografias antigas continuam disponíveis no registro que já as utiliza.
- Fotos, documentos, status comercial, publicação, condições comerciais, permuta e demais áreas mantêm seus fluxos existentes.

A duplicação de imóveis copia também as dez colunas específicas e os campos antigos reutilizados. O fluxo de captação preserva seu texto legado de dimensões e usa o mesmo dropdown de tipo de galpão, sem coluna nova.

## Permissões

Os campos técnicos entram no registro compartilhado `Habitations::CadastroFieldRegistry`. Perfis antigos com `locked_fields` explícito também recebem os novos bloqueios por padrão. A edição administrativa das permissões registra `category_fields_version: 1`, permitindo liberar os campos deliberadamente. O dono da conta mantém seu acesso existente.

A política é aplicada tanto à interface quanto aos parâmetros recebidos; mostrar novamente uma seção não desbloqueia um campo proibido. As políticas de revisão existentes de apartamentos são preservadas; Diferenciado usa a revisão residencial e Galpão em Condomínio entra nas opções comerciais.

## IA

A geração usa os valores atuais enviados pelo formulário, filtrados pelas permissões. Campos técnicos incompatíveis, dormitórios e demais quantidades inaplicáveis não entram no contexto da geração. O grupo/categoria orienta o texto.

A prévia é mostrada para revisão. Aplicar preenche os campos permitidos do formulário; descartar mantém o texto atual. Nenhuma dessas ações salva ou publica o imóvel. A ação Salvar continua sendo necessária. A geração usa o serviço existente e continua disponível depois do primeiro salvamento do imóvel.

## Banco e implantação

Migration aditiva: `20260911120000_add_category_details_to_habitations.rb`. Dez colunas novas opcionais: área de armazenagem, pé-direito, altura de armazenagem, capacidade do piso, capacidade elétrica, docas, complemento de operação, setor e duas laterais. Constraints protegem medidas positivas e docas não negativas. Frente/testada e fundo reutilizam colunas existentes. Área construída reutiliza `area_util_m2`, já usado pelas importações; nenhum valor antigo é convertido. As oito seleções de galpão/elétrica usam `caracteristicas` e `infra_estrutura`, com as opções antigas preservadas. Quando uma opção nova repete uma opção do checklist oposto, prevalece a antiga; repetições que já existiam e seleções legadas não são removidas automaticamente. Nenhuma coluna antiga foi removida.

Somente o banco local exclusivo `unitymob_cadastro_categories_test` recebeu a migration durante a implementação. Rollback e reaplicação foram executados nesse banco. Produção, banco de desenvolvimento compartilhado e checkout principal não foram alterados. O rollback remove as novas colunas; após uso real, seus valores devem ser preservados antes de uma reversão estrutural.

## Verificação

Comandos na worktree, usando Ruby 3.2.3 via RVM:

```sh
env RAILS_ENV=test DB_NAME_TEST=unitymob_cadastro_categories_test rvm 3.2.3 do bundle exec rspec spec/models/habitation_category_details_spec.rb spec/requests/admin/habitation_category_behavior_spec.rb spec/services/ai/property_content_service_spec.rb spec/services/habitations/field_lock_policy_spec.rb spec/services/habitations/cadastro_field_registry_spec.rb
env RAILS_ENV=test DB_NAME_TEST=unitymob_cadastro_categories_test rvm 3.2.3 do bundle exec rails zeitwerk:check
node test/javascript/habitation_form_category_test.cjs
```

O teste de requisição pode exportar os 22 formulários renderizados ao definir `CATEGORY_FORM_SNAPSHOTS`. O teste DOM usa esses HTMLs reais e `jsdom` (ferramenta de teste externa, não incluída no aplicativo):

```sh
env RAILS_ENV=test DB_NAME_TEST=unitymob_cadastro_categories_test CATEGORY_FORM_SNAPSHOTS=/tmp/category-form-snapshots rvm 3.2.3 do bundle exec rspec spec/requests/admin/habitation_category_behavior_spec.rb
NODE_PATH=/tmp/cadastro-preview-check/node_modules CATEGORY_FORM_SNAPSHOTS=/tmp/category-form-snapshots node test/javascript/habitation_category_dom_test.cjs
```

Resultados da revisão: 49 testes focados aprovados, incluindo cópia dos detalhes, persistência nos campos existentes e ausência de novas opções repetidas entre checklists. Na suíte ampla (314 casos), a expectativa do seletor novo removido foi corrigida e revalidada; permanece a falha anterior descrita abaixo. `zeitwerk:check`, sintaxe JavaScript e `git diff --check` passaram.

Foram exercitadas 158 transições, incluindo campos, abas, reutilização de inputs, Outros, cancelamento, restauração e bloqueios de permissão. A validação visual foi estrutural/DOM; não houve inspeção manual do aplicativo em navegador nesta worktree. Nenhum CSS ou arquivo de tema foi alterado.

A suíte ampla de imóveis apresenta uma falha preexistente no teste do captador DWV: espera o texto `Captador:` no card. Esse teste já falhava antes desta implementação e o card não foi alterado. A expectativa antiga de herança no teste do payload IA foi ajustada para representar uma edição posterior ao vínculo, preservando a regra atual de empreendimento.

## Equipamentos nos dois formulários

Cadastro administrativo e captação compartilham as opções Persianas elétricas e Escada interna em Características, para residenciais e comerciais, incluindo galpões. Ponto de recarga para veículo elétrico fica em Infraestrutura dos imóveis construídos e empreendimentos; terrenos não recebem essa opção própria, mas conservam a infraestrutura herdada do condomínio vinculado. Todos usam os checklists existentes, sem colunas ou migration adicionais. A captação envia também a seleção vazia para permitir desmarcar o último item, preservando os demais campos quando não enviados.

A conversão já existente da captação de empreendimento em unidade vinculada é preservada: o controller valida o empreendimento na própria conta e autoriza internamente a mudança de grupo para residencial. Essa autorização não é aceita por parâmetros; o cadastro administrativo continua com grupo fixo.

Validação dos equipamentos e captação: 119 casos aprovados (118 no lote e o caso de isolamento entre contas reexecutado após corrigir sua preparação). Cobertura de renderização, marcação/desmarcação, persistência, herança e permissões; `zeitwerk:check` e `git diff --check` aprovados. Nenhuma migration adicional executada.
