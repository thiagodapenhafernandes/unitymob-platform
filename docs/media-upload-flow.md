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
