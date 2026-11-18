# Atribuição de leads do site

A captura preserva a primeira chegada e a sessão que gerou a conversão em campos independentes de `attribution_data`. A coluna Origem e o dashboard usam a sessão de conversão. A origem funcional (Site, integração, formulário nativo) permanece preservada.

## Evidências

- Google: `gclid`, `gbraid` ou `wbraid`; Microsoft: `msclkid`; TikTok: `ttclid`.
- UTMs com origem e meio pago reconhecido classificam Google, Microsoft, Meta/Facebook/Instagram, TikTok, LinkedIn, Pinterest, X e YouTube. Outras campanhas pagas permanecem como campanha paga.
- `fbclid` isolado indica Meta, mas não comprova anúncio. Redes sociais sem meio pago explícito não são chamadas de Ads.
- Referrer de buscador conhecido, sem sinal pago, permite inferir busca orgânica. A interface escreve **Google orgânico**, **Bing orgânico**, etc.
- Sem evidência externa: direto/origem desconhecida. Domínios são comparados integralmente ou como subdomínios legítimos; identificadores conflitantes não recebem plataforma presumida.

Esses sinais são declarados ou inferidos, não certificados pelas plataformas. Parâmetros podem ser removidos, compartilhados ou alterados. Não há promessa de atribuição perfeita. Nomes podem chegar no payload/UTM ou, para Meta com IDs oficiais e conta vinculada, pelo enriquecimento descrito abaixo.

## Persistência

Após aceite do consentimento existente, a primeira chegada permanece por até 90 dias e a sessão por 30 minutos desde a captura de página/envio. Navegação interna preserva a sessão; nova chegada identificada inicia outra. Sem consentimento, os dados ficam apenas em memória. Recusa limpa a persistência de atribuição. Storage indisponível não impede cadastrar o lead.

Payloads antigos e novos são aceitos. Não há backfill nem reclassificação automática do histórico; o rótulo orgânico explícito também funciona em registros já classificados como `organic_search`.

## Referências

- Google: https://support.google.com/analytics/answer/11242870?hl=en
- Microsoft: https://learn.microsoft.com/en-us/advertising/bulk-service/account?view=bingads-13
- TikTok: https://ads.tiktok.com/resources/help/article/tiktok-click-id?lang=en

## Enriquecimento Meta em segundo plano

Na integração Meta, informe o ID da conta de anúncios e salve. O sistema valida o acesso e mostra o nome retornado pela Meta. Não escolhe automaticamente uma conta entre as disponíveis. Uma conexão sem esse vínculo não enriquece anúncios. Se houver várias conexões elegíveis no tenant sem identificação da conexão de origem, o job não escolhe uma arbitrariamente.

Novos leads Meta com `ad_id`, `campaign_id` ou `meta_leadgen_id` disparam `MetaLeadEnrichmentJob` na fila `sync`. Os parâmetros de anúncio/campanha precisam ser enviados nos links dos anúncios; `utm_campaign` e `fbclid` não são convertidos em IDs. O webhook nativo permite resolver o anúncio pelo leadgen, validando o formulário de uma página da integração.

O job confere a conta retornada pela Meta, salva nomes de campanha/conjunto/anúncio e formulário em `other_information`, e a lista prioriza a campanha enriquecida. Não altera atribuição, corretor, status ou distribuição. A marca `meta_enriched_at` evita consultas após sucesso; falhas da API têm até três tentativas. O cadastro continua se o enfileiramento falhar (com registro técnico no log).

Não há backfill automático. Os leads antigos sem identificadores oficiais continuam exibindo somente os dados disponíveis. A migração `20260909160000` deve preceder a ativação em produção. O worker existente deve consumir a fila `sync`.

## Captura compartilhada dos formulários — implementação local de 17/11/2026

O modal de lead, os formulários públicos (inline ou modal, incluindo landing pages)
e `/contato` usam `Leads::Attribution.capture` para classificar a aquisição com o
mesmo contrato. O controller compartilhado `form-attribution` acrescenta primeira
chegada e sessão de conversão ao `FormData`, em um namespace separado dos campos
personalizados e anexos. Consentimento e cookies de analytics são conferidos pelo
servidor; o formulário não pode declarar identidade, consentimento ou tenant.
Envios sem JavaScript continuam aceitos com o contexto disponível na URL e no
request, sem reconstruir uma primeira chegada que não foi capturada.

Formulários públicos guardam o snapshot no `source.attribution_data` da submissão
e o acrescentam ao webhook existente. Quando o formulário já está configurado
para gerar lead, o job transporta esse snapshot sem recalcular consentimento,
preserva a origem funcional e vincula a sessão de navegação existente. Uma nova
consulta de um contato existente conserva a aquisição original e guarda a nova
atribuição no histórico. Submissões antigas continuam processáveis pelos campos
legados. Não há backfill nem nova conversão de aquisição no retorno da submissão.

`/contato` continua exclusivo do atendimento administrativo pelo fluxo de webhook
existente: recebe atribuição adicional, mas não cria lead comercial nem entra na
distribuição de corretores. Não há alteração de destinos, assinaturas, regras de
distribuição ou ativação de tracking das contas. A camada é compartilhada por todos
os temas atuais e futuros. Esta implementação ainda não foi publicada.

## CAPI — disparos configurados por conta (ajuste local de 25/10/2026)

Na atualização administrativa do lead, o envio ocorre somente quando ele entra em outra etapa com `Evento Meta` preenchido. Usa o valor salvo pela própria conta; nomes de etapas e tipos ganha/perdida não determinam um evento. Em branco, não envia. Alterar somente a qualificação, concluir um compromisso ou salvar novamente a mesma etapa não dispara eventos fixos de CAPI. Qualificação, agenda, auditoria e as demais integrações mantêm seus fluxos próprios.

A configuração de conversões da conta continua definindo ativação, datasets e código de teste. Os destinos não são substituídos pelo sistema. Tokens expirados são excluídos e o sucesso requer confirmação `events_received: 1` de cada destino; o identificador estável é preservado nos retries. Não há reprocessamento nem alteração de mapeamentos existentes. Estas mudanças permanecem locais até publicação autorizada.
