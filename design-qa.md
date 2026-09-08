# Unitymob public/site — verificação do redesign

final result: passed

## Referência e escopo

Referências: `public/site/assets/whatsapp-1.png` a `whatsapp-4.png`, fornecidas pelo usuário (1280 × 800 px).
Pedido: adaptar a identidade visual ao site comercial existente; não copiar o conteúdo de WhatsApp para toda a página.
Implementação: `public/site/index.html`, `assets/site.css`, `assets/qualification.css`, `assets/site.js`.
Backup integral conferido byte a byte: `backups/site-before-redesign-20260906-224213.tar.gz`.

## Evidências

Capturas via Codex In-app Browser, viewport desktop 1280 × 800 e mobile 390 × 844, imagens na mesma dimensão CSS (densidade normalizada 1:1):
- `output/site-redesign-qa/desktop.png` — entrada desktop, comparada à referência 1 na mesma inspeção visual.
- `output/site-redesign-qa/mobile.png` — entrada mobile após ajuste de tipografia.
- `output/site-redesign-qa/mobile-tools.png` — aba Imóveis e enquadramento do painel.
- `output/site-redesign-qa/pricing.png` — plano e condições comerciais.
A referência não fornece um layout mobile: empilhamento e foco no lado direito da demonstração são adaptações intencionais.

## Superfícies verificadas

- Tipografia: sans-serif de sistema, títulos fortes, tracking compacto e destaques azuis. Arial é uma aproximação de família; a fonte exata da referência não foi fornecida. Hierarquia e legibilidade verificadas.
- Layout: texto à esquerda e produto à direita na entrada; leitura empilhada no mobile; largura 390 sem overflow horizontal da página. Tabela comparativa conserva rolagem interna.
- Cores: fundo #edf2f7, azul #365f8f, texto #202934 e painéis brancos. Logo original mantido.
- Imagens: as quatro referências originais são reutilizadas sem recompressão; mobile enquadra o painel à direita. Não há imagens quebradas. O CRM da entrada é markup de interface ilustrativa, com indicação de dados fictícios.
- Conteúdo: módulos, público, preço de R$ 3.000, uso operacional normal, custos de terceiros, implantação e perguntas frequentes preservados. Manchetes comerciais condensadas. Documentos legais existentes permanecem intactos nesta alteração.
- Comparação focada: painel do CRM e painel da extensão inspecionados nos screenshots emitidos no browser. O painel da extensão mantém o próprio asset de origem; não foi redesenhado de forma aproximada.

## Interações e verificações

- Quatro abas: cada seleção atualiza imagem, descrição e aria-pressed.
- Calculadora: incremento de R$ 100 levou total de R$ 3.500 para R$ 3.600 e economia de R$ 500 para R$ 600; valor restaurado.
- Diagnóstico: abre, recebe nome fictício e avança à pergunta da imobiliária; fecha. Não houve envio externo. Etapas posteriores herdadas não foram reexecutadas integralmente.
- FAQ: abertura confirmada com aria-expanded=true.
- Navegação por âncoras e destinos legais locais conferidos.
- Console observado sem warnings ou erros.
- Sintaxe dos scripts validada por node --check; assets, IDs únicos, âncoras e git diff --check válidos.

## Histórico de correções

- P2: imagem completa exigia deslocamento lateral no mobile. Corrigido com enquadramento responsivo no painel da ferramenta; evidência mobile-tools.png.
- P2: título e ações ocupavam espaço excessivo no mobile. Fonte ajustada para 44px e botões compactados; evidência mobile.png.
- Sem P0/P1/P2 pendente na inspeção realizada.

## Limites e próximos refinamentos

- P3: fonte exata das referências não identificada; aproximação por fonte local sem dependência de CDN.
- Demonstrações são ilustrativas, não realizam operações no CRM.
- Publicação não executada. Fluxo final de envio ao WhatsApp não acionado.
