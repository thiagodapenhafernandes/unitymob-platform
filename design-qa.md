# Meta Leads — opção 2

final result: passed

- Fonte: /Users/thiagodap.fernandes/.codex/generated_images/01a0fdb8-428d-7312-8d71-b4935dc549ce/exec-acd285f9-4f9b-4109-8db8-e10888f12305.png
- Implementação: /tmp/unitymob-meta-design/desktop.png
- Comparação conjunta: /tmp/unitymob-meta-design/comparison.png
- Mobile: /tmp/unitymob-meta-design/mobile.png
- Viewport desktop: 1440 × 1024 CSS px; screenshot 1440 × 1024, densidade 1. Fonte 1487 × 1058 normalizada para 1440 × 1024, preservando proporção aproximadamente equivalente.
- Mobile: 390 × 844 CSS px e pixels, densidade 1.
- Estado: Conexão, página expandida, formulários reais e pendência de Instagram; sidebar expandida no desktop.

## Comparação

A composição mantém cabeçalho compacto, alerta, quatro abas horizontais e painel de páginas com as duas ações à direita. Sem banner em gradiente ou seções multicoloridas. Símbolos de Meta, Facebook e Instagram via ax_brand_icon e assets já existentes; Bootstrap Icons nas ações funcionais.

- Tipografia: fontes e escala compacta já utilizadas no admin; escala menor que a imagem aceita para seguir o design system real.
- Ritmo: componentes compartilhados, espaçamento previsível e ações que quebram linha no mobile. Abas com rolagem horizontal.
- Tokens: superfícies neutras e azul primário existentes; cores limitadas aos ícones e estados.
- Assets: ícones Bootstrap e logo existente, sem imagens artificiais ou bibliotecas novas.
- Conteúdo: dados reais preservados. A imagem continha checkboxes por formulário, plataforma e ações inexistentes; não foram criados. Seleção continua por página e restrita à impersonação. Tabela mostra nome e criação, preservando paginação Turbo.

## Histórico

- P2 mobile: largura intrínseca da tabela expandia a coluna do disclosure e cortava o estado do Instagram. Corrigido na primitive compartilhada com grid-template-columns: minmax(0, 1fr). Nova captura mobile mostra texto completo, controles dentro da tela e scrollWidth igual a 390.
- Seleção foi movida do disclosure intermediário para o modal compartilhado para manter as ações do painel próximas, como na referência.
- Comparação final conjunta não encontrou P0/P1/P2 pendentes. Referência e implementação têm conteúdo diferente (3 exemplos versus 149 formulários reais), portanto altura da lista não é divergência visual.
- A comparação conjunta permite ler cabeçalho, abas e painel; texto e controles também inspecionados nos screenshots individuais e via accessibility tree.

## Validação

- Quatro abas, hash na URL, formulários carregados e modal de seleção aberto/fechado sem salvar: verificados no browser.
- Mobile: header de detalhe existente mantido; nenhuma rolagem horizontal da página.
- Console: nenhuma entrada de erro na consulta final.
- RSpec da integração: 30 exemplos, zero falhas; inclui permissões, isolamento, seleção e paginação.
- Helper UI compartilhado: 31 exemplos, zero falhas.
- Zeitwerk e assets:precompile: passaram.
- Nenhuma chamada de sincronização, renovação, desconexão ou salvamento executada na conta pelo browser.

## Limites

Não foi realizado deploy. Não foi testado recebimento externo de novos leads; escopo desta entrega é organização visual e preservação dos fluxos existentes.

## Refinamento solicitado e paleta aplicada em 02/10/2026

- Referência adicional: /var/folders/vp/8s97f7610sg5n819krdn7h0m0000gn/T/codex-clipboard-6d73f648-2435-4567-931c-7d30c15d7cb9.png.
- Comparação refinada conjunta: /tmp/unitymob-meta-design/refined-comparison.png.
- Captura final: /tmp/unitymob-meta-design/final.png.
- Mobile refinado: /tmp/unitymob-meta-design/refined-mobile.png (390 x 844, scrollWidth 390).
- Corrigidas escala do heading e ícone, tipografia das abas, padding dos painéis, subtítulo no header, identidade sem caixa e aviso em linha. Formulários precedem Instagram.
- Paleta salva via interface na conta Conexão, após autorização do usuário para concluir tudo: painéis #FBFCFE, cabeçalhos #F8FAFC, texto #202A37; mantidos fundo #EEF2F7, destaque #365F8F e sidebar #FFFFFF. Mensagem de sucesso e tokens na tela Meta confirmados.
- Checks após refinamento: 61 exemplos, zero falhas; assets:precompile e git diff --check passaram.
- Diferenças esperadas: dados e funções reais em vez de checkbox, plataforma e status fictícios por formulário. Ícones nas abas mantidos por solicitação explícita.
- Resultado final após revisão da captura: passed. Sem deploy.

## Ajustes de paginação e orientação
- Formulários fechados por padrão; Turbo lazy só inicia quando o bloco fica visível.
- Lotes de 10, ordenados pela criação no Facebook decrescente e ID como desempate.
- Primeiro lote cria a tabela; demais acrescentam linhas ao mesmo tbody. Verificado no navegador com 30 linhas e um único cabeçalho.
- Pendências incluem caminho de conferência/renovação e nova tentativa; Instagram sem perfil explica vínculo no Facebook.
- Sidebar usa o helper compartilhado de marcas em todas as seções. Assets de Loft, DWV e Leadlovers obtidos dos sites oficiais: https://www.vistasoft.com.br/, https://site.dwvapp.com.br/contato/, https://leadlovers.com/.
- 100 exemplos de Meta, UI, sidebar e catálogo de perfis passaram.

## Meta Ads / campanhas
- Referência: direção já aprovada em Meta Leads, cabeçalho plain, marca oficial, abas underline, tokens e form sections compartilhados.
- Comparação visual: `/tmp/unitymob-meta-design/scroll-final.png` com `/tmp/unitymob-meta-design/campaigns-final.png`; mesma hierarquia, bordas e respiro.
- Navegação por links na primitive studio_nav preserva filtros e mantém os consumidores de abas Stimulus.
- Filtro de período e abas verificados ao vivo; mobile 390x844 sem overflow horizontal da página.
- CRM permanece visível sem insights; valores desconhecidos não aparecem como investimento zero.
- CPM, qualificação, conversão em venda e custos por qualificado/visita derivados dos dados existentes, com metodologia explícita. Alcance único, receita e ROAS não são simulados.
- 74 exemplos passaram: campanhas, helpers UI/campanhas, consulta de funil, job de insights e integração Meta. Zeitwerk e assets passaram.
