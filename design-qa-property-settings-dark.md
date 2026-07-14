# Design QA — Configurações de imóveis / Busca Inteligente

- Source visual truth: screenshot dark da rota `/admin/property_setting/edit`, aba `Busca Inteligente por IA`, anexado pelo usuário nesta conversa.
- Implementation route: `/admin/property_setting/edit#property-settings-ai-search`.
- Intended viewport: desktop largo, aproximadamente 1440 × 1800 conforme a referência.
- State: tema dark, aba de Busca Inteligente ativa, formulário preenchido.
- Implementation screenshot: indisponível nesta sessão.

## Full-view comparison evidence

Bloqueada. A referência mostra controles claros conflitantes com o shell dark e um grid em duas colunas no qual o painel longo de compartilhamento deixa uma grande área vazia na coluna esquerda. A implementação reorganiza as áreas para `Busca | Acesso`, `Busca | Aliases` e `Compartilhamento` em largura total, mas não foi possível capturar a tela autenticada após a alteração.

## Focused region comparison evidence

Bloqueada porque o navegador interno não está disponível. A inspeção de código confirma:

- quatro áreas explícitas de grid para busca, acesso, aliases e compartilhamento;
- quatro grupos funcionais dentro de compartilhamento;
- controles, hover e foco dark escopados à aba;
- quebra para uma coluna em 1100 px e campos em largura total abaixo de 720 px;
- aviso de privacidade e ação de remover alias migrados para componentes compartilhados.

## Findings

- [P1] A implementação renderizada não pôde ser comparada com a referência.
  - Impacto: contraste real, alturas finais dos painéis e densidade após preenchimento permanecem sem evidência visual pós-correção.
  - Próximo passo: capturar a rota autenticada no tema dark, no mesmo viewport, e comparar a visão completa e as regiões de inputs e compartilhamento.
- [P2] Estados interativos ainda não foram exercitados visualmente.
  - Impacto: hover, foco, toggles, Tom Select e breakpoint de 1100 px podem apresentar diferenças não detectadas pelos contratos estáticos.
  - Próximo passo: validar dark/light, foco, toggles ativos/inativos e larguras desktop/compacta.

## Comparison history

- Evidência inicial: inputs/textarea brancos no dark e grande vazio estrutural à esquerda.
- Correção implementada: contraste dark reforçado, grid por áreas e compartilhamento agrupado em largura total.
- Refinamento estrutural: busca dividida em Recursos, Interpretação/mensagens e Consulta/limites; métricas em grade autoajustável e vazio de aliases padronizado.
- Refinamento compartilhado: o cabeçalho artesanal foi substituído por `ax_workspace_heading`, preservando status da marca e acesso ao fluxo de revisão com o contrato dark/compacto comum às demais áreas.
- Fluxo de revisão: heading e footer passaram aos componentes compartilhados; as quatro etapas usam lista ordenada e o CSS exclusivo foi removido do ERB para `admin/property_review_workflow.css`, carregado somente na rota correspondente.
- Runtime local: a migration `20260714203000_add_catalog_context_limits_to_property_settings.rb` foi aplicada em development e test; a rota deixou de responder 500 por migration pendente e voltou ao fluxo normal de autenticação.
- Evidência visual pós-correção: bloqueada; o runtime retornou `Browser is not available: iab`.

final result: blocked
