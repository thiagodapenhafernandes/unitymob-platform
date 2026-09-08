# Validação de prévias de imóveis no WhatsApp

Verificação HTTP em 08/09/2026. Links públicos da Conexão:

| Código | Página e imagem | Dimensões JPEG | Bytes |
| --- | --- | --- | --- |
| 4054 | HTTP 200 | 1280 × 719 | 192422 |
| 2846 | HTTP 200 | 1365 × 1024 | 373460 |
| 2672 | HTTP 200 | 1365 × 1023 | 544766 |

Metadados og:title, og:description, og:url e og:image presentes no HTML do servidor; og:image nos primeiros 1,5 KB. Os documentos também retornaram os metadados com User-Agent WhatsApp/2.2236.3 N.

Documentação oficial consultada: https://developers.facebook.com/docs/whatsapp/link-previews/
Exige imagem abaixo de 600 KB, largura de pelo menos 300 px, proporção largura/altura de até 4:1 e head/metadados nos primeiros 300 KB. Os três exemplos atendem. A Meta não garante exibição e orienta aguardar a prévia no compositor antes de enviar. A requisição via curl retornou a documentação; o navegador de pesquisa inicialmente recebeu 429.

Caminho usado: WA-JS 4.6.0, não Cloud API. sendTextMessage chama prepareLinkPreview, que tolera falhas de obtenção da imagem. A implementação de prévias dessa biblioteca também usa serviços externos; a disponibilidade da página de imóvel não prova sucesso desse processamento.
Fontes da biblioteca:
- https://github.com/wppconnect-team/wa-js/blob/v4.6.0/src/chat/functions/prepareLinkPreview.ts
- https://github.com/wppconnect-team/wa-js/blob/v4.6.0/src/util/linkPreview.ts
- https://github.com/wppconnect-team/wa-js/blob/v4.6.0/src/chat/functions/sendTextMessage.ts

Ajuste 0.4.8: preparação limitada a 15 segundos, miniatura obrigatória, contexto da conversa revalidado após a espera, envio da mensagem já preparada usando a mesma função final da biblioteca. Nenhum retry automático de envio. Cards indicam fila, preparação/envio, conclusão ou interrupção. Itens enviados são desmarcados; itens restantes ficam selecionados. Controles dos cards ficam bloqueados durante a operação; animação respeita movimento reduzido.

Validação: 84 testes no checkout da release e 82 no checkout principal, todos aprovados. Inclui ausência de imagem, erro de preparação, timeout sem envio tardio, troca de destinatário e erro de envio sem repetição. Build de produção discovery 0.4.8 gerado. Não houve envio real: renderização no aplicativo destinatário ainda requer teste manual autorizado. Não há mudança de backend nem deploy Rails necessário.

## 0.4.9 / 0.4.10: preparação e contagem

O Chrome aberto confirmou bloqueio CSP das imagens dos serviços externos de preview. As fotos públicas 4054, 2846 e 2672 foram baixadas e convertidas com sucesso no service worker da extensão (HTTP 200; prévias JPEG de 13.253, 13.374 e 19.755 bytes). A 0.4.9 foi carregada no perfil do usuário, com as mesmas permissões. Nenhuma mensagem real foi enviada pelo diagnóstico.

A 0.4.10 acrescenta um indicador discreto `✓ Enviado N×`, persistido no Chrome por origem/tenant, conta WhatsApp, conversa, lead e imóvel. Conta somente sucesso confirmado pelo envio, nunca preparação ou erro incerto. Não retroage envios anteriores nem sincroniza com outros navegadores. Falha ao salvar o contador não transforma mensagem já enviada em erro/retry. Tooltip informa escopo e último envio. Histórico permanece ao reabrir o lead. A fila de gravações existente serializa envios e contadores.

Validação: 92 testes passaram no pacote isolado, build e verificação de diff passaram. Pacote em `browser-extension/releases/0.4.10` e ZIP correspondente. Nenhuma mudança no site público é necessária para essas correções.


## Envio direto pela busca — 2026-09-08 (ainda não publicado)

A seleção no catálogo compartilha após a confirmação existente e vincula cada imóvel somente após envio confirmado. O worker consulta `POST /api/v1/browser_extension/leads/:id/properties/share`, que valida acesso ao lead, tenant, capacidade de vínculo e imóvel público/comercial. Não recebe URL arbitrária do painel. A vinculação reutiliza a operação idempotente existente.

Falhas de vínculo retornam sucesso do envio com pendência separada. A pendência é guardada no navegador no escopo do histórico de compartilhamento; retomadas tentam somente o vínculo. Imóveis já vinculados podem ser reenviados, sem duplicar interesses. A atualização de interesses preserva busca, filtros e aba. Removida a mensagem “Imóveis enviados em mensagens individuais.”, sem mudanças de CSS.

Validação: 95 testes JS; 14 testes Rails focados em propriedades, autorização e login; build e Zeitwerk aprovados. Nenhuma mensagem real foi enviada nos testes. A pasta carregada `browser-extension/releases/0.4.10` recebeu os três arquivos atualizados para teste, preservando manifesto/ID/CSS; o ZIP submetido à loja permanece intacto. O novo fluxo requer também o servidor atualizado (incluindo o `public_path` retornado pela busca); recarregar a extensão contra produção antiga não ativa o fluxo completo.
