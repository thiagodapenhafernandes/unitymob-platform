# Meta — pacote de revisão de 22/10/2026

## Estado e escopo

App Unitymob **1766223014200910**, rascunho **2059260608230481**, não enviado.
Salute: Ads/Lead Ads e retorno CRM → Meta. Conexão BC: Instagram Direct.
Nenhum deploy do piloto central, alteração de domínios, callbacks, tokens, inscrições ou acesso aprovado nesta retomada.

## Pedidos preenchidos no painel

| Pedido | Justificativa | Evidência / estado |
| --- | --- | --- |
| Marketing API Access Tier | Salva com diagnóstico de produção 270, trace e fluxo CRM → Meta | Requisito de chamadas concluído no painel. O formulário não apresenta upload de vídeo. Recebimento CAPI ainda bloqueado. |
| instagram_manage_messages | Salva | Vídeo real CRM respondendo e Instagram recebendo já anexado e confirmado. |
| instagram_basic | Atualizada e salva | Vídeo de 84 segundos anexado; reabertura mostra Visualizar screencast carregado. |
| pages_messaging | Salva; roteiro de reprodução atualizado | Mesmo vídeo completo anexado e confirmado. Página Conexão BC selecionada; chamadas de teste concluídas. |

O vídeo completo mostra envio/resposta e depois perfil conectado e permissões, sem simular funcionalidades. O vídeo inicial de entrada é complementar e permanece local. As caixas novas de concordância de uso permitido não foram aceitas. Marketing Tier tinha concordância anterior marcada, preservada.

## Validação Instagram Conexão BC

Tenant72, @imobiliariaconexaobc, remetente autorizado @tpenh. Lead6793; InstagramMessage1 recebida às15:52:21 e InstagramMessage2 respondida às15:54:21 (Brasília). Resposta recebida na interface Instagram. Isso comprova a demonstração autorizada, não acesso avançado aprovado e não evento natural do monitor.

## Diagnóstico Salute

Ver [diagnostico-salute-270.md](../outputs/meta-review-2026-10-22/diagnostico-salute-270.md).
Token válido do app correto, ads_management concedida e conta de anúncios visível. Meta bloqueia o teste CAPI por nível de desenvolvimento da Ads API (270). A leitura do dataset retorna Missing Permission (100), a conferir após tier/atribuição. Não houve conversão real nem configuração persistida.

## Acessos aprovados preservados

whatsapp_business_messaging, pages_show_list, pages_manage_metadata, pages_manage_ads, business_management, pages_read_engagement, public_profile, leads_retrieval, ads_management e whatsapp_business_management. Renovação permanece pendente de declaração; nenhum acesso foi removido.

## Instruções e acesso do analista

Roteiro consolidado em instrucoes-analista.txt, com os dois fluxos separados e resultados atuais. Conta exclusiva ainda não criada nem senha compartilhada. O código atual exige manage:integracoes na tela Meta, permissão agrupada que inclui outras integrações; não representa isolamento só aos dados de demonstração. Não conceder usuário administrador de produção. A conclusão usa os perfis existentes: leads view/edit com scope=own e sem Integrações. Atribuir apenas o lead de demonstração ao usuário exclusivo; para identificação e estado da conexão, usar os vídeos anexados. Os testes comprovaram resposta no próprio lead e bloqueio de Integrações e de leads de outro responsável/tenant. Não foi necessário um módulo paralelo de concessão ou demonstração; o rascunho dessa estrutura foi removido antes de migration/deploy. A ativação do usuário e o requisito de testador Facebook continuam pendentes.

## Tratamento de dados — fatos conferidos e revisão necessária

- Responsável pré-preenchido no painel: TMIS TECNOLOGIA DA INFORMACAO LTDA, Brasil. Confirmar razão social/papel contratual; dados comerciais são tratados sob instrução da imobiliária conforme documentação local.
- Cadastro prévio de prestadores contém somente UNITYMOB/Brasil e não descreve toda a infraestrutura comprovada.
- Metadata dos servidores: Salute sfo2; Conexão BC e gateway nyc1. As duas aplicações usam do_spaces, região sfo3 (incluindo support_region); banco configurado local. São regiões dos EUA. Isso impede afirmar processamento exclusivamente no Brasil.
- Proposta: incluir o fornecedor de infraestrutura DigitalOcean com função de hospedagem/banco/arquivos e EUA, conferindo pessoa jurídica contratada, backups e demais processadores aplicáveis antes de atestar. Não presumir que todo recurso opcional OpenAI/Firebase recebe Dados da Plataforma sem inventário do fluxo.
- A declaração prévia de que não houve pedidos de segurança nacional nos últimos12meses e a resposta Nenhuma das opções acima sobre políticas para autoridades dependem do responsável. Backend não comprova ausência de solicitações nem processos jurídicos.
- Confirmar lista jurídica de prestadores, países e contratos/DPA. Não aceitar declarações ou termos para tornar a tela artificialmente completa.

## O que impede chamar o pacote de pronto para submissão

1. Aceites formais de uso permitido e renovação dos acessos atuais.
2. Validação pelo responsável das declarações de autoridades e cadastro de processadores/países.
3. Acesso de análise restrito, testado, e requisito de testador Facebook real solicitado por pages_messaging.
4. Recebimento Salute permanece não comprovado até liberação do tier e validação de acesso ao dataset. A justificativa expõe esse bloqueio em vez de alegar êxito.

Nada enviado para análise. Não houve deploy nem alterações do piloto central. Nenhum código de aplicação foi alterado nesta retomada; validação foi o teste real Instagram, upload/reabertura dos anexos e consultas/teste CAPI no backend.

## Reaproveitamento e testes

41 exemplos passaram: spec/requests/admin/leads_instagram_reply_spec.rb, spec/requests/admin/meta_integrations_spec.rb e spec/services/instagram/reply_spec.rb. Foram adicionados três cenários negativos/positivos do perfil restrito no teste existente de resposta Instagram. Não houve alteração de código de negócio, schema ou UI para criar um mecanismo duplicado. Perfis, convites, revogação e atendimento existentes serão reutilizados; convite não foi enviado nem usuário ativado nesta etapa.
