# Direção de Produto da Unitymob

Atualizado em: 12 de julho de 2026

## Objetivo deste parecer

Este documento avalia a direção da Unitymob como produto a partir dos módulos e fluxos atualmente implementados. Ele diferencia:

- o que já está operacional para a Salute;
- o que precisa ser consolidado para atender outras imobiliárias;
- o que representa evolução de produto, e não correção de um fluxo incompleto.

## Síntese executiva

A Unitymob já reúne os componentes centrais de uma operação imobiliária: imóveis, captações, revisão, publicação, leads, WhatsApp, distribuição, agenda, automações, site público, SEO, portais, auditoria e integrações.

O desafio atual não é simplesmente adicionar módulos. É transformar os recursos existentes em uma plataforma configurável, confiável e coerente para imobiliárias com processos diferentes.

As três direções prioritárias são:

1. confiança multi-tenant e observabilidade;
2. políticas operacionais configuráveis por imobiliária;
3. CRM orientado à próxima ação e à conversão.

## Quadro de execução

Este parecer também funciona como fonte de verdade do roadmap. Os estados usados são:

- **Concluído no develop**: implementado, testado e enviado ao branch `develop`;
- **Pendente de produção**: concluído no código, mas ainda sem promoção para `master` e deploy;
- **Pendente**: ainda exige implementação ou decisão operacional.

### Grupo 1 — confiança multi-tenant e observabilidade

#### Concluído no develop

- contrato formal de isolamento multi-tenant e gate automatizado `security:tenant_isolation`;
- CI dedicado ao isolamento, executado em `develop`, `master` e pull requests;
- correções de escopo por tenant em configurações e conteúdo compartilhado;
- proteção das rotas globais exclusivas do System Admin;
- menu do System Admin com acessos às telas globais;
- painel `/admin/system/health` com release, schema, runtime, filas e erros;
- separação entre erros funcionais e ruído de tráfego/bots;
- saúde consolidada por tenant sem expor registros operacionais entre contas;
- limites objetivos configuráveis pelo System Admin;
- monitor automático a cada cinco minutos;
- histórico global e por tenant com retenção de 90 dias;
- alertas por Web Push e e-mail, com deduplicação;
- filtro de histórico por tenant com enforcement exclusivo de System Admin.

#### Pendente de produção

- promover os commits do Grupo 1 de `develop` para `master`;
- executar as migrations de histórico e configuração de saúde;
- validar visualmente `/admin/system/health` em produção;
- confirmar o primeiro ciclo do monitor e a gravação de amostras;
- confirmar entrega real de Web Push e e-mail no ambiente de produção.

#### Pendente

- concluir a análise dos quatro ErrorEvents históricos de mídia ainda abertos;
- acompanhar as primeiras execuções do CI e ajustar dependências de ambiente, se necessário;
- avaliar gráficos de tendência longa depois de existir volume histórico suficiente.

#### Auditoria operacional de 12 de julho de 2026

- produção confirmada na release 346;
- Puma, Solid Queue, Nginx e PostgreSQL confirmados como ativos;
- 14 fingerprints estavam abertos no início da auditoria;
- eventos `20`, `66` e `67` foram encerrados após comprovação: dois eram erros
  de consultas diagnósticas manuais e um era o agendamento antigo da auditoria
  de hierarquia sem tenant, já corrigido na release 346;
- eventos `58` a `64`, exceto o `57`, também foram encerrados após confirmação
  das correções de host para URLs, qualificação de `created_at` na auditoria e
  remoção da consulta manual ao atributo inexistente `error_class`;
- quatro fingerprints permanecem abertos por cautela: dois arquivos ausentes,
  uma transformação de imagem não suportada e uma falha de integridade de mídia.
  Esses eventos dependem de validação dos blobs e do fluxo de transformação antes
  de qualquer encerramento.

### Critério de conclusão do Grupo 1

O Grupo 1 estará concluído quando o pacote estiver em produção, as rotas críticas
estiverem saudáveis, o monitor tiver registrado amostras globais e por tenant, os
canais de alerta tiverem sido comprovados e não houver regressão no gate de
isolamento. Gráficos avançados são evolução posterior e não bloqueiam o grupo.

