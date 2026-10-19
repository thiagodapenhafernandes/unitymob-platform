# Conexão BC: mensuração e previsibilidade — 19/10/2026

## Estado desta entrega

Produção: foi cadastrada na propriedade GA4 431425110 a dimensão de evento **Tipo de negócio**, parâmetro `business_type`. Ela permite analisar os valores já enviados: venda, locacao, venda_locacao, geral. Não houve deploy de código nem nova publicação de GTM nesta etapa.

Preparado localmente para revisão: contrato de lead confirmado no modal compartilhado, para Conexão e Salute e todos os temas. Não existe ainda uma conversão nova validada em produção. A ativação requer também configurar/revisar os containers conforme abaixo.

## Auditoria da conta Conexão BC

| Item | Evidência atual | Consequência |
| --- | --- | --- |
| Fluxo GA4 | URL conexaobc.com, medição G-WX6W71NGHX | Domínio antigo já corrigido na etapa anterior |
| Search Console | Vínculo criado na etapa anterior | Combinar consulta/página com aquisição; não identifica individualmente cada visitante |
| Ads | Dois vínculos existentes: Imobiliária Conexão BC e MCC - Imobiliária Conexão BC2 | Preservados. Vínculo não prova importação correta de conversões nem qual conta deve otimizar campanhas |
| Dimensões | RD Action, RD Filter e RD ID existentes; Tipo de negócio criada nesta etapa | Não removi dimensões legadas. Parâmetros novos precisam de mapeamento explícito |
| Retenção | Eventos: 2 meses; usuários: 14 meses; redefinição por atividade ativa | Explorações detalhadas de eventos têm janela curta. Recomendo avaliar 14 meses para eventos com a política de retenção da empresa; não alterado |
| Eventos principais | Somente purchase listado, sem stream detectado | Cadastro de imóvel não é compra no site. Configurar generate_lead após validar o contrato; não marcar clique como lead |
| Diagnóstico do fluxo | Interface ainda exibe ausência de dados nas últimas 48 h | A etapa anterior comprovou HTTP 204 para coleta e evento de teste. Não afirmar relatórios processados/completos sem rechecagem após processamento |

## Lacunas confirmadas no código

- O modal trata criação, complemento e contato interno como sucesso para preservar atendimento. Somente nova criação deve emitir esta conversão de aquisição.
- O formulário `/contato` dispara webhook, mas não persiste lead nesse controller. A mensagem de sucesso não prova entrada no CRM. Não foi alterado para criar leads silenciosamente.
- Formulários públicos persistem submissão e podem rotear ao CRM por job. Submissão e lead criado são etapas diferentes; o retorno inicial não confirma sucesso do job.
- Rastreador interno de marketing usa `/marketing/events`; não encaminha automaticamente tudo ao GA4.
- Não há nesta entrega integração GA4 de qualificação, visita, proposta e venda do CRM. Esses eventos exigem mapa das etapas e uma identidade de atribuição persistida com consentimento; não deduzir qualificação pelo nome de um botão.

## Alteração de código preparada

1. `LeadsController`: acrescenta `analytics_event` somente quando o intake confirma novo lead persistido. Complemento, contato interno, validação inválida e respostas antigas não anunciam nova aquisição.
2. `lead_capture_controller.js`: encaminha apenas event_id opaco, business_type, código público do imóvel e form_id; remove query/hash da URL explicitamente fornecida ao evento. Aguarda callback das tags, com limite de 700 ms antes de seguir o atendimento. Ausência/recusa/falha do rastreador não bloqueia o fluxo existente.
3. `_tracking_head`: mantém o gate de consentimento e os aliases; admite event_id/form_id e callback no objeto da camada de dados, sem enviar a função à Meta.

O evento não contém ID interno do lead, nome, telefone ou e-mail. O event_id serve para diagnóstico da emissão; não foi implementado armazenamento de correlação com o CRM nem deduplicação universal por GA4. URLs automaticamente coletadas pelo Google e tags legadas exigem sua própria revisão; a limpeza da URL deste payload não garante limpeza global.

Não muda matching, distribuição, formulários, números de WhatsApp, integrações existentes, aparência ou o pacote local de SEO. Uma consulta agregada ao mesmo lead continua no CRM, mas não incrementa generate_lead de aquisição. Se o negócio quiser contar novas consultas como oportunidades, usar evento próprio com definição separada.

Cobertura de temas: `default`, `saluteimoveis`, `conexaoimobiliaria` e `salute_luxury` recebem o mesmo controller e partial compartilhados, sem condição por tema; futuros temas seguem esse contrato.

## Ativação dos containers após revisão

### Conexão — GTM-PFC2LD5G

