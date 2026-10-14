# UnityMob: análise de produto por módulo

Data: 13/10/2026. Referência: checkout UnityMob Platform, HEAD `7064ba3a`, incluindo alterações locais ainda não commitadas. Auditoria de código e documentação; nenhuma alteração de implementação, banco ou produção. Os caminhos abaixo são relativos à raiz do repositório e as linhas referem-se ao checkout analisado.

## Conclusão

A especialização mais consistente está na cadeia **imóvel → interesse → canal de entrada → corretor elegível → aceite → acompanhamento**. Cadastro, Kanban, agenda, templates, site e IA isolados são recursos comuns. O potencial de diferenciação está em fazer essa cadeia funcionar com contexto imobiliário, políticas por imobiliária e evidência do resultado.

Não há fundamento nesta auditoria para afirmar exclusividade de mercado, aumento de conversão ou retorno financeiro. Código comprova mecanismos implementados, não adoção, disponibilidade em todas as contas ou eficácia em produção. Recursos dependem de configuração, integrações e permissões.

## Critério de classificação

- **Genérico:** capacidade horizontal ou comum aos CRMs imobiliários; continua necessária para vender e operar.
- **Especialização real:** regra imobiliária identificável no código, conectada à operação. Não equivale a exclusividade comercial.
- **Oportunidade:** evolução proposta, com resultado esperado e dependências; não apresentada como funcionalidade já disponível.
- **Prioridade:** P1 fortalece confiabilidade e resultado da cadeia principal; P2 amplia produtividade ou escala após as bases; P3 depende de demanda e validação comercial.

## Inventário por módulo

