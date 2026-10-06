# Composições do construtor de páginas

Os recursos são opcionais e preservam os padrões das páginas anteriores.

## Biblioteca

Em Blocos → Adicionar seção pronta: Texto + foto, Benefícios, Números, Como funciona, Depoimentos e Chamada final. Os exemplos precisam ser editados antes de publicar. A seção agrupa os blocos seguintes até a próxima seção; seus filhos continuam editáveis e reordenáveis.

Ao criar uma página, os modelos Sobre a empresa, Anuncie seu imóvel e Campanha já combinam estas seções. Não incluem afirmações comerciais ou depoimentos reais por padrão.

## Aparência

- Coleções: sem fundo, suave, contorno ou destaque, além do padrão anterior.
- Aparência e navegação: superfície clara, suave, escura ou da marca; respiro compacto, equilibrado ou amplo; títulos editoriais ou marcantes; entrada suave opcional.
- Cor da marca: preto ou branco escolhido pelo maior contraste WCAG com a cor principal da conta. A prévia e o site compartilham a paleta.
- Capa: imagem de fundo, texto + imagem ou somente texto; ação principal e secundária.
- Mobile: colunas na ordem normal ou invertida; coleções empilhadas, em grade de duas colunas ou carrossel. O padrão anterior continua disponível.
- FAQ: perguntas expansíveis por `details/summary`, sem biblioteca e com navegação por teclado.
- Navegação da página: destinos `#ancora`; configure a âncora no bloco correspondente. Destinos externos não são renderizados nesse componente.
- Movimento: entrada de 450 ms, desativada quando o visitante prefere movimento reduzido.

Os temas Padrão, Salute e Conexão usam as primitives comuns e a paleta da conta. Luxury recebe o mesmo comportamento com seu acabamento editorial. O visual existente da Conexão não muda sem optar pelos novos controles.

## Validação local

Os scripts em `outputs/salute-pages-import/local_builder_examples.rb` e `local_rich_pages.rb` recusam execução fora de development. Criam rascunhos do tenant Salute para testar modelos e os conteúdos enviados. Não publicam páginas nem acessam produção.

Os depoimentos de Anuncie ainda contêm nomes de exemplo da fonte e precisam de revisão. As fotografias dos modelos são enviadas pelo editor; não são apresentadas como imagens reais da empresa.

## Conteúdos Salute para validação local

A recriação estruturada está em `outputs/salute-pages-import/recreate_rich_pages.rb`; a conferência de conteúdo está em `verify_rich_pages.rb`. Ambos recusam execução fora de development. A conta é buscada pelo slug `salute` e validada pelo nome.

- Sobre: capa com etiqueta/CRECI, quatro indicadores, história com citação, duas colunas de serviços, destaque de garantia, canais em etiquetas, missão/visão/propósito, valores, oito marcos e duas ações finais.
- Anuncie: capa com duas ações por âncora, três indicadores, seis benefícios, destaque de garantia, nove canais, quatro etapas, formulário local de sete campos, quatro depoimentos e CTA final.
- FAQ: 14 perguntas em três grupos, categorias múltiplas por pergunta, filtros, busca sem acentos, respostas inicialmente abertas, destaque no grupo Locação e duas chamadas de contato.

Novos controles: etiquetas e selo na capa; etiqueta/divisor na seção; largura editorial de 900 px; quatro colunas e apresentação em etiquetas nas coleções; iniciais e estrelas nos depoimentos; bloco Destaque e chamada com duas ações; filtros/busca/grupos/destaques da FAQ; apresentação editorial e ação WhatsApp opcional no bloco de formulário.

Os filtros, a busca e os acordeões também funcionam na prévia do editor. Ela continua sem executar scripts do conteúdo. O filtro é compartilhado entre o editor e o controller público.

O formulário de validação é próprio, sem webhook ou regra de distribuição. A ação WhatsApp exige campos válidos e abre uma mensagem com os campos visíveis; arquivos e campos ocultos são excluídos. A prévia impede envios. O envio padrão continua usando o fluxo existente de PublicFormSubmission.

Os `href="#"` da fonte foram substituídos pelo WhatsApp/e-mail configurados da conta, `/imoveis` ou `#formulario`. Os nomes de exemplo nos depoimentos foram preservados para revisão. Nenhuma página foi publicada.

## Edição individual: conteúdo e estilo

A seleção identifica seção/bloco, card ou texto. O painel de Conteúdo reúne o campo selecionado, Trix para texto rico e tipografia: fonte local, tamanho, peso, itálico, alinhamento, decoração, caixa, entrelinhas e espaçamento. Estilo reúne fundo, cor/opacidade do texto e borda. Campos de estilo do card não aparecem ao selecionar seu título ou descrição.

Fundos: atual/herdado, sólido, transparente e gradiente linear/radial, com segunda cor, direção e opacidade. Gradiente de texto tem ativação própria; vidro, disponível em blocos e cards, permite desfoque e saturação. Os campos dependentes aparecem apenas quando o efeito está em uso. Cores e bordas básicas dispensam ativação prévia. As cores dos itens usam a mesma primitive `ax-color-control` do restante do admin; sliders sincronizam o campo numérico nomeado.

Os estilos são campos tipados e limitados no catálogo; o renderer também verifica cores, enums e limites. Nenhum campo aceita CSS arbitrário. Valores ausentes mantêm o tema, e elementos explicitamente personalizados têm precedência sobre o container. A geometria de edição usa o mesmo HTML da página salva, sem wrappers adicionais.

O envio do formulário compacta `data` de cada bloco em `data_payload` JSON para evitar o limite de partes multipart em páginas ricas. Prévia estrutural e envio manual compartilham esse caminho. O controller valida o envelope e aplica os mesmos strong parameters, normalização e autorização existentes. Uploads permanecem partes de arquivo; inputs de arquivo vazios não são enviados. O formulário tradicional sem compactação continua aceito.

## Preview local e salvamento explícito

Texto e estilos (cores, tipografia, gradientes, bordas e vidro) são aplicados diretamente no documento do preview. Não há autosave nem renderização Rails por tecla ou movimento de slider. Os inputs continuam sendo a fonte de dados do formulário; Salvar/Salvar e sair consolida no servidor com a normalização e autorização existentes.

Mudanças de estrutura ainda usam o renderizador compartilhado Rails, ao concluir o campo ou executar a ação estrutural. Esse endpoint não persiste dados. Uma renderização estrutural reaplica os ajustes locais pendentes. HTML de texto passa por uma lista de tags/atributos permitidos antes de entrar no canvas e novamente pela validação Rails ao salvar.
