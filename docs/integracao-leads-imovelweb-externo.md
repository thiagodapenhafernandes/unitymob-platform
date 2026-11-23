# Unitymob — integração de leads

**Versão:** 1.1 — 21/11/2026  
**Contato técnico:** contato@unitymob.com.br

## Autorização

O administrador da imobiliária autoriza a **Unitymob** para a sucursal no painel de integração de leads do Imovelweb. Na Unitymob, informa o código da sucursal e conclui a confirmação do vínculo pelo e-mail administrativo cadastrado no portal.

O recebimento depende de uma conexão autorizada e ativa no ambiente correspondente. A publicação de imóveis por XML é independente desse fluxo.

## Callback

| Ambiente | Método e URL |
|---|---|
| Produção | `POST https://webhooks.unitymob.com.br/webhooks/imovelweb/production` |
| Sandbox | `POST https://webhooks.unitymob.com.br/webhooks/imovelweb/sandbox` |

Antes dos testes, confirmar com a Unitymob a habilitação do ambiente e o `clientCode` autorizado. Usar sandbox para eventos de teste.

```http
Content-Type: application/json
Authorization: Bearer <TOKEN_DE_CALLBACK_DO_AMBIENTE>
```

O token de callback é específico do ambiente e deve ser compartilhado por canal seguro. É distinto do access token da API Open Navent.

**Formato:** um objeto JSON por requisição, no idioma **EN**, com limite de **64 KiB**.  
**Eventos aceitos:** `CONTACTO` e `CONTACTO_MENSAJE`.

## Campos

| Campo | Uso |
|---|---|
| `eventId` | Obrigatório. Identificador estável do evento, até 255 bytes. |
| `eventType` | Obrigatório. `CONTACTO` ou `CONTACTO_MENSAJE`. |
| `clientCode` | Obrigatório. Identificador da conexão autorizada, até 255 bytes. |
| `name` | Nome do interessado. Opcional. |
| `email` | E-mail do interessado. Fornecer e-mail válido ou telefone utilizável. |
| `phoneNumber` | Telefone completo, preferencialmente com código do país e DDD. E-mail sem telefone é aceito. |
| `internalReference` | Código original do imóvel, quando disponível. |
| `reference` | Referência do anúncio na integração; preservada separadamente quando houver `internalReference`. |
| `idNavplat` | ID do anúncio no portal. |
| `message` | Mensagem do interessado. |
| `registerDate` | Data original; recomenda-se ISO 8601 com fuso horário. |
| `contactTypeId` | Tipo de contato informado pelo portal. |
| `messageId` | Identificador da mensagem. |
| `leadOrigin` | Marca/origem informada pelo portal. |

Os campos reconhecidos aceitam texto, inteiro ou `null`, sem objetos ou listas. Campos adicionais não reconhecidos são descartados. Não é necessário enviar CPF ou outros identificadores pessoais extras. Um contato válido pode ser recebido mesmo sem imóvel localizado.

### Exemplo com dados fictícios

Substituir `clientCode` pelo identificador acordado para sandbox.

```json
{
  "eventId": "evento-exemplo-0001",
  "eventType": "CONTACTO_MENSAJE",
  "clientCode": "CODIGO_DA_CONEXAO_SANDBOX",
  "name": "Pessoa de teste",
  "email": "lead@example.com",
  "internalReference": "AP-100",
  "reference": "iw-1234567890",
  "idNavplat": "1234567890",
  "message": "Gostaria de mais informações sobre o imóvel.",
  "registerDate": "2026-11-21T10:00:00-03:00",
  "leadOrigin": "Imovelweb"
}
```

## Respostas e reenvios

| HTTP | Significado |
|---|---|
| `202` | Evento aceito para processamento. Corpo: `{"ok":true}`. Também retornado para reenvios já registrados. |
| `401` | Autenticação ausente, inválida ou indisponível na configuração do receptor. |
| `404` | Ambiente inexistente ou conta sem conexão ativa. |
| `413` | Corpo superior a 64 KiB. |
| `422` | JSON ou campos inválidos, identificação obrigatória ausente ou evento não suportado. |
| `503` | Recebimento temporariamente indisponível. |

O `202` confirma o recebimento para processamento assíncrono; não confirma a conclusão do cadastro no CRM.

Em falhas de rede ou erros transitórios, reenviar com o mesmo `eventId` e `clientCode`, no mesmo ambiente. Isso evita duplicação. O primeiro conteúdo aceito é preservado: reenvio não atualiza os campos do evento. Cada nova manifestação deve ter um novo `eventId`. Erros de autenticação, conta ou formato devem ser corrigidos antes de tentar novamente.

Para suporte, informar ambiente, `eventId`, `clientCode`, data/hora com fuso e HTTP recebido, sem incluir o token.
