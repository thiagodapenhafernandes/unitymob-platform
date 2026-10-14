# Correções das quatro lacunas de produto

13/10/2026 — alterações locais, sem commit ou deploy. Complementa a análise por módulo, que descreve o estado anterior às correções.

## Mudanças

1. **Distribuição:** o modo persistido `performance` conserva enum, pesos e algoritmo. A interface agora o apresenta como **Sorteio ponderado**, com pesos manuais e sem aprendizado automático. O helper existente fornece o rótulo; o resumo Stimulus lê o rótulo do formulário em vez de manter outro catálogo. “Ciclos” passa a “Peso”. Nenhuma fila foi rotacionada e nenhuma configuração existente foi migrada.
2. **Matching:** o motor percorre o estoque elegível por tenant em lotes de 500, mantendo em memória apenas os melhores resultados solicitados. Preserva pontuação, tolerância, imóveis ignorados e elegibilidade pública; desempata por recência e ID. Reutiliza `by_city`, `for_sale` e `for_rent`, inclusive para imóveis cujo endereço está na associação. Normalização da modalidade e escolha do preço ficam em `InterestIntelligence::BusinessType`, compartilhado pelo perfil e matcher. A modalidade vem dos dados da conversão, contexto do lead, busca ou sinais inequívocos dos imóveis; sem modalidade determinada, mantém o fallback de compatibilidade. Eventos antigos ligados a imóveis podem fornecer preços por modalidade sem regravar histórico. Endereços são pré-carregados para evitar consultas por imóvel.
3. **Resultados comerciais:** `Lead.won_in_crm(tenant:)` concentra o critério de ganho declarado e é reutilizado pelas consultas Meta e dashboard. Propostas aceitas são contadas separadamente, uma vez por lead. Aceitar proposta preserva status, atividade e automação, mas deixa de enviar automaticamente `Purchase`. O envio configurado na etapa do funil permanece. Indicadores e custos recebem nomes de ganho no CRM, sem alegar receita recebida. A chave interna `sales` é mantida para compatibilidade dos consumidores existentes, agora limitada a ganhos declarados.
4. **Portais:** rejeitados são a diferença entre o estoque da conta e o escopo elegível, com contagem distinta. Os cinco maiores motivos continuam como diagnóstico; a soma dos motivos não determina mais a quantidade de rejeitados. Feeds e regras de publicação permanecem os mesmos.

## Validação

- Suíte ampliada: **412 exemplos, 0 falhas**. Cobre inteligência de interesse, portais, recebimento/distribuição/aceite, model de lead, propostas, dashboard, painel Meta, tracking público e conversões Meta.
- Validação final após complementar contexto de conversão do site: **52 exemplos, 0 falhas** em inteligência, configuração de etapas e conversões Meta. Parte desses testes se repete na suíte ampliada; não somar como quantidade de testes distintos.
- Novas regressões: estoque acima de 250 imóveis, locação em imóvel misto, compra sem sugerir imóvel só de locação, endereço associado, modalidade de busca/conversão, isolamento entre contas, rejeições com motivos sobrepostos, proposta aceita sem ganho, pesos manuais e Purchase configurado na etapa ganha.
- `rails zeitwerk:check`, sintaxe do JavaScript alterado e `git diff --check`: aprovados.
- Não foi executada a suíte completa do repositório nem validação visual interativa ou em produção. Nenhuma migration é necessária. Alterações anteriores de automação e demais WIP foram preservadas.

## Efeito operacional

O painel deixa de inflar ganhos com propostas aceitas. A Meta deixa de receber Purchase pelo simples aceite de proposta; eventos já enviados não são corrigidos retroativamente. Percorrer mais imóveis aumenta o trabalho do matching, com memória limitada por lote e número de sugestões; latência em catálogos reais não foi medida nesta validação local.
