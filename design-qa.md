# QA — Fila de atendimento inspirada no NotificaLead

- Referência: `/var/folders/vp/8s97f7610sg5n819krdn7h0m0000gn/T/codex-clipboard-755ea4ca-e374-4e25-bb6e-cfb6b3998dbb.png` (3400×3775 pixels).
- Evidência desktop inicial: `tmp/support-qa/reference-desktop.jpg`.
- Evidência desktop final: `tmp/support-qa/reference-desktop-final.jpg` (1500×1664, DPR 1).
- Evidência mobile: `tmp/support-qa/reference-mobile.jpg` (390×844, DPR 1).
- Normalização: imagem fonte visualizada em 1499×1664; comparação lado a lado no mesmo retorno de ferramenta com implementação em 1500×1664. A densidade original da captura do NotificaLead não foi informada. Não alegar cópia pixel a pixel.
- Estado: operador autenticado, chamado QA encerrado com imagem, pré-perguntas/métricas recolhidas, aba Conversa. A referência tem 352 registros; a aplicação tem três chamados QA reais. Não foram inventados clientes para preencher a lista.

## Comparação e correções

1. P2 inicial: painel estreito e cartões com linha adicional de assunto. Ajustado gutter para 30px, divisão 33%/restante e cartões compactos com nome/conta/estado/responsável. Evidência pós-correção: desktop final.
2. P2 inicial: descrição de chamado ativo/equipe sumia quando recolhido. Movida para o cabeçalho dos painéis, preservando o contexto da referência.
3. P2 mobile: filtros/painéis competiam com a conversa. Seleção recolhe o topo e abre cabeçalho de detalhe compartilhado com voltar, nome e estado. Evidência mobile e verificação DOM: viewport/scrollWidth ambos 390.
4. Comparação final: mesmas regiões funcionais — filtros/chips, contato ativo/equipe, lista lateral, pré-perguntas/métricas, abas, mensagens/anexos e rodapé de estado.

## Superfícies avaliadas

- Tipografia: system-ui e pesos/tamanhos dos componentes Unitymob; hierarquia compacta e truncamento do cabeçalho mobile. Fonte exata do print não identificada; manter o design system existente é intencional.
- Espaçamento: gutters, duas colunas, gaps, cards arredondados e feed rolável conferidos no desktop completo; mobile sem overflow horizontal.
- Cores: tokens Unitymob preservados, verde para resolvido, destaque azul da seleção. Não reproduzida a borda vermelha indiscriminada da referência para evitar sinalizar atrasos sem dados.
- Imagens: anexos reais do QA, com proporção preservada e link de abertura/download. Não substituídos por imagens artificiais.
- Conteúdo: nomes/contas/datas reais do ambiente local. Nota interna separada. Encerrados mantêm histórico e não exibem editor nem atribuição editável (restrição de domínio anterior, intencional).
- P3 residual: ícones decorativos e tonalidades do NotificaLead não copiados; ações possuem rótulos acessíveis no padrão existente.

## Interações e segurança

- Busca autenticada do destinatário na conta, criação ativa pelo formulário, entrega entre aplicativos, edição e remoção sincronizadas, etiqueta persistida e nota interna ausente no cliente comprovadas no QA #3.
- Chips de origem filtraram a lista sem fechar a conversa; contador atualizado.
- Abas testadas no desktop/mobile, retorno à lista no mobile e zero erros no console após navegação verificada.
- 37 testes centrais + 24 testes CRM passaram; cobrem autorização, frames, anexos, áudio, revisões ordenadas, diretório por tenant, replay e edição por autor/admin.

## Limites intencionais

O contato ativo usa o aviso pessoal já existente da Unitymob; não bloqueia o trabalho do usuário com popup obrigatório. Áudio enviado como arquivo; gravação de microfone não incluída. Edição/remoção apenas com chamado aberto e auditoria. Nenhum deploy ou mudança no código do NotificaLead.

final result: passed
