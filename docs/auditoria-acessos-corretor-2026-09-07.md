# Mapeamento de acessos do corretor — 07/09/2026

> **Regra final posterior:** tarefas e agenda abertas pertencem ao lead e acompanham seu responsável. A exceção intermediária para o responsável antigo foi substituída. Ver [implementação e backfill](lead-activity-ownership-2026-09-07.md). As análises abaixo registram as etapas anteriores.

> **Revisão de impacto posterior:** corrigidos localmente o bloqueio indevido na complementação de proprietário antes do vínculo e o impacto em tarefas antigas atribuídas. Agenda recebe a mesma proteção contra transferência futura do lead. Ver [uso real e impacto](impacto-corretores-acessos-2026-09-07.md).

## Correções aplicadas no checkout

Implementação posterior ao diagnóstico, autorizada nesta tarefa. O diagnóstico abaixo registra a situação anterior.

- Configuração do atendimento WhatsApp exclusiva do dono da conta; sincronização de modelos exige a permissão de integrações. O atendimento do corretor permanece disponível.
- Contratos B2B aparece somente para quem satisfaz a regra administrativa do servidor.
- Negativas de `check_permission!` interrompem a execução também dentro de ações, preservando auditoria e resposta de acesso negado.
- Propostas e vínculos de atividades conferem a interseção dos escopos de leads e comercial. Atividades já atribuídas permanecem operáveis após transferência do lead, sem expor seu painel; a verificação do lead se aplica à criação ou troca do vínculo.
- Propostas validam que imóvel e usuário pertencem à conta do lead.
- Atualização rápida de proprietário exige vínculo com imóvel dentro do escopo ou contexto autorizado de captação/imóvel para completar campos faltantes antes do vínculo; administração mantém o acesso da conta. A busca para evitar duplicações continua disponível.
- Etiquetas/interesses exigem edição; cartões pessoais exigem gerenciamento; publicação pelo captador respeita `publish:captacoes`. A rota alternativa de publicação também carrega e autoriza o registro.
- A edição limitada dos imóveis próprios foi preservada: é uma exceção operacional explícita no código, com travas por campo, e não foi removida nesta correção. Perfis verticais/horizontais continuam seguindo a composição existente.

Validação após os ajustes de rotina: suíte ampliada com **142 exemplos, zero falhas**; cobertura final dos limites do corretor com **22 exemplos, zero falhas**, incluindo isolamento do contexto e do proprietário entre contas; `security:tenant_isolation` com **46 exemplos, zero falhas**. `zeitwerk:check` e `git diff --check` aprovados. Sem commit ou deploy.

Sem commit, deploy ou alteração de permissões persistidas. A conferência dos perfis efetivos do usuário em produção permanece fora desta implementação local.

## Escopo e limite da evidência

Revisão estática do checkout `unitymob-platform`, branch `develop`, base `e998b733`, incluindo alterações locais já existentes. Foram examinados menu lateral, catálogo de permissões, composição de perfis, rotas, controllers e modelos dos fluxos abaixo. Os prints orientam a investigação, mas não comprovam salvamento ou a configuração efetiva do usuário.

Não houve alteração de aplicação, permissões ou produção. Não foram executadas requisições de escrita, testes de exploração ou testes automatizados. Portanto, os achados abaixo descrevem caminhos autorizados pelo código; não afirmam que alguém os utilizou ou que a mesma revisão está publicada. O nome “Corretor” na interface não basta para determinar as permissões reais.

## Como o acesso funciona

- `Profile::PROFILE_PRESETS["Corretor"]` libera dashboard, consulta/mídia de imóveis, criação/edição de leads, gerenciamento comercial, atendimento WhatsApp e captações próprias. Não libera as áreas administrativas em geral.
- `AdminUser#can?` combina permissões do perfil vertical e horizontal com **OU**. Desligar uma permissão em um perfil não revoga a autorização concedida pelo outro.
- O escopo próprio/equipe/todos é calculado separadamente. Ele só protege uma ação quando o controller efetivamente aplica esse escopo.
- O filtro global `AccessControl::Policy` trata IP e dispositivo. A autorização de cada recurso depende dos filtros e verificações de cada controller.
- Os presets são ponto de partida de perfis novos. Alterar o preset não corrige automaticamente perfis existentes.

