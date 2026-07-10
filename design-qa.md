# Design QA — página pública de imóvel e Google Maps

## Referências

- Organização de conteúdo da página pública da Imobille fornecida pelo usuário.
- Identidade visual e componentes existentes da Salute.
- Viewports validados: 1280 × 720 e 390 × 844.

## Verificações

- A galeria mantém o mosaico Salute e foi compactada para 400 px no desktop.
- No mobile, a primeira dobra segue a sequência galeria, ações, breadcrumb, título, preço e CTAs.
- No mobile, a galeria oferece contador, navegação anterior/próxima, favoritar e compartilhar sem remover a abertura do organizador de fotos.
- Os CTAs da página pública abrem o formulário de lead antes do WhatsApp; demais pontos continuam seguindo a configuração operacional.
- O preço possui uma única ocorrência estrutural e vem antes das características no DOM.
- Vídeo/Tour, Mapa e Rua aparecem como ações compactas abaixo da galeria quando disponíveis.
- A localização apresenta Mapa, Satélite e Rua sem alterar a identidade visual.
- O painel Google > Maps segue a densidade e os componentes do admin.
- A prévia administrativa carrega a integração configurada.
- A localização aproximada é ofuscada no servidor; o HTML não recebe o ponto exato.
- Rua usa coordenadas exatas somente quando liberada globalmente e não bloqueada no imóvel.

## Resultado

P0: nenhum.

P1: nenhum.

P2: nenhum.

P3: a disponibilidade visual da Rua depende da cobertura do Google Street View para o endereço.

final result: passed