| Módulo | Funções genéricas | Especialização identificada | Oportunidade / prioridade |
|---|---|---|---|
| Entradas e integrações | Webhooks, OAuth, normalização e filtros | Intake unifica entradas; reconcilia novas consultas com relacionamentos existentes; RD pode bloquear origens antes do recebimento operacional | P1: explicar recebido, filtrado, reconciliado, distribuído e aceito, com correlação e motivo |
| Migração de CRM | Importação e sincronização | Reconciliação de corretor, funil, interesses, tarefas e histórico; preservação de atribuições locais e separação de histórico de entrada nova | P2: onboarding com cobertura, divergências e pendências verificáveis |
| Leads e funil | Cadastro, etapas, qualificações, atividades | Interesses em imóveis ligados ao atendimento e ao responsável; histórico contextual de novas consultas | P1: próxima ação clara e pendência humana, sem ampliar o CRM com mais campos indiscriminadamente |
| Distribuição | Rodízio e pesos | Venda/locação, faixa de preço, campanha/origem, disponibilidade, check-in/loja, pocket, pool e contingências | P1: explicar regra vencedora, inelegibilidade e conflito; simulação usando o motor existente |
| Aceite e recuperação | Responsável e fila | Aceite protegido contra concorrência, janelas e redistribuição quando o atendimento não avança | P1: separar aceite de primeiro contato humano e medir recuperação efetiva |
| Atendimento WhatsApp | Inbox, templates e transferência | Resposta conecta entrada, elegibilidade, aceite e titularidade; revogação de acesso do responsável anterior | P1: resposta → corretor → primeiro contato → visita, com evidência e falhas acionáveis |
| Campanhas WhatsApp | CSV, audiência, envio, status, retry e opt-out | Contexto do corretor e do lead; respostas alimentam atendimento, tarefas e automações | P2: campanhas por interesse, queda de preço e retomada, medidas por visita; audiência salva ainda tem ramo explicitamente não suportado |
| Automações | Editor visual, condições, espera, tarefa e webhook | Eventos de proposta, resposta, matching, falta de estoque e redução de preço; ações com sugestões e contexto imobiliário | P1: poucos playbooks úteis e confiáveis; alterações recentes de concorrência, pausa e simulação estão locais |
| Inteligência de interesse | Perfil e recomendações | Navegação, favoritos e compartilhamento compõem perfil; matching tem razões; alterações de preço acionam reprocessamento | P1: corrigir semântica venda/locação e cobertura antes de ampliar a promessa de inteligência |
| Busca com IA | Texto/voz para filtros | Vocabulário de imóveis, localização, empreendimento e código; sugestões com relaxamento de critérios no fluxo de campo | P2: medir interpretação e recuperação; reduzir divergência entre busca pública e de campo |
| Estoque e empreendimentos | CRUD e filtros | Hierarquia empreendimento/unidade, lote/quadra, identidade de duplicidade e bloqueios por campo/perfil | P1: qualidade, disponibilidade e identidade confiáveis do estoque |
| Captação e aprovação | Formulários e status | Tipos imobiliários e modalidades de locação; revisão de imóveis captados por corretor e política operacional | P2: jornada única e legível da captação à aprovação/publicação; existem mecanismos distintos, não ausência global de aprovação |
| Proprietários | Contatos e relacionamento | Reconciliação Vista/DWV, vínculo com imóveis e limites de edição de dados sensíveis de captação/comissão | P2: qualidade e governança; evitar criar outro cadastro paralelo |
| Mídia e publicação em portais | Upload, galeria, watermark e feed | Fotos locais/DWV/herdadas e elegibilidade por negócio, status, preço, localização e fotos | P1: distinguir apto para feed de publicado no portal; identificar falhas de mídia e rejeições únicas |
| Site e página do corretor | Catálogo, temas, formulários e compartilhamento | Tokens de página personalizada atribuem conversão ao corretor sem login, pelo mesmo fluxo de recebimento | P1: medir compartilhamento → atendimento → visita; preservar distribuição no site normal |
| SEO, conteúdo e navegação | Metatags, sitemap, páginas e tracking | Metadados de imóvel/empreendimento e sinais de navegação usados no contexto comercial | P2: priorizar descoberta e conversão; pontuação SEO isolada não prova demanda |
| Agenda e tarefas | Calendário, lembretes e conclusão | Visita ligada a lead, imóvel e corretor; distinção de tarefas históricas importadas e operação atual | P1: padronizar próxima ação e resultado da visita; reaproveitar agenda, não criar agenda concorrente |
| Propostas | Valores, PDF e status | Proposta vinculada a lead/imóvel/corretor; aceite alimenta eventos comerciais | P1: separar proposta aceita, negócio fechado e receita/comissão recebida |
| Marketing e BI | Dashboards, agrupamentos e resumo com IA | Origem/campanha ligada a qualificação, visita, proposta e etapas do CRM | P1: métricas com semântica explícita e coortes; não prometer ROI financeiro com sinais de funil |
| Extensão e operação mobile/campo | Acesso móvel, contatos e tarefas | Imóveis no fluxo WhatsApp, operações idempotentes; check-in com loja, precisão GPS e sinais antifraude conectado à elegibilidade | P2: reduzir troca de aplicativos e medir tempo poupado; relevância do check-in depende do modelo da imobiliária |
| Governança e onboarding | Contas, perfis, permissões e auditoria | Configuração por tenant, políticas operacionais e provisionamento de conta/dono/domínio | P2: presets e checklist de entrada em operação; governança é base obrigatória, não argumento isolado de exclusividade |
| Plataforma e suporte | Healthcheck, erros, tickets e SLA | Saúde por tenant, integrações e suporte contextual | P1 para confiabilidade do SaaS; P3 para expansão comercial do módulo de suporte |

## Evidências principais

### Entrada, propriedade do lead e resultado

- `app/services/leads/intake.rb:73-121`: recepção central, reconciliação e encaminhamento. Há lock por tenant; isso favorece consistência, mas exige medição de espera antes de qualquer proposta de aumento de capacidade.
- `app/services/rd_station/lead_receiver.rb:23-34`: política de origens antes do intake.
- `app/services/leads/distributor_service.rb:70-137`: seleção, pocket/pool e condições operacionais; `:306-414`: critérios. A escolha de regras e situações sem tipo de negócio merecem análise de ambiguidade; não classificadas automaticamente como erro sem reproduzir uma configuração real.
- `app/models/distribution_rule.rb:168-180`: modalidade `performance` escolhe por sorteio ponderado. Não há aprendizado de conversão nesse método.
- `app/services/leads/acceptance.rb:3-21`: aceite com proteção transacional e escopo.
- `app/services/external_lead_migration/lead_upsert.rb:19-40`: histórico evita distribuição indevida e preserva reconciliação local.
- `app/queries/meta/campaign_funnel_query.rb:68-79`: `sales` combina proposta aceita, etapa ganha ou status concluído. São sinais do CRM, não comprovantes de receita.
- `app/models/proposal.rb:66-77`: aceite de proposta envia marco `sale` à Meta. É necessário definir o contrato comercial desse evento e o nome dos indicadores antes de interpretar como venda efetiva.
- `app/models/appointment.rb:5,14-16,40-56` e `app/models/task.rb:44-65,78-80`: visita contextual, escopo e distinção de histórico operacional.