Referências: `app/models/profile.rb:117`, `app/models/admin_user.rb:297`, `app/controllers/admin/base_controller.rb:294`, `app/services/access_control/policy.rb:16`.

## Achados prioritários

### 1. Alto — corretor configura o atendimento WhatsApp da empresa

O menu e as ações `edit/update` exigem apenas `manage:whatsapp_inbox`, concedido ao corretor padrão. A atualização atinge a integração do tenant, não uma preferência pessoal. O corretor pode habilitar/desabilitar apresentação, exigir apresentação antes de responder, permitir foto e mudar o destino dos botões de atendimento entre inbox e WhatsApp externo.

Recomendação: separar administração do atendimento e operação das conversas. Aplicar a regra administrativa tanto no menu quanto no servidor. Não remover `manage:whatsapp_inbox` do corretor como solução, pois isso também bloqueia atendimento legítimo.

Referências: `app/views/admin/shared/_sidebar.html.erb:403`; `app/controllers/admin/whatsapp_service_settings_controller.rb:5`, `:14`, `:37`.

### 2. Médio — Contratos B2B aparece no menu indevidamente

O link está dentro de `view:comercial`, junto de Minhas Tarefas e Agenda. Porém os controllers de contratos e termos exigem `require_admin_or_administrative_user!`. Para um corretor sem perfil Administrativo, o backend já bloqueia o acesso. O print comprova exposição do link, não acesso aos contratos.

Recomendação: usar na visibilidade do link a mesma regra aplicada ao destino. Preservar Minhas Tarefas e Agenda.

Referências: `app/views/admin/shared/_sidebar.html.erb:166`, `:176`; `app/controllers/admin/commercial_contract_proposals_controller.rb:2`; `app/controllers/admin/commercial_contract_terms_versions_controller.rb:2`; `app/controllers/admin/base_controller.rb:269`.

### 3. Alto — propostas de negociação sem escopo da carteira

Este é o módulo de propostas vinculado ao lead, distinto de Contratos B2B. `set_lead` consulta todos os leads do tenant; `set_proposal` consulta todas as propostas vinculadas a leads do tenant. Nenhum dos dois restringe ao responsável/equipe. Assim, o corretor padrão tem permissão comercial para alcançar por ID formulários, edição, PDF, marcação de envio e exclusão de propostas de outros corretores da mesma conta.

Há ainda ausência de validação de tenant para o `habitation_id` recebido na proposta: o formulário lista imóveis do tenant, mas os parâmetros aceitam o ID diretamente e o modelo não valida essa associação por conta. Isso precisa de teste específico de isolamento antes da correção.

Recomendação: aplicar escopo de carteira nas buscas do servidor e validar as associações recebidas. Definir explicitamente como escopos de leads e comercial se combinam.

Referências: `app/controllers/admin/proposals_controller.rb:2`, `:84`, `:88`, `:96`; `app/models/proposal.rb:15`.

### 4. Alto — negativa de permissão não interrompe algumas ações

`check_permission!` registra a negativa e renderiza/redireciona. Quando é usado como `before_action`, a resposta interrompe a cadeia de callbacks; quando chamado dentro do corpo da ação, não encerra automaticamente o método chamador.

Em `LeadsController`, as ações abaixo chamam o helper e continuam sem `return` ou teste de `performed?`:

- `open_whatsapp_conversation`: criação/obtenção de conversa;
- `activate_whatsapp_template`: criação de mensagem e despacho de envio;
- `archive`: alteração de status e registro de arquivamento;
- `close_deal`: alteração para negócio concluído;
- `schedule_activity`: agendamento operacional.

