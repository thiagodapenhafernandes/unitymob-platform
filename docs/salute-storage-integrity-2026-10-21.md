# Salute: integridade das fotos e encerramento dos alertas

## Escopo e evidências de leitura (21/10/2026)

- Stage `saluteimoveis`, host `143.110.138.67`, banco `salute_imoveis_v3_production`, release `818`, revisão `bc1615fcd840509ef7220ab2e8da84e7b6703318`.
- Nenhuma alteração remota, deploy, retry, purga ou resolução de evento foi executada nesta investigação.
- 21 blobs com falhas de integridade registradas, IDs `7150..7170`, todos fotos do imóvel interno `407`, código `5224`, tenant `1` (Salute).
- Todos os 21 objetos foram lidos diretamente do Spaces: os bytes divergem do checksum cadastrado. Não é apenas falha de geração de thumbnail.
- Exemplo `7154`: banco 276394 bytes; objeto 238281 bytes. Exemplo `7150`: banco 268191 bytes; objeto 247228 bytes.
- Cadastro dos cinco primeiros blobs: 20/04/2026. `LastModified` dos 21 objetos: `2026-10-21T05:35:13Z` (02:35:13 em Brasília). Esse metadado não identifica autor nem prova quando começou a divergência; alterações de metadados/ACL podem afetar a data no storage.
- Bucket sem versionamento ativo e sem logging de acesso habilitado; auditoria local de blobs não retornou entradas para os cinco primeiros blobs. A URL legada consultada no Vista respondeu HTTP 403. Não foi possível atribuir o autor/comando histórico com essas fontes.

## Como a divergência pode ocorrer

`DigitalOceanSpacesService#upload_with_single_part` ignorava o checksum recebido. Tanto `SpacesImageSync.repair_missing_blob` quanto `Vista::PropertyReconciliationService#restore_missing_blob_from_url` restauram um objeto na chave original usando uma URL externa e o checksum antigo. Se a origem devolve bytes diferentes, o upload era aceito sem atualizar o cadastro. É um caminho concreto de criação da inconsistência, mas não há evidência que atribua a ele a execução histórica deste caso.

A correção valida o checksum localmente em blocos antes do PUT, preservando a compatibilidade sem `Content-MD5`. Upload direto do navegador continua com o contrato existente; não é possível verificar seus bytes no servidor antes do envio pelo browser.

## Por que o contador cresce

- O descarte do `TransformVariantJob` encerra aquela execução, mas não impede outro produtor de criar jobs novos.
- `WarmPublicVariantsJob` não consultava as falhas do original.
- A quarentena por transformação retinha somente dez entradas; uma foto possui mais combinações de variantes.
- A geração de imagem social também podia voltar a processar o original inválido.

A correção compartilhada reconhece falhas antigas e grava uma marca permanente no original após nova falha. Aquecimento, resolução de URL e jobs sociais/de transformação respeitam essa marca. Variantes já disponíveis continuam sendo servidas. A correção não limpa checksums, fotos ou históricos e não transforma um arquivo divergente em válido.

## Acumulados identificados

| ErrorEvent | Ocorrências na coleta | Último contexto |
| --- | ---: | --- |
| 802 | 10823 | TransformVariantJob, blob 7154 |
| 778 | 1511 | TransformVariantJob, blob 7150 |
| 88 | 29 | PrepareSocialImageJob, imóvel 407 |

O fingerprint agrega ocorrências; o último contexto não prova que todas as ocorrências históricas pertencem ao mesmo blob. Não resolver outros eventos por classe indiscriminadamente.

## Tratamento posterior em produção — não executado

1. Publicar a proteção somente quando autorizada. Revalidar os IDs, anexos, tenant e contadores antes de qualquer aplicação.
2. Preservar os objetos atuais e o cadastro dos 21 blobs antes da recuperação.
3. Buscar originais confiáveis em backup ou reimportar a galeria atual do Vista, respeitando identidade e ordenação. Os payloads atuais possuem imagens diferentes dos nomes dos blobs antigos; não casar por posição e não sobrescrever chaves antigas com fotos diferentes.
4. Para backup, exigir correspondência exata de tamanho e checksum antes da restauração. Para uma foto nova aprovada, criar um novo blob com seus próprios metadados e substituir somente o anexo correspondente do imóvel/tenant. Não executar purga dos antigos nesta etapa.
5. Validar abertura do original, geração de variantes e compartilhamento social; verificar visualmente a galeria. Remover quarentena apenas dos originais efetivamente restaurados e validados, ou usar os novos blobs.
6. Após cessar a reincidência e confirmar que os contextos foram tratados, marcar os eventos específicos como resolvidos usando `ErrorEvent#resolve!`. Preservar `occurrences_count`: é histórico, não fila pendente. O relatório de saúde consulta `ErrorEvent.unresolved`, então eventos resolvidos deixam de aparecer nos próximos alertas. E-mails antigos não mudam.
7. Conferir a próxima execução do aquecimento e os próximos alertas. Encerrar o evento não corrige as fotos nem o alerta independente de memória.

**Situação:** correção local preparada; dados e eventos de produção continuam intactos. A recuperação das fotos e o encerramento dos eventos dependem de autorização posterior para modificar produção e de uma fonte de imagens confiável.

## Validação local

- 205 exemplos, zero falhas: jobs de aquecimento/transformação/social, resolver público, adaptador Spaces, controller de compartilhamento, requests de detalhe/compartilhamento, contrato de temas e views públicas.
- Temas `default`, `saluteimoveis`, `conexaoimobiliaria` e `salute_luxury`: cobertos pelo fluxo compartilhado, sem alteração de markup/CSS ou identidade visual.
- `rails zeitwerk:check` e `git diff --check`: aprovados.
- A execução ampliada que incluiu `spec/lib` teve 425 exemplos e três falhas em `spec/lib/admin/dark_theme_component_contract_spec.rb`: quantidade de painéis do formulário de automação, matriz documental de CSS e ausência de `journey_explorer` no inventário de seletores. As views de automação, CSS do admin, documento da matriz e esse spec estão idênticos a `HEAD`; não foram alterados para esta demanda.
- Não houve build CSS porque não houve mudança de CSS/SCSS/JS. Não houve validação visual em produção nem aplicação do procedimento de recuperação.