### Atendimento e execução

- `app/services/whatsapp/response_flow_runner.rb:178-252`: resposta conecta ações comerciais, tarefa e atendimento.
- `app/services/whatsapp/attendance_manager.rb:13-86`: titularidade e mudança de responsável.
- `app/services/whatsapp/service_window_guard.rb:17`: regras de janela.
- `app/services/whatsapp/campaign_audience_resolver.rb:47-52`: ramo de audiência salva não suportado.
- `app/services/automation/event_catalog.rb:20-100` e `app/services/automation/action_executor.rb:23-60`: eventos e ações especializados. A existência do catálogo não comprova todos os fluxos ativos em todas as contas.
- `app/controllers/api/v1/browser_extension/operations_controller.rb:182-218`: idempotência nas operações da extensão.
- `app/services/check_ins/create_service.rb:50-103` e `app/services/anti_fraud/check_ins/analyzer.rb:37-70`: limites e sinais operacionais; suspeita não é prova de fraude.

### Estoque, interesse e publicação

- `app/services/habitations/hierarchy_normalizer_service.rb:10-50`: hierarquia com coerência de tenant.
- `app/services/habitation_duplicate_checker.rb:8-65`: identidade de duplicidade; análise limitada e resultado inconclusivo quando faltam dados.
- `app/services/habitations/media_gallery.rb:13-64`: fontes locais, DWV e herança do empreendimento.
- `app/services/portal/eligibility_scope.rb:7-18`: escopo de publicação. Em `:48-53`, `rejected_count` soma os cinco maiores motivos; pode contar o mesmo imóvel várias vezes e deixar outros motivos fora. Não representa quantidade de imóveis rejeitados únicos.
- `app/controllers/concerns/broker_site_page.rb:15-55`, `app/models/habitation_share_link.rb:31-43`, `app/services/leads/routing_service.rb:7-24`: página, token e vínculo do corretor entram no fluxo comum.
- `app/services/seo/property_metadata_builder.rb:12-62`: metadados contextualizados.
- `app/services/interest_intelligence/matcher.rb:16-26,40-51`: somente os 250 imóveis mais recentemente atualizados do escopo são pontuados; bons imóveis mais antigos podem ficar fora. Em `:98-105`, preço de venda tem preferência sobre locação; o matching precisa reconhecer a modalidade do interesse.
- `app/services/interest_intelligence/profile_builder.rb:11-54` e `app/services/interest_intelligence/property_change_dispatcher.rb:12-35`: sinais do perfil e reprocessamento por preço.
- Busca pública e busca de campo usam caminhos com capacidades diferentes. Não está estabelecida uma busca externa em tempo real na DWV pelo motor examinado; interpretar filtros com LLM não equivale a agente autônomo especializado.

### Gestão e limites comerciais

- `app/services/dashboard/ai_diagnosis.rb:36-68,112-188`: recurso opcional, orçamento e recomendações determinísticas com resumo por modelo externo. Não demonstra modelo proprietário ou inferência causal.
- `app/models/commercial_contract_proposal.rb:15,104-140,186`: contratos de contratação da UnityMob, OTP e evidências. Não são contratos de locação imobiliária, reajustes e repasses.
- `app/services/system/tenant_provisioner.rb:17-35,40-66`: criação transacional de conta, dono e domínio.
- `app/services/system/platform_health_report.rb:39-71`: saúde agregada por tenant. Saúde técnica não substitui evidência de atendimento ou publicação externa.
- Não identifiquei no escopo examinado um ERP completo de locação, conciliação bancária, repasses ou comissão recebida. Esta é uma fronteira de produto, não uma conclusão de que faltam pequenas telas.

## O que é diferencial comercial defensável?

