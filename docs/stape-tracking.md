# Stape e cliques de WhatsApp

Em **Integrações → Rastreamento → Google Tag Manager**, ative o rastreamento e o carregador Stape. Os parâmetros são isolados por conta; o ID GTM não é obrigatório neste modo. O loader substitui o GTM padrão e só carrega após o consentimento existente do site.

Parâmetros extraídos da imagem fornecida para Salute:

- Domínio: `https://gtm.saluteimoveis.com.br`
- Loader: `https://load.gtm.saluteimoveis.com.br`
- Identificador: `3ceniiuiwsxi`
- Configuração: `dxfrp44=ABxOMD04RCIiTzVPWyRaTx9FQVIYUw0HVAsSGxwBDAAEFwUSAAZHCgYVXRUb`

O código legível fica em `app/views/layouts/_stape_loader.html.erb`. Preserva o tratamento de Safari 16.4+ com cookie `si_uid`; sem esse cookie, usa o loader normal. Não há campo de JavaScript livre no admin.

## Cookie Keeper

Com GTM e Stape habilitados na conta e consentimento aceito, o site chama
`GET /tracking/stape-cookie` antes do loader. Em HTTPS, o Rails cria `si_uid`
aleatório (UUID), preserva o identificador existente e renova a validade para
400 dias. O cookie é Secure, SameSite=Lax e legível pelo JavaScript; a resposta
não pode ser cacheada. A recusa remove o cookie. Sem HTTPS ou sem consentimento,
nenhum identificador novo é emitido, e uma falha de rede não interrompe o loader.

Na Stape, configurar Cookie Keeper com identificador do tipo Cookie e nome
`si_uid`, além de ativar o power-up no container correspondente. Essa configuração
externa não é feita pelo Rails. Cada domínio emite seu próprio cookie; não se
compartilha identidade entre contas por domínio pai inferido.

Referência: https://stape.io/helpdesk/knowledgebase/how-to-choose-user-identifier-type-in-cookie-keeper

### Evidência da Salute e limite da validação

Em 23/10/2026, a consulta somente de leitura à release 839 da Salute e ao HTML
público confirmou os parâmetros acima e o consumo de `si_uid` pelo loader no
Safari 16.4+. Não foi encontrada emissão desse cookie no código publicado.
O endpoint descrito nesta seção é o complemento local para essa lacuna;
não foi publicado. A configuração do power-up na Stape e a validação em Safari
real continuam externas a essa entrega. O anexo da demanda pode complementar
essa conferência posteriormente, sem bloquear a implementação local.

## Separar venda e locação no container

O evento continua sendo `whatsapp_click`, com `habitation_id` e `negotiation_type`:

| Valor | Contexto |
|---|---|
| `sale` | Imóvel de venda |
| `rent` | Imóvel de locação |
| `sale_rent` | Imóvel disponível nas duas modalidades |
| `general` | Contato sem imóvel identificado |

No GTM, crie uma variável da camada de dados chamada `negotiation_type`. Configure dois gatilhos de evento personalizado `whatsapp_click`, um com essa variável igual a `sale` e outro igual a `rent`. Associe cada gatilho à tag/conversão correspondente de venda ou locação. Trate `sale_rent` e `general` separadamente; não atribua intenção de compra a esses contatos.

A modalidade descreve o imóvel; clicar não comprova envio de mensagem ou conversão concluída. A configuração das tags de transporte/conversão no container Stape/GTM é responsabilidade do gestor de tráfego. Verifique duplicação antes de manter Pixel/Google Ads diretos e tags equivalentes no container ativos ao mesmo tempo.

## Validação e publicação

Validar primeiro no dev: salvar e reabrir o formulário, aceitar o consentimento, verificar o loader e clicar em um imóvel de cada modalidade. Confirmar `whatsapp_click` na camada de dados. Depois verificar o recebimento no Preview do GTM servidor e nas plataformas de destino. HTTP 200 do loader não comprova esse recebimento.

A preparação no dev não altera configuração nem publica código na produção. Ao publicar, cadastrar os mesmos parâmetros na conta Salute do ambiente de produção e repetir a validação.
