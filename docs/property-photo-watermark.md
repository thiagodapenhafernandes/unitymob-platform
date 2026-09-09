# Marca d'água no upload de fotos

Novas fotos enviadas com aplicação de marca solicitada entram em `Habitation#watermark_photos`. Essa associação não participa das galerias, compartilhamento ou imagens do site. Uploads sem marca continuam em `photos`. Importações Vista/Loft e fotos existentes não são reprocessadas automaticamente.

`HabitationPhotoWatermarkJob` usa a fila `media`, configuração da mesma conta e lock por anexo. Após converter e armazenar a imagem, respeita `public_photos_enabled?` e transfere o anexo para `photos`, preservando seu ID. A original é descartada pelo `Storage::SafePurgeJob` após 15 minutos, somente se não estiver mais vinculada.

O job tenta até três execuções, com intervalo de 30 segundos. Falhas de uma foto não interrompem as demais do lote. Metadados `watermark_status` e `watermark_error` permitem acompanhar a pendência. Reexecuções ignoram resultados já marcados. Falta da marca e falta da foto original têm mensagens distintas.

O gerenciador de mídia consulta o status a cada três segundos enquanto houver processamento e atualiza a galeria ao concluir. Na captação, as etapas Fotos e Revisão mostram as pendências e oferecem atualização e retomada. Tentar novamente e remover uma pendência respeitam as permissões e o escopo do imóvel/captação. A retomada usa a configuração atual da conta.

A marca aceita PNG, JPEG e WebP de até 5 MB e 25 megapixels, com validação do conteúdo em novos uploads. Configurações existentes não exigem download da marca a cada salvamento de outros campos. O tamanho é proporcional à largura da foto, sem mínimos ocultos; a margem nos cantos corresponde a 3,5% dessa largura. A prévia segue os mesmos critérios, sem sombra artificial.

## Operação

- Manter o worker `media` ativo e ImageMagick disponível.
- Se a marca estiver ausente no storage, enviar novamente seu arquivo em Configurações de imóveis e retomar as fotos pendentes.
- Se a foto original estiver ausente, remover sua pendência e enviar a foto novamente.
- Fotos e falhas anteriores à implantação não são alteradas por backfill. Não reaplicar automaticamente a marca em acervos importados.
- Não é necessária migration: pendências usam os anexos e metadados existentes do Active Storage. Em rollback, pendências permanecem armazenadas e exigem retomar a versão que as processa.
