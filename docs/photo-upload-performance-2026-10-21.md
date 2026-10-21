# Upload de fotos — investigação e correção local, 21/10/2026

## Limite da investigação

Reprodução no checkout local e banco de testes. Nenhuma conexão de diagnóstico,
alteração de dados, limpeza de fila, retry ou deploy em produção. O relato de
aproximadamente 12 minutos não possui nesta rodada um trace correlacionando
início do envio, resposta HTTP, início/fim dos jobs e conclusão da tela. Portanto,
não há medição que atribua integralmente esses 12 minutos a uma etapa ou prometa
um novo tempo em produção.

## Gargalos confirmados

1. `Habitation#watermark_photos` declarava os mesmos três perfis públicos de
   `photos`, com `preprocessed: true`. O callback de criação do Active Storage
   enfileirava três `ActiveStorage::TransformJob` por original pendente. Esse
   original nunca entra na galeria; `HabitationPhotoWatermarkJob` cria outro blob
   ao aplicar a marca. Suas variantes não são reutilizadas pelo blob final.
   São transformações, downloads e gravações de derivados dispensáveis.
2. A fila `media` é serial por processo, intencionalmente para limitar RSS.
   `ActiveStorage::TransformJob` tem prioridade -10 e
   `Storage::TransformVariantJob` tem -5; a aplicação da marca usava a prioridade
   padrão (0). Assim, os derivados dos próprios originais e o aquecimento público
   podiam passar à frente do trabalho necessário para concluir o upload.
3. O publicador de derivados também aceitava a associação `watermark_photos`.
   Esse fluxo não deve publicar versões do original que ainda aguarda marca.

Tipo do gargalo: trabalho redundante de CPU/I/O e disputa de prioridade na fila.
O browser envia arquivos sequencialmente, acompanha a transferência por XHR e
só declara conclusão quando as fotos saem das pendências. Esse limite protege
memória e isola falhas por arquivo; não foi aumentado ou contornado.

## Mudança preparada

- Remover os perfis públicos apenas de `watermark_photos` e retirar a associação
  da lista de publicação automática de derivados. Um job antigo ainda pode
  executar sua transformação, mas não publicará o derivado enquanto o vínculo
  continuar pendente. Jobs já enfileirados não são cancelados ou apagados.
- Prioridade -20 para `HabitationPhotoWatermarkJob`, antes das variantes e do
  aquecimento. Mantidos worker, número de threads/processos, locks por anexo,
  três tentativas, intervalo, quarentena de integridade e descarte seguro.
- Preservados os perfis/preprocessamento de `photos`, hero, banners e demais
  anexos públicos. O resultado marcado continua em novo blob e a mesma identidade
  do anexo é mantida. A geração de variantes do resultado pelo acesso público ou
  aquecimento existente não foi alterada.

Prioridade das alternativas: primeiro eliminar o trabalho sem utilidade; depois
corrigir a precedência na fila. Upload paralelo, compressão com perda no cliente,
redução de resolução/qualidade e mais workers exigiriam outra avaliação e não
fazem parte desta correção.

## Medição antes/depois

Mesmo teste, 20 PNGs anexados pela associação real, ActiveJob TestAdapter:

| Operação | Antes | Depois |
| --- | ---: | ---: |
| Jobs públicos dos originais pendentes | 60 | 0 |
| Jobs de variantes de uma foto enviada sem marca | 3 | 3 |
| Prioridade de aplicação da marca | padrão (0) | -20 |
| Prioridade dos derivados/aquecimento | -10 / -5 | -10 / -5 |

O teste foi executado antes da correção: falhou nos 60 jobs excedentes e na
prioridade; após a correção passou. É uma medição da quantidade de trabalho e da
ordem de execução, não um benchmark de banda/Spaces nem uma medição de latência
com a carga real de produção.

## Impacto em todas as contas

Mudança sistêmica, sem condicional da Salute. Beneficia contas que solicitam marca
no upload administrativo/captação e remove a preparação inútil das pendências
DWV. Contas sem marca preservam o caminho atual. Configuração, storage, permissão
de publicação e pesquisa do imóvel continuam vinculados à conta.

Há testes com duas contas e testes de configuração estrangeira, foto privada,
falha de publicação, arquivo ausente, retry, idempotência, preservação de ID e
upload sem marca. Hero/banners e todos os temas cadastrados conservam seus
contratos. A mensagem de sucesso continua condicionada à conclusão real, sem
mascarar fila ou falhas. Nenhum markup/CSS/Stimulus foi alterado nesta demanda.

Risco operacional: prioridade não interrompe um job já em execução. Rajadas
contínuas de uploads podem adiar o aquecimento e outras tarefas de mídia. A
concorrência e o consumo máximo de memória não foram elevados. Congestionamento
de rede, arquivos grandes e tempo de ImageMagick continuam possíveis; a melhoria
real em minutos precisa ser conferida depois de uma implantação autorizada.

## Validação concluída

- Reprodução inicial: 3 exemplos, 2 falhas esperadas (60 variantes inúteis e prioridade).
- Regressão final: 115 exemplos Rails, 0 falhas. Inclui upload/status/retomada/permissões, captação, processamento real de imagem, DWV, publicação de derivados e contrato dos quatro temas.
- JavaScript existente de andamento/conclusão e reordenação DWV: 7 testes, 0 falhas.
- `RAILS_ENV=test bundle exec rails zeitwerk:check` e `git diff --check`: aprovados.
- Sem migration, mudança de schema, build CSS ou ajuste de configuração do servidor.
