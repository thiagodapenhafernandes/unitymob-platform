# Imagens públicas: primeiro acesso e preparação no upload

O Squoosh instalado no Mac é a PWA de https://squoosh.app/. Ele serve para
comparar codecs e qualidade localmente; não é um serviço de processamento da
plataforma. A automação usa Active Storage + ImageProcessing/MiniMagick já
instalados, ActiveJob e a fila `media` do SolidQueue.

## Fluxo

1. Upload/importação grava o original, com a associação e storage da conta.
2. Variantes nomeadas `public_web_*`, com `preprocessed: true`, são preparadas
   em background após o commit. Nenhuma compressão roda no salvamento do hero.
3. Hero gera WebP de 640, 900, 1440 e 1920 px; banners, 768 e 1440 px. Ambos
   usam qualidade 82 e removem metadados apenas da derivada. Cards geram WebP
   360×270, 540×405 e 720×540, com qualidade 82 e remoção de metadados.
   A publicação renova a versão do HTML público para retirar URLs antigas dos fragmentos.
4. A derivada de um anexo público pode ser publicada no storage e entregue
   diretamente, sem passar pelo redirecionamento do Rails. A opção da conta
   `public_photos_enabled?` precisa permitir isso. Falha na ACL mantém a rota
   assinada existente; nunca força publicação de documentos ou anexos privados.
5. Preload e hero compartilham URLs e srcsets. Preloads mobile e desktop têm
   media queries distintas, evitando que o celular baixe os dois perfis.

Escopo da preparação: slides/fundos do hero, banners, fotos de imóveis e suas
versões com marca d'água. Blog já possui variantes WebP preprocessed e também
usa a fila de mídia. Imagens de fornecedores externos continuam nas URLs de
origem; não são baixadas nem republicadas automaticamente.

## Compatibilidade e qualidade

A entrada deve ser decodificável pelo ImageMagick instalado: JPEG, PNG, WebP e
outros formatos suportados. Não há promessa de converter qualquer arquivo.
Slides do hero exigem imagem estática raster compatível. SVG/logos, arquivos
privados e documentos mantêm seus fluxos. Transparência é suportada pelo WebP.
Compressão com perdas não equivale a qualidade idêntica; 82 é um ponto inicial,
com o original preservado para comparação e ajustes posteriores.

Novos anexos entram automaticamente. Anexos antigos não disparam o callback
novamente: preparar somente os itens prioritários em lotes pequenos pela fila
de mídia. Não reanexar nem apagar originais para provocar processamento.

## JavaScript e temas

Controllers exclusivos de galerias, mapas e compartilhamento usam o loader
por presença no DOM já existente, inclusive após turbo:frame-load. Carrosséis
começam a preparar até 200 px antes do viewport, em vez de 700 px. Busca,
consentimento e captura de leads mantêm o registro principal.
O fundo do painel de filtros só recebe background-image na primeira abertura,
evitando baixar uma imagem de aproximadamente 420 KB enquanto o painel está fechado.

Padrão, Salute, Conexão e Salute Luxury usam os mesmos perfis e preload;
preservam a própria composição visual. Temas novos herdam o fluxo compartilhado.

## Validação

Os testes cobrem conversão real PNG → WebP, preservação de key/checksum do
original, conta que proíbe publicação, anexo privado, fallback de ACL, URL direta,
upload assíncrono, rollback de upload inválido e todos os temas registrados.

Referência do app: https://github.com/GoogleChromeLabs/squoosh.
