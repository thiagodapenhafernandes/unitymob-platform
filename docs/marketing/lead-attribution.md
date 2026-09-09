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