Esse problema aparece especialmente quando a permissão é retirada do perfil: a negativa pode ser seguida de efeitos de escrita e, depois, erro de resposta duplicada. Permissões de visualização e escopo do lead ainda são exigidas pelos filtros anteriores. Não foi feito envio real para reproduzir o caso.

Recomendação: mover as verificações para filtros que interrompam a ação ou encerrar explicitamente o método após a negativa; testar ausência de escrita e de jobs, não apenas o status HTTP.

Referências: `app/controllers/admin/base_controller.rb:294`; `app/controllers/admin/leads_controller.rb:586`, `:598`, `:714`, `:743`, `:755`.

### 5. Alto — tarefas e agenda podem vincular lead fora da carteira

As listagens e buscas de tarefas/compromissos aplicam escopo do responsável. Contudo, criação e atualização recebem `lead_id` diretamente. Os modelos validam pertencimento ao mesmo tenant, mas não se o corretor pode acessar aquele lead. Assim, uma tarefa/agenda própria pode ser vinculada a lead de outro corretor da mesma conta, com efeitos na timeline e no painel renderizado.

Recomendação: validar o lead associado dentro do escopo autorizado antes de salvar. Preservar o uso normal de tarefas e agenda próprias.

Referências: `app/controllers/admin/tasks_controller.rb:106`; `app/controllers/admin/appointments_controller.rb:99`; `app/models/task.rb:83`; `app/models/appointment.rb:35`.

### 6. Atenção — cadastro rápido de proprietários tem alcance de toda a conta

O corretor padrão não vê o menu Proprietários, mas `manage:captacoes` permite busca, criação e atualização rápida. A busca e a seleção do registro usam o tenant inteiro, sem exigir vínculo com uma captação acessível. Na atualização rápida, o corretor pode alterar e-mail/cidade e preencher telefone quando estiver vazio; não recebe todos os poderes do cadastro completo.

A busca compartilhada pode ser intencional para evitar duplicação. Já a alteração de um proprietário sem vínculo com a captação merece restrição ou decisão explícita de negócio.

Referências: `app/controllers/admin/proprietors_controller.rb:167`, `:229`, `:279`, `:284`, `:312`.

### 7. Atenção — permissões de visualizar/editar/publicar não são uniformes

- Etiquetas pessoais e vínculos de interesse do lead permitem escrita com `view:leads`. Há escopo de carteira, mas retirar `edit:leads` não bloqueia essas ações.
- Cartões pessoais permitem CRUD com `view:whatsapp_inbox`; o cartão da empresa tem proteção adicional e só é editável pelo proprietário da conta.
- Edição de imóvel aceita `edit:imoveis` **ou** vínculo do usuário com o imóvel, além das demais regras de acesso e travas por campo. Retirar a permissão de edição não torna necessariamente os próprios imóveis somente leitura.
- Publicação da captação pelo captador usa `manage:captacoes`, responsabilidade pelo imóvel e condições do fluxo de revisão. O caminho `release_to_site` não consulta `publish:captacoes`, embora essa opção exista no catálogo de perfis.

Recomendação: documentar quais exceções são intencionais e alinhar os controles exibidos à regra efetiva. Não retirar automaticamente a publicação do captador nem sua edição limitada sem definir a regra desejada.

Referências: `app/controllers/admin/lead_labels_controller.rb:2`; `app/controllers/admin/property_interests_controller.rb:2`; `app/controllers/admin/presentation_cards_controller.rb:6`; `app/models/presentation_card.rb:81`; `app/controllers/admin/habitations_controller.rb:2132`; `app/controllers/admin/habitation_intakes_controller.rb:5`, `:384`, `:602`.

### 8. Atenção — sincronização dos templates da empresa liberada ao operador

O botão e `sync_templates` usam `manage:whatsapp_inbox`, portanto o corretor padrão pode enfileirar a sincronização dos templates do tenant. Não é edição de template, mas é uma ação sobre a integração compartilhada. Recomenda-se decidir se deve ficar com administração/integrações.

