# Recebimento nas regras de distribuição

Implementação local de 04/11/2026. Sem deploy, alteração de configurações de clientes ou redistribuição histórica.

O campo **Receber** substitui o rótulo Tipo de negócio. Cada opção tem uma explicação visível abaixo do seletor, atualizada ao selecionar e associada ao campo por `aria-describedby`.

| Opção | Recebe |
| --- | --- |
| Venda | Venda identificada. |
| Locação | Locação convencional identificada. |
| Venda e locação | Venda, locação convencional ou interesse identificado em ambas. |
| Diária | Diária ou temporada identificada. |
| Administrativo | Solicitações administrativas identificadas. |
| Triagem | Natureza ou modalidade não identificada. |
| Todos | Todas as categorias acima, inclusive indefinida. |

Venda e locação não inclui diária, administrativo ou indefinido. A opção da regra não preenche nem transforma a modalidade do contato. Diária considera o imóvel da própria conta, dados estruturados ou texto da entrada; não usa o nome da campanha. A seleção de participantes de Diária usa a área de locação. Administrativo, Triagem e Todos permitem selecionar participantes de ambas as áreas.

## Formulários, filtros e coexistência

- Sincronização automática continua incluindo formulários novos das páginas selecionadas. Exceções não são reinseridas durante sincronizações.
- Formulários excluídos sempre prevalecem, com sincronização ligada ou desligada, inclusive em encaminhamentos automáticos de contingência. A exclusão é local à regra.
- Primeiro são aplicadas conta, regra ativa, origem, escopo autorizado da integração, recebimento e os filtros existentes. Todos não ignora cidades, preços, campanhas ou outros filtros.
- Para uma entrada Meta, uma seleção explícita do formulário tem prioridade sobre uma regra ampla automática compatível. A prioridade existente de filtros específicos continua dentro desse conjunto.
- No salvamento, duas regras explícitas ativas não podem disputar o mesmo formulário com recebimento sobreposto. Recebimentos separados (venda/locação), exclusões e recortes comprovadamente separados de cidade ou faixa de preço permitem coexistência. Filtros livres distintos não provam separação: precisam de formulários separados ou exclusões.
- Conflitos legados ou concorrentes que ainda resultem em mais de uma correspondência ficam pendentes, com `conflicting_rules` e IDs das regras no histórico. Não há desempate pelo menor ID nem desvio pela contingência padrão.
- Um destino escolhido sem candidatos não autoriza tentar outra regra que exclui o formulário. Seguem check-in, horário, represamento, bolsão e contingência configurados.
- A contingência não exige casar os filtros positivos de origem/campanha do destino, conforme seu contrato anterior. Ela respeita Receber e as exclusões de formulário.
- Pocket, fidelização, complemento de consulta, atribuição manual e links de corretor mantêm seus contratos. Um atendimento protegido pode conservar seu responsável sem gerar nova distribuição.

Exemplo de configuração a ser feita pela conta: Equipe vendas com sincronização automática e formulários Notre Dame excluídos; AUGT com esses formulários selecionados explicitamente e Receber = Todos. Para receber todos os contatos desses formulários, não adicionar filtros contraditórios à AUGT. Esta entrega não aplica esse exemplo à produção.

## Contexto e auditoria

A reentrada usa o formulário e a classificação da consulta nova, preservando os campos originais do cadastro. O contexto do ciclo fica em `other_information.distribution_entry`; a atribuição registra o recebimento, categoria, natureza, modalidade e atualização da regra. Contato WhatsApp indefinido ou administrativo não é promovido a comercial só por corresponder a Triagem, Administrativo ou Todos.

As opções existentes conservam seus códigos (Venda 0, Locação 1, Venda e locação 2); as novas usam 3 a 6. Não há migration ou conversão automática de regras existentes para Todos. Antes de publicar, revisar filas existentes que dependiam de Venda e locação para receber entradas indefinidas e sobreposições anteriormente resolvidas por ID. Rollback para código antigo exige antes retirar os novos valores das configurações, sem converter os leads.


## Campanhas Meta por participante da fila

Cada participante tem `allowed_meta_campaign_ids`: vazio significa **Todas as campanhas** e preserva as origens já aceitas pela regra. A seleção múltipla em Campanhas Meta permitidas usa as campanhas sincronizadas (`MetaCampaignInsight`) da própria conta; não libera campanhas de outro tenant. Limpar a seleção volta a todas. Atualizações que não enviam o campo preservam a configuração anterior.

Com seleção, o participante só concorre se o ID exato de `meta_campaign_id` da entrada estiver autorizado. Nome da campanha, UTM ou anúncio não substituem um ID identificado. Entrada sem campanha identificada não é entregue a participantes restritos. Em reentradas, a campanha é capturada em `distribution_entry` para não reutilizar a atribuição histórica de outra consulta.

O filtro antecede rotativo, ponderado, fidelização e seleção de atendimento, e também se aplica a notificações e reivindicações do bolsão e à contingência. Sem elegíveis por campanha, a distribuição respeita a contingência existente; sem encaminhamento, mantém o lead represado, sem responsável, com `distribution_failed/no_eligible_agent_for_campaign`. Não redistribui leads já atribuídos ao salvar a fila. Ao remover um participante, sua configuração naquela fila também é removida.