- Preservar a versão 3 e a compatibilidade com GTM-W942D8JG. Não importar generate_lead ao Ads sem revisar a conversão legada de envio do formulário: ambas podem contar o mesmo contato.
- Criar uma tag GA4 dedicada para evento `generate_lead`, medição **G-WX6W71NGHX**, acionador de evento personalizado com nome exato `generate_lead`.
- Mapear parâmetros de camada de dados versão 2: business_type, property_code, form_id e event_id. Não mapear nome, telefone, e-mail ou objeto completo do formulário. Não usar acionador genérico form_submit.
- Manter as tags de interação existentes separadas. Registrar business_type como dimensão (feito); considerar property_code se a cardinalidade do estoque permitir. form_id é parâmetro padrão de formulário; verificar disponibilidade nos relatórios desejados antes de criar dimensão redundante. Não registrar event_id como dimensão de relatório.
- Preview com criação real controlada em ambiente de teste; um evento para lead novo, zero para repetição/complemento/interno/erro/recusa. Publicar o container e o código em sequência combinada após aprovação, e validar a produção.
- Após recebimento processado, marcar generate_lead como evento principal e revisar importações/contagem no Ads. Nenhuma mudança de lances ou orçamento é parte desta entrega.

### Salute — revisão necessária antes de ativar

No container acessível **Salute Site - Novo / GTM-MK9WQC9P**, workspace 28, encontrei tag `001 | 09 | Google Analytics 4 (Web) | Evento | Lead Form Site`: evento generate_lead, acionador legado Lead Form Site, parâmetros email, nome e whatsapp referenciando variáveis JS. Há também uma tag GA4 server de Lead Form Site e tags de clique CTWA. Isso é evidência de configuração, não confirmação de disparo ou envio de valores pessoais no site atual.

Antes de publicar: identificar o container efetivamente servido pelo loader/Stape em produção; resolver a variável de medição `Var | GA4`; revisar também o destino server. Substituir o gatilho legado da conversão correspondente pelo evento confirmado, revisar/remover parâmetros pessoais destinados ao GA4 e impedir que a versão web e a server contem duas conversões no mesmo destino. Preservar Ads/Meta/RD e as conversões de outras campanhas. Nenhuma dessas tags foi alterada nesta etapa.

## Plano para gerar decisões, não apenas mais eventos

| Etapa | Entrega | Decisão que permite tomar |
| --- | --- | --- |
| 1. Confiabilidade | Aprovar contrato, mapear containers, testar consentimento e duplicação | Saber se o número de leads é utilizável |
| 2. Jornada | Instrumentar visualização de imóvel, busca e busca sem resultado, abertura de formulário, erro categorizado e confirmação | Descobrir páginas/estoque que atraem interesse, mas perdem contatos |
| 3. Resultado comercial | Mapear qualificação, primeiro atendimento, visita, proposta, venda e motivo de perda no CRM | Priorizar origem que traz oportunidades e vendas, não só cliques |
| 4. Histórico e análise | Avaliar retenção e exportação diária para BigQuery; confirmar custos e política antes de habilitar | Comparar coortes, atraso de conversão e sazonalidade sem depender só da interface |
| 5. Operação | Painel por canal, campanha, página inicial, imóvel, cidade e modalidade | Direcionar conteúdo, estoque e mídia pelo retorno observado |

Começar com dados já disponíveis e acrescentar eventos por pergunta concreta. Evitar gravar valores digitados, mensagens e termos de busca potencialmente pessoais. Erros precisam de categorias fechadas, não texto bruto de exceção.

### Indicadores e regras de leitura

- Aquisição: impressões, CTR e posição por consulta/página (Search Console); sessões orgânicas e pagas separadas (GA4). Separar marca e não marca.
- Conversão: leads confirmados / sessões elegíveis, separando consentimento e canais. CRM é referência para total de leads; GA4 representa visitantes mensuráveis e pode subcontar.
- Qualidade: qualificados / leads, visitas / qualificados, propostas / visitas, vendas / propostas. Mostrar volume absoluto ao lado de cada taxa.
- Operação: mediana e p90 do tempo até primeiro atendimento; perdas por falta de retorno; funil por coorte de entrada. Não comparar uma coorte de ontem com outra que já teve meses para comprar.
- Receita: custo por lead qualificado, custo por venda e comissão líquida atribuível, quando custo e receita estiverem reconciliados. Não usar preço anunciado do imóvel como valor de conversão de lead.

Previsão inicial: `sessões previstas × taxa sessão→lead × taxa lead→qualificado × taxa qualificado→venda`. Calcular por canal e modalidade, usando coortes maduras e horizonte declarado. Publicar cenários baixo/base/alto e o intervalo observado, nunca uma promessa de vendas. Sem volume suficiente ou histórico reconciliado, mostrar cenário de planejamento, não previsão estatística. Com menos de 30 casos no recorte, sinalizar amostra pequena e agrupar períodos; 30 não garante confiabilidade.

Alertas propostos para um próximo recorte, ainda não automatizados: queda de recebimento com tráfego ativo; discrepância persistente GA4/CRM fora da linha de base de consentimento; conversão caindo com volume comparável; concentração de buscas sem resultado; demora no primeiro atendimento. Definir limites após observar a linha de base para evitar alarmes falsos.

## Validação e limites

Os resultados finais de testes e o patch isolado estão na entrega do chat. Não foram enviados leads falsos para produção. A suíte ampliada reproduz três falhas já conhecidas nos contratos estáticos do admin. O teste de duplo envio em leads_spec espera um único webhook, mas o fluxo existente também notifica complemento; a mesma falha foi reproduzida carregando o controller de HEAD, sem esta alteração. Não foi mudado o comportamento de webhooks para fazer esse teste passar.

Referência de semântica do evento: https://developers.google.com/analytics/devguides/collection/ga4/reference/events#generate_lead