Referências: `app/views/admin/whatsapp_inbox/index.html.erb:44`; `app/controllers/admin/whatsapp_inbox_controller.rb:10`, `:264`.

## Matriz de menus e funções

| Área | Situação no perfil padrão e no código revisado | Direção recomendada |
|---|---|---|
| Início | Permitido; corretor é direcionado ao início de campo | Manter |
| Imóveis | Catálogo permitido; consulta comercial pode incluir imóveis de outros corretores; dados sensíveis e edição têm regras próprias | Manter catálogo e revisar operações, sem restringir toda consulta a imóveis próprios |
| Leads e funis | Permitidos com escopo de carteira nas rotas principais | Manter; corrigir ações e recursos associados dos achados |
| Bolsão | Visível por `view:leads`; participação tem regras operacionais próprias | Não confundir lista de leads disponíveis com vazamento de carteira |
| Minhas Tarefas / Agenda | Permitidos com escopo comercial próprio | Manter; validar lead vinculado |
| Propostas do lead | Permitidas pelo comercial; escopo de carteira ausente no controller | Corrigir prioridade alta |
| Contratos B2B e termos | Link indevido; servidor exige Admin/Administrativo | Ocultar link para quem não pode acessar |
| WhatsApp / Atendimento | Permitido; conversas filtradas por atribuição ou lead acessível | Manter atendimento; separar funções administrativas |
| Configurações / Atendimento WhatsApp | Permitido indevidamente pela permissão de operação | Restringir menu e servidor |
| Cartões pessoais | Permitidos; cartão corporativo protegido separadamente | Preservar separação pessoal/empresa |
| Templates / Disparos | Sem permissão no preset do corretor | Manter restrição; revisar sincronização via inbox |
| Captações | Permitidas; revisão administrativa bloqueada no preset; publicação depende do fluxo e responsabilidade | Manter operação própria e alinhar controle de publicação |
| Dashboard Captação / Metas | Sem permissão no preset | Manter restrição |
| Distribuição / Automação | Sem permissão no preset | Manter restrição |
| Proprietários | Menu bloqueado; atalhos da captação liberados | Rever alcance da atualização rápida |
| Usuários / Perfis / Lojas | Sem permissões no preset; perfis têm regra adicional de governança | Manter restrição |
| Marketing / Site público / Integrações | Sem permissões no preset | Manter restrição |
| Configuração de imóveis / Fluxo de revisão / Campo | Fora do preset; imóveis e revisão exigem dono da conta | Manter restrição |
| Segurança administrativa / Auditorias | Sem permissões no preset | Manter restrição |
| Meu perfil / Tema / 2FA / Meus chamados / Sair | Funções pessoais, distintas da administração da conta | Manter |

“Sem permissão no preset” não garante bloqueio de todo usuário chamado Corretor: perfil horizontal ou permissões customizadas podem conceder acesso. Esta tabela não substitui auditoria de todos os endpoints mobile/API/ActionCable nem prova de produção.

## Próximos passos propostos

1. Corrigir separação entre configurar WhatsApp e atender; alinhar visibilidade de Contratos B2B.
2. Corrigir interrupção após negativa e escopo de propostas, tarefas e agenda.
3. Definir alcance dos atalhos de proprietários, publicação e exceções de edição; preservar fluxos aprovados.
4. Conferir em leitura, na Conexão, perfis vertical/horizontal e permissões efetivas do usuário do print, além da revisão publicada. Não inferir isso pelo nome exibido.
5. Testar corretor próprio, outro corretor da mesma conta, outra conta, gerente, administrativo e dono: menu, URL direta e escrita. Nos bloqueios, verificar também banco e fila sem efeitos.
6. Comparar o estado de perfis existentes com a política aprovada antes de qualquer ajuste de dados. Alterar somente o preset não basta.

O teste atual de propostas (`spec/requests/admin/proposals_spec.rb`) usa usuário administrador nos cenários examinados; por si só não demonstra isolamento entre corretores. A correção precisa acrescentar esses cenários negativos.
