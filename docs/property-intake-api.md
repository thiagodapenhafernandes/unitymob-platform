# API de captação de imóveis

A referência navegável fica em `/docs/api`. Para importar no Postman, use
`/docs/openapi.yaml` no mesmo ambiente.

Envie `POST /api/v1/property_intakes` com `Content-Type: application/json`,
`Accept: application/json` e `Authorization: Bearer <TOKEN_DA_INTEGRACAO>`.
Use o token somente no backend do sistema de origem. A conta de destino é
identificada pela credencial.

```json
{
  "external_id": "CAP-2026-000123",
  "captured_at": "2026-11-06T14:30:00-03:00",
  "captador": { "external_id": "CAPTADOR-002", "nome": "Mariana Exemplo" },
  "imovel": {
    "categoria": "apartamento",
    "modalidade": "venda",
    "titulo": "Apartamento de 3 quartos com varanda",
    "descricao": "Apartamento com varanda, uma suíte e duas vagas.",
    "valor_venda_centavos": 85000000,
    "valor_condominio_centavos": 95000,
    "valor_iptu_anual_centavos": 180000,
    "area_privativa_m2": 92.5,
    "quartos": 3,
    "suites": 1,
    "banheiros": 2,
    "vagas": 2,
    "endereco": {
      "cep": "90000-000",
      "logradouro": "Rua Exemplo",
      "numero": "120",
      "complemento": "Apartamento 302",
      "bairro": "Centro",
      "cidade": "Porto Alegre",
      "uf": "RS"
    },
    "fotos": [
      { "url": "https://midia.example.com/captacoes/sala.jpg", "ordem": 1 }
    ]
  },
  "proprietario": {
    "nome": "Carlos Exemplo",
    "telefone": "+5551999990000",
    "email": "carlos@example.com"
  }
}
```

Para locação, use `"modalidade": "locacao"` com o valor mensal em
`valor_locacao_centavos`. Envie ao menos um contato do proprietário. Área,
contagens, despesas, complemento e fotos são opcionais no recebimento.
A revisão aplica as exigências de aprovação configuradas na conta.

Envie até 10 fotos JPEG, PNG ou WebP, com até 8 MB cada, em URLs HTTPS
públicas na porta 443, sem redirecionamento. Links temporários precisam
estar válidos até o primeiro recebimento bem-sucedido.

A primeira chamada bem-sucedida devolve `201 Created` e o seguinte formato.

```json
{
  "protocolo": "PC-000123",
  "external_id": "CAP-2026-000123",
  "status": "pendente_revisao"
}
```

O reenvio do mesmo JSON devolve `200 OK` com o protocolo original. Alterar
o conteúdo de um ID já recebido resulta em `409 Conflict`. Credencial
inválida retorna `401 Unauthorized`. Dados inválidos retornam `422`.
O protocolo confirma a entrada na fila administrativa. O captador é
registrado no recibo com a identidade externa enviada e a captação entra
sem responsável interno atribuído.

## Credencial por conta

No painel administrativo, acesse **Integrações → API de captação**.
O administrador da conta com permissão de gerenciar integrações pode gerar,
rotacionar ou revogar a credencial. Copie o valor no momento da emissão e
entregue-o por canal seguro. A aplicação guarda apenas o digest.
A rotação invalida o token anterior e a revogação interrompe novos envios.