A comparação com documentação oficial mostra que site integrado, distribuição, redistribuição, IA, funil e integrações já são oferecidos no segmento. Kenlo descreve essas capacidades no [CRM imobiliário](https://www.kenlo.com.br/crm-imobiliario); Vista apresenta operação imobiliária e publicação no [site oficial](https://www.vistasoft.com.br/); roteamento e automações também são horizontais, como documentado pelo [Pipedrive](https://www.pipedrive.com/en/products/sales/lead-routing-software). Isso compara ofertas declaradas, não desempenho, qualidade ou equivalência de implementação.

Portanto, os diferenciais potenciais da UnityMob são:

1. **Continuidade operacional:** a entrada não termina no cadastro; chega ao responsável elegível, com contexto e recuperação quando o atendimento falha.
2. **Estoque como parte do atendimento:** interesse, disponibilidade, sugestões explicáveis e mudanças do imóvel podem produzir uma próxima ação comercial.
3. **Migração e políticas por imobiliária:** preservar relações e histórico, configurar a operação e demonstrar que a transição não perdeu responsabilidade ou dados.

Sua defensibilidade cresce com uso recorrente, qualidade dos dados, padrões de operação e resultados comprovados. Complexidade de integração ou quantidade de módulos, isoladamente, não garante vantagem.

## Prioridades e sequência

### Ciclo 1 — confiança na operação e na medição (P1)

**Entregar:** diagnóstico de uma entrada de ponta a ponta; explicação da distribuição; separar aceite e contato humano; corrigir rótulos/contagens enganosos; publicar e verificar os ajustes locais de automação por um fluxo autorizado próprio.

**Reutilizar:** `Leads::Intake`, `Leads::DistributorService`, `Leads::Acceptance`, atividades, eventos de automação, auditoria e queries atuais. Diagnóstico deve observar o motor existente; não criar segundo motor de distribuição.

**Critérios de sucesso:** toda entrada tem estado e motivo verificáveis; gestor identifica pendências sem consultar logs; métricas distinguem resposta automática de humana; `sales` tem definição visível; rejeições de portal contam imóveis únicos. Medir percentis de tempo até atendimento, percentual sem contato e recuperação por contingência. Fixar baseline antes de definir metas numéricas.

### Ciclo 2 — atendimento orientado a imóveis (P1/P2)

**Entregar:** matching correto por venda/locação, cobertura adequada do estoque, disponibilidade confiável e feedback do corretor sobre sugestão. Depois, três playbooks: lead sem contato, novo imóvel compatível e queda de preço. Lembrete de visita pode usar a agenda existente.

**Reutilizar:** `InterestIntelligence::ProfileBuilder`, `Matcher`, reprocessamento e eventos de propriedade; `Automation::EventCatalog`/executor; propostas, agenda e tarefas existentes.

**Critérios de sucesso:** nenhum aluguel comparado com preço de venda; sugestões relevantes não dependem de recência arbitrária; razão da indicação visível; medir sugestão vista/aceita/rejeitada, contato gerado e visita realizada. Evitar mais mensagens automáticas sem opt-out, controle de frequência e relevância.

### Ciclo 3 — onboarding repetível e escala (P2)

**Entregar:** presets de políticas para modos de operação identificados em clientes; checklist de migração, estoque, permissões, canais e teste de recebimento; saúde operacional por conta.

**Reutilizar:** provisionador, integrações, reconciliação/migração, políticas de revisão e relatório de saúde. Não concentrar regras de negócio em um novo painel ou copiar configurações sensíveis entre contas.

**Critérios de sucesso:** reduzir tempo até primeira entrada atendida e primeira publicação validada; operador entende o que está pronto, bloqueado ou dependente de terceiro; histórico migrado não dispara trabalho novo indevido. Configurado e apto não equivalem a ativo e homologado.

## O que não priorizar agora

- Mais variantes de Kanban, dashboards e editor visual sem resolver pendências concretas dos usuários.
- “Agente de IA” genérico ou modelo próprio antes de medir busca, matching e resultado dos playbooks.
- Crescer em temas/site além da manutenção necessária para aquisição e conversão.
- Construir um ERP de locação inteiro a partir da existência de propostas ou contratos da plataforma. Primeiro validar demanda, segmento, responsabilidade financeira e integração com soluções existentes.
- Expandir suporte como produto independente antes de usar os dados para reduzir falhas e custo do próprio SaaS.

## Validação e limites

Foram inspecionados módulos, serviços, models, controllers, queries e testes relacionados, com divisão de leitura por domínio. Os achados principais de matching, métricas de venda, distribuição ponderada e rejeições de portal foram confirmados diretamente no código. Há testes relacionados em recebimento, distribuição/concorrência, aceite, atendimento, matching, publicação e páginas de corretor; sua presença não é execução nem prova de produção.

Não foram executados testes nesta auditoria documental, nem consultadas métricas de adoção, receita, entrevistas, produção ou desempenho concorrente. Os ajustes anteriores de automação têm validação local própria, mas não foram tratados aqui como publicados. A priorização é uma hipótese sustentada pelo código e deve ser calibrada com uso e baseline operacional de clientes.
