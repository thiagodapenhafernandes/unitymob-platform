# Contexto ampliado de eventos do site e CRM

A opção **Enviar contexto ampliado do site e CRM** fica em **Integrações → Rastreamento → Google Tag Manager**. É desligada por padrão e salva por conta. Não substitui o loader Stape nem altera os destinos, as inscrições de webhooks gerais ou os gatilhos de outras contas.

## Quando ativada

- A página fornece `business_type`, `page_type` e `site_language` antes do loader. Navegação Turbo atualiza o contexto e limpa os dados de imóvel/identidade da página anterior. O container continua responsável pelo `page_view`; o Rails não adiciona um segundo emissor de page views.
- O detalhe de imóvel emite `view_item` após consentimento, com código público no item, ID interno separado, preço numérico, características e localização pública. O contexto de listagem fornece os filtros suportados e o total de resultados. O evento opcional `view_item_list` não foi adicionado.
- `generate_lead` continua restrito a uma nova captura aceita pelo servidor. Complementos, duplicatas, erros e contatos internos não geram outra conversão. Acrescenta `transaction_id` igual ao `event_id` existente, `lead_id`, `lead_channel`, `user_data` e item do imóvel. O UUID já utilizado não foi trocado por outro formato; os consumidores devem usar `lead_id` para correlacionar com o CRM.
- Webhooks Google por etapa recebem modalidade canônica (`locacao`, inclusive para snapshots antigos `aluguel`), `lead_stage`, `lead_channel`, ID interno/código do imóvel, UTMs e identidade original dentro de `user_data`, além de data ISO 8601. IDs/sufixos por lead/marco permanecem os mesmos. Não há regravação de eventos já persistidos.
- O UID inicial continua exato em `utm_content` e `source.utm.utm_content`; novas consultas mantêm a lista de UIDs sem apagar o primeiro. Sem UID, o campo é omitido. O teste administrativo de webhook permite editar `utm_content`.
- Identidade original com telefone válido pode ser entregue sem e-mail; e-mail editado depois não substitui a identidade inicial. Sem identidade original válida, o evento é descartado com `original_identity_missing`. Modalidade indefinida continua impedindo envio. Contas sem a opção mantêm a elegibilidade legada por e-mail original.
- IP, user agent e identificadores de navegação persistidos só entram no bloco `visitor` quando o consentimento de analytics foi capturado como concedido. URLs desse bloco não levam query ou fragmento. Cidade/CEP do visitante não são inferidos da localização do imóvel.
- O fechamento conserva a comissão real informada em `value`/`BRL`; não calcula receita fictícia. Sem comissão, mantém a omissão anterior. O financeiro/operador precisa informar o valor real ao fechar. Eventos intermediários não recebem `value`.
- Venda e locação simultâneas continuam representáveis por `venda_locacao`. Diária no contexto público permanece distinta; nenhum imóvel é convertido para venda por falta de modalidade. O preço é omitido se a intenção de um imóvel misto não estiver determinada.

## Escopo e validação

A camada é compartilhada por todos os temas e temas futuros. Não há hardcode de conta/domínio. O switch usa o componente `ax_switch_field` e o espaçamento já existente no formulário de rastreamento. As outras abas preservam seu valor ao salvar.

A ativação deve ser combinada com o gestor do GTM/Stape: existem eventos e dados adicionais e a interpretação de `property_id` passa a ser ID interno no contrato ampliado, com `property_code` separado. O contrato legado permanece nas contas não ativadas. O endpoint e o segredo do webhook Google continuam sendo os já cadastrados.

A resposta HTTP do receptor não prova disparo de tags nem conversão aceita por Ads/Meta. Para homologar: realizar uma captura controlada com consentimento e UID conhecido; conferir geração única; qualificar por ação; concluir uma visita na agenda; enviar uma proposta; fechar com comissão; correlacionar os IDs no Preview/logs do container. Não simular ações comerciais em leads reais e não reenviar histórico sem autorização específica.
