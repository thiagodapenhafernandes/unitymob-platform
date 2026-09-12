# Inteligência de Interesse no lead

O bloco usa os componentes compartilhados do admin. Leitura, origem, compatíveis e favoritos começam fechados em desktop e mobile. Navegação permanece visível, com sete linhas iniciais e expansão do histórico carregado. Não duplica ações de contato, agenda ou seleção.

## Leitura operacional

`InterestIntelligence::Journey` consulta registros estruturados, sem chamar OpenAI ou alterar o lead. A confiança existente continua representando clareza do perfil, não intenção de compra. O novo badge é uma leitura operacional separada do resumo de IA já usado pelas automações.

Precedência da leitura:

1. Fechamento/arquivamento: ciclo encerrado. Navegação ou acesso a seleção após o encerramento indica “Avaliar retomada”, sem reabrir o lead.
2. Último contato sem interesse: “Revisar interesse”, salvo proposta atualizada posteriormente.
3. Pedido de retorno acompanhado de próximo compromisso futuro: “Retorno combinado”.
4. Proposta enviada, visualizada ou aceita, ainda válida: “Em negociação”. Envio não equivale a aceite.
5. Visita futura agendada ou realizada nos últimos 14 dias: estado correspondente. Agendamento não equivale a confirmação.
6. Interesse declarado em seleção nos últimos sete dias: quente.
7. Conversa registrada nos últimos 14 dias, pesquisa no site ou abertura de seleção nesse período: morno.
8. Histórico sem sinais recentes de avanço: frio. Ausência de qualquer sinal: aguardando sinais.

Tentativas sem resposta não aquecem o lead. Comentários e registros importados são exibidos como evidência; texto livre não é interpretado automaticamente como intenção, orçamento ou prazo. Falta de imóvel compatível não representa desinteresse. Os prazos acima são regras operacionais explícitas, não um modelo validado de probabilidade de fechamento.

## Origem e histórico

Preserva a atribuição existente de primeira origem/conversão, com campanha quando registrada. A navegação posterior e as aberturas de seleções são apresentadas separadamente dos registros do corretor. O vínculo da sessão não pode ser transferido a outra conta ou outro lead.

O frame carrega até 100 eventos recentes de navegação e 100 de seleção; a conversão é incluída com os dados reais de origem. Registros anteriores permanecem no banco. A verificação de navegação anterior à conversão consulta o histórico, não apenas a amostra carregada.

## Favoritos

O site envia o estado atual dos favoritos do navegador usando o rastreamento existente e respeitando o consentimento. O servidor valida a conta, registra inclusões/remoções e mantém a última lista recebida na sessão. Repetir o envio não duplica eventos. Na conversão, os eventos anteriores são vinculados ao lead.

A primeira observação de um favorito antigo aparece como “Favorito identificado no navegador”; sua data não é apresentada como o momento em que o usuário clicou no coração. Os favoritos atuais participam da construção do perfil. Favoritos removidos deixam essa lista, preservando o histórico.

A lista no lead reúne os últimos estados recebidos dos navegadores vinculados. Não é uma sincronização de favoritos entre dispositivos. Favoritos antigos só ficam conhecidos quando o navegador volta ao site com rastreamento permitido. Sem lista recebida e lista recebida vazia são estados distintos. O endpoint aceita até 500 IDs por sincronização.

## Verificação

- RSpec: serviços de inteligência, vínculo de sessão, favoritos, requests do frame/navegação e helpers compartilhados.
- `node test/javascript/public_interest_favorites_test.mjs`: estado inicial, add/remove/add rápido, ordem dos envios e retirada do consentimento.
- Conferência do HTML renderizado em Chrome a 390 e 1440 pixels: colapsos, tooltips, Escape, navegação visível e ausência de transbordamento horizontal.
- Build `admin_tailwind:build` e `zeitwerk:check`.

Sem migration ou execução de recuperação histórica. Publicação não faz parte desta alteração local.