## Correção de premissa: ciclo de captação da Salute

O ciclo de captação da Salute está operacional e funciona adequadamente no processo adotado pela empresa. Portanto, não deve ser classificado como um ciclo aberto ou incompleto.

O fluxo atual contempla:

1. criação e preenchimento da captação;
2. validação dos requisitos antes da submissão;
3. envio para revisão administrativa, quando essa camada está habilitada;
4. aprovação ou devolução ao captador;
5. limitação dos blocos que podem ser corrigidos após a devolução;
6. notificações internas e, opcionalmente, por e-mail;
7. liberação manual para o site.

Para a Salute, esse desenho é um processo válido e já consolidado. A evolução necessária é de **produtização multiempresa**, não de conclusão do fluxo da Salute.

## `/admin/property_setting/review_workflow` como motor de política

A tela `/admin/property_setting/review_workflow` deve ser tratada como a fonte de verdade do ciclo operacional de captação de cada imobiliária.

Ela já permite configurar:

- quais requisitos precisam estar completos para enviar uma captação;
- se existe aprovação administrativa antes da publicação;
- quem assume captações pendentes quando a revisão é desativada;
- quais blocos o captador pode corrigir após uma devolução;
- notificações internas;
- notificações por e-mail e seus destinatários;
- publicação final manual.

### Princípio de produto

O sistema não deve impor o processo da Salute às demais contas. Cada imobiliária deve escolher seu fluxo dentro de opções seguras e suportadas pela plataforma.

A Salute permanece com sua configuração atual. Outras contas podem optar, por exemplo, por:

- captação com revisão administrativa;
- captação sem revisão administrativa;
- checklist mais simples ou mais rigoroso;
- devolução com edição limitada a determinados blocos;
- diferentes responsáveis e notificações.

### Evoluções recomendadas para o motor de política

#### Prioridade alta

- Exibir claramente o fluxo efetivo resultante da configuração.
- Manter auditoria de quem alterou a política, quando e quais valores mudaram.
- Versionar as configurações para que captações em andamento saibam sob qual regra foram iniciadas.
- Permitir testar ou simular o fluxo antes de ativá-lo.
- Informar quantas captações em andamento serão afetadas por uma mudança.
- Exigir confirmação para mudanças que reatribuam responsáveis ou alterem etapas em andamento.

#### Prioridade média

- Definir revisores por perfil, equipe, loja ou região.
- Configurar prazo esperado de revisão e alertas de atraso.
- Configurar escalonamento quando o revisor não agir.
- Criar variações de checklist por tipo de imóvel ou modalidade.
- Definir quem pode executar a publicação final.
- Permitir que a publicação seja manual ou automática após aprovação, quando a imobiliária desejar.

#### Prioridade futura

- Modelar fluxos diferentes por unidade, marca ou operação dentro do mesmo tenant.
- Criar modelos de fluxo reutilizáveis para onboarding de novas imobiliárias.
- Comparar desempenho entre versões de fluxo sem expor dados entre tenants.

## Jornada do imóvel

A jornada do imóvel está operacional, mas sua leitura pode ser mais integrada. Cada imóvel deveria mostrar, em um único contexto:

- situação cadastral;
- situação da captação e revisão;
- pendências;
- responsável atual;
- qualidade do cadastro;
- status da mídia;
- publicação no site;
- publicação nos portais;
- erros ou rejeições por canal;
- leads e oportunidades gerados.

Essa evolução não substitui o fluxo configurável. Ela apresenta o estado produzido por esse fluxo de forma clara para a operação.

## Central de publicação

A publicação deve evoluir para uma visão operacional por imóvel e por canal:

| Canal | Estado | Última ação | Pendência | Responsável |
|---|---|---|---|---|
| Site | Publicado | Data e hora | Nenhuma | Operação |
| Portal | Aguardando | Data e hora | Processamento | Integração |
| Portal com erro | Rejeitado | Data e hora | Motivo objetivo | Administrativo |
| Compartilhamento | Pronto | Data e hora | Nenhuma | Corretor |

