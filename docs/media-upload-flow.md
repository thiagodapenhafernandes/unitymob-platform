# Fluxo de envio de fotos — conferência

O manager existente continua compartilhado entre modal, página de mídia e cadastro.
Fotos de imóveis já salvos entram na fila de envio automaticamente. Cada arquivo
mostra o progresso de transferência; após a recepção, a pendência aparece na grade
com progresso por etapas até a marca e o armazenamento terminarem. O job mantém
a foto original fora da galeria pública e só libera o resultado concluído.

A transferência ocupa 0–25%; recepção confirmada, 25%; aplicação da marca, 50%;
armazenamento, 75%; foto disponível na galeria, 100%. São marcos do fluxo,
não medição do tempo restante. Falhas não contam como fotos salvas.
Os marcos do worker são compartilhados com o processo web em `tmp/photo-processing-progress`
(requer filesystem compartilhado se houver mais de um host), com expiração de uma hora.
O modal mostra um único resumo do lote no rodapé; erros individuais ficam em “Ver motivo”.
A miniatura pendente usa endpoint autenticado, com escopo do imóvel e sem cache público.
Não é necessário clicar Salvar mídia para concluir o envio das fotos. Esse botão
permanece para os demais campos. Fotos com erro de envio são retomadas na miniatura.
O cadastro de imóvel ainda não persistido conserva seu fluxo de formulário.

## Conferência de regressões

- [ ] Upload múltiplo por seletor e arrastar arquivos; limite de 250 MB por seleção.
- [ ] Adicionar fotos enquanto a fila envia outras.
- [ ] Progresso individual; erro individual e nova tentativa.
- [ ] Retomar/descartar pendências da marca; reabrir modal durante processamento no servidor.
- [ ] Marca habilitada/desabilitada e configurações existentes de qualidade, tamanho e transparência.
- [ ] Galeria ampliada e navegação.
- [ ] Ordem por arraste e foto de destaque.
- [ ] Ambiente individual e organização por ambiente.
- [ ] Visibilidade no site e foto interna.
- [ ] Seleção individual/todas, download, exclusão e compartilhamento.
- [ ] Fotos de integrações e fotos herdadas do empreendimento.
- [ ] Classificação das fotos, vídeos, tour 360 e podcast salvos pelo formulário.
- [ ] Permissões por perfil/campo/ação, isolamento por tenant e auditoria.

## Validações automatizadas

Request specs de mídia: modal, campos e controles existentes, upload, ordenação,
visibilidade, ambientes, seleção, download, permissões, pendências e miniatura privada.
Job safety specs: publicação apenas após sucesso, isolamento de conta e não reaplicação.
Testes JS: polling, desconexão, fila com adições durante envio e falha isolada com retry.

## Reels para o Grupo ZAP (VRSync)

No organizador de mídia (página e modal), o campo “Reel para o Grupo ZAP” recebe
um arquivo MP4 ou MOV por imóvel, separado dos links em `videos` e das fotos.
Clique em **Salvar mídia** para enviar; um novo arquivo substitui somente o reel.
O campo respeita as permissões de mídia e o bloqueio de campos do perfil, e o
histórico registra a alteração do anexo. O armazenamento segue o destino de
documentos da conta, com download público somente pelo link assinado do anexo. Não aceita URLs nem IDs de blobs no formulário.

O arquivo deve ter até 80.000.000 bytes (limite conservador de 80 MB), de 10 a 60
segundos e proporção vertical 9:16 (tolerância de 0,001 na razão para arredondamento
em pixels). O Active Storage analisa o arquivo no servidor, considerando a rotação
do vídeo. Enquanto a análise não terminar ou se os requisitos não forem atendidos,
o reel fica fora do XML; reabra o organizador para conferir o estado atualizado.
Um resultado inválido não bloqueia edições dos demais dados do imóvel.

Apenas os feeds `zapimoveis` e `vivareal_vrsync` adicionam um `Item medium="reel"`
ao `Media`. A URL proxy do Active Storage é estável, baixa o arquivo sem sessão
ou URL temporária de storage e segue o host da requisição do feed. Fotos mantêm
sua ordem e destaque; os links de vídeos existentes permanecem intactos. Não há
conversão automática de links do YouTube/Vimeo em reels nem alteração nos outros portais.

Requisitos para ativar em produção: worker ActiveJob/Solid Queue processando a
fila de análise do Active Storage, `ffprobe` instalado no host do worker, storage
acessível pelo web e worker e proxy HTTP permitindo o upload de 80 MB mais o
multipart. Sem metadados válidos, o envio permanece bloqueado. Não há migration
nova; usa as tabelas existentes do Active Storage. A aceitação pelo Grupo ZAP
precisa ser homologada após uma publicação autorizada.

Testes específicos: `spec/models/habitation/portal_reel_spec.rb`,
`spec/requests/admin/habitation_portal_reel_spec.rb` e
`spec/requests/integrations/portal_feeds_spec.rb`. O fixture `portal_reel.mp4`
é um vídeo preto de 10 segundos, 90×160 pixels, sem áudio, gerado localmente
com FFmpeg para testar a análise real sem dependência de download externo.
