# Preço ao cliente dos disparos WhatsApp

## Fonte e cálculo

A cobrança usa `GET /{waba_id}/pricing_analytics`, com `COST` e `VOLUME`, filtrado pelo número e pelas datas das entregas. A moeda vem de `GET /{waba_id}?fields=currency`. Valores são tratados como decimais, sem arredondar antes da apresentação.

Preço final em reais = custo informado pela Meta × cotação fixa + volume entregue informado pela Meta × adicional Unitymob em reais.

- O cliente vê um único **Gasto total**, já com o adicional embutido. A média por entregue é identificada como média, com quatro casas para reduzir divergência visual de arredondamento.
- Adicional zero usa somente o custo da Meta convertido. Falhas e envios sem confirmação de entrega não entram no volume.
- A cotação é configurável por número e vinculada à moeda de origem. Troca de moeda exige revisar a cotação. Se a conta Meta estiver em BRL, a conversão usa 1.
- O parâmetro legado `cpl_sent_unit_price` passa a representar o adicional por **entregue**, em reais. Valores existentes são preservados; novos números começam em zero. `cpl_fla_unit_price` é preservado no banco para compatibilidade, mas não participa do preço nem aparece no formulário.
- Cotação e adicional são parâmetros atuais, como no formulário anterior; esse relatório não constitui um livro de faturamento histórico.

## Escopo honesto

A API informa custo por número/período/categoria, sem identificar o ID da campanha Unitymob. Por isso o painel financeiro informa explicitamente o número e as datas, incluindo outros disparos e envios avulsos. Não se divide esse custo entre campanhas ou se calcula CPL financeiro com a estimativa antiga. O detalhe de campanha mantém o gasto próprio indisponível quando não há atribuição oficial.

O painel é compartilhado entre listagem e detalhe e carregado em um Turbo Frame. Consulta separada evita bloquear os indicadores operacionais. Cache de dez minutos é isolado por conta, número, WABA, credencial, timezone e período. Alterar cotação/adicional não refaz inscrições na Meta e não depende de invalidar o cache do custo original.

## Indisponibilidade e permissões

HTTP 200 sem custo, resposta parcial, moeda ausente, dados de outro número/período e falhas de rede resultam em **Indisponível**, nunca zero ou tarifa local como substituto.

Na Salute, teste real em 14/11/2026 retornou moeda USD e 7 entregas em 13/11, mas `COST` foi recusado com código 10/subcódigo 2388184, informando cobrança via parceiro. A consulta de `VOLUME` funciona. Nesse cenário o custo oficial depende do parceiro; cotação/adicional não removem o bloqueio da Meta. Não há uso de endpoints privados do painel, cópia de cookies ou permissão alterada automaticamente.

A consulta exige permissão de visualizar campanhas e escopo global dentro da própria conta, pois inclui o número inteiro. Atualizar os parâmetros mantém as permissões de gerenciamento já existentes. Tokens e respostas de erro brutas não são exibidos ou registrados.

## Publicação

Requer migration `20261114120000`, que adiciona cotação e moeda, constraint de validade e muda somente o default do adicional para zero. Sem backfill de valores nas contas. A implementação é compartilhada por todos os tenants.

Referências: https://github.com/meta/facebook-python-business-sdk/blob/main/facebook_business/adobjects/whatsappbusinessaccount.py e https://whatsappbusiness.com/products/platform-pricing/.