A política de quando publicar continua pertencendo ao fluxo configurado pela imobiliária.

## Workspace por função

### Corretor ou captador

- leads que precisam de resposta;
- captações incompletas ou devolvidas;
- visitas e retornos do dia;
- imóveis sob sua responsabilidade;
- pendências objetivas e próxima ação.

### Gestor

- SLA de atendimento;
- captações paradas em cada etapa;
- revisões pendentes;
- leads sem próxima ação;
- conversão por corretor, origem e imóvel;
- imóveis com problemas de publicação.

### Marketing

- qualidade dos anúncios;
- mídia e SEO;
- publicação por canal;
- campanhas e conversões;
- oportunidades de conteúdo.

### System Admin

- saúde dos tenants;
- isolamento e segurança;
- erros e regressões;
- jobs e filas;
- integrações degradadas;
- uso de armazenamento;
- migrations e releases.

## CRM orientado à próxima ação

O CRM deve conectar leads, WhatsApp, distribuição, tarefas, agenda e automações. Cada lead precisa responder:

- quem é o responsável;
- qual é o estado atual;
- há quanto tempo está sem resposta;
- qual é a próxima ação;
- quais imóveis despertaram interesse;
- quais outros imóveis são compatíveis;
- quais visitas e propostas existem;
- por que o lead foi perdido, quando aplicável.

As métricas prioritárias são tempo até primeiro atendimento, leads sem próxima ação, visitas, propostas, conversão e motivos de perda.

## Integrações como central operacional

Cada integração deve comunicar consequência operacional, e não apenas configuração técnica:

- saudável, em atenção ou indisponível;
- último sucesso e último erro;
- itens afetados;
- volume processado;
- credencial próxima do vencimento;
- teste de conexão;
- reprocessamento seguro;
- histórico filtrável por imóvel ou lead.

## Prontidão multiempresa

Para ampliar a operação além da Salute, a plataforma precisa consolidar:

- onboarding de tenant;
- checklist de ativação;
- branding e domínio isolados;
- configurações operacionais por conta;
- modelos iniciais de fluxo;
- integrações e credenciais por tenant quando aplicável;
- perfis e permissões predefinidos;
- importação inicial;
- limites, consumo e plano contratado;
- exportação e encerramento seguro da conta.

## Sequência recomendada

### Ciclo 1 — confiança e política operacional

- concluir e publicar o pacote atual de isolamento por tenant — **pendente de produção**;
- manter testes cruzados obrigatórios — **concluído no develop, com CI dedicado**;
- consolidar `/admin/property_setting/review_workflow` como motor de política;
- adicionar auditoria e impacto de mudanças de fluxo;
- criar visão de saúde para o System Admin — **concluído no develop, pendente de produção**.

### Ciclo 2 — produtividade operacional

- ficha operacional unificada do imóvel;
- central de publicação;
- workspace por perfil;
- próxima ação do lead;
- SLA de atendimento e revisão;
- central de pendências.

### Ciclo 3 — escala da plataforma

- onboarding de novas imobiliárias;
- modelos de configuração;
- planos, limites e consumo;
- políticas por unidade ou operação;
- inteligência de compatibilidade entre lead e imóvel;
- IA assistiva e auditável.

## O que evitar

- codificar o processo da Salute como regra fixa para todos os tenants;
- criar novos módulos antes de integrar os existentes;
- automatizar publicação sem política explícita da imobiliária;
- alterar regras de captações em andamento sem impacto e auditoria;
- usar IA para decidir etapas críticas sem revisão humana;
- expandir comercialmente o SaaS antes de consolidar onboarding e isolamento.

## Parecer final

A Unitymob não precisa “fechar” o ciclo de captação da Salute; esse ciclo já funciona. A oportunidade de produto é elevar o fluxo existente a um **motor de políticas operacionais configurável por imobiliária**, preservando a configuração consolidada da Salute e permitindo que outras contas adotem processos diferentes com segurança.

O posicionamento recomendado é:

> Uma plataforma operacional imobiliária configurável, na qual cada empresa define seu processo, cada usuário sabe sua próxima ação e cada imóvel possui estado, responsabilidade e publicação rastreáveis.
