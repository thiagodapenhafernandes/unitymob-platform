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
contagens, despesas, complemento, título, descrição e fotos são opcionais no recebimento.
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
registrado no recibo com a identidade externa enviada. Se `captador.email` for
informado, deve corresponder a um usuário ativo da conta e será vinculado em
**Responsáveis e agenciamento → Captador**. Sem e-mail, mantém o comportamento
anterior, sem responsável interno atribuído. E-mail sem correspondência retorna `422`.

## Credencial por conta

No painel administrativo, acesse **Integrações → API de captação**.
O administrador da conta com permissão de gerenciar integrações pode gerar,
rotacionar ou revogar a credencial. Copie o valor no momento da emissão e
entregue-o por canal seguro. A aplicação guarda apenas o digest.
A rotação invalida o token anterior e a revogação interrompe novos envios.


## Campos adicionais (opcionais)

No objeto `imovel`:

| Campo da API | Campo no cadastro |
|---|---|
| `torre` | Bloco / Unidade |
| `demi_suites` | Demi-suítes (inteiro) |
| `nome_condominio` | Nome do empreendimento/condomínio |
| `area_total_m2` | Área total (número, de 0 a 99.999.999,99) |
| `tipo_vaga`, `box` | Tipo de vaga e número do box |
| `onde_estao_as_chaves`, `observacoes_chaves` | Localização e observações das chaves |
| `permuta`, `parcelamento` | Aceita permuta/parcelamento (`true` ou `false`) |
| `administracao_locacao` | Administração da locação (`true` ou `false`) |
| `tipo_cadastro` | `Unitário` ou `Empreendimento` |
| `observacoes_internas` | Descrição interna |
| `observacoes_restritas` | Observações internas e restritas |

Localização das chaves: `Imobiliária`, `Corretor(a)`, `Proprietário`, `Zelador`,
`Portaria`, `Inquilino`, `Construtora` ou `Outro`.
O nome do condomínio segue as regras existentes do cadastro: imóveis avulsos
que não utilizam empreendimento podem ter esse nome removido pelo model.

Títulos e descrições podem ser omitidos, nulos ou vazios nesta etapa. As validações
estruturais, de identidade, endereço e preço continuam ativas; as exigências de
aprovação/publicação continuam sendo aplicadas pelo fluxo administrativo da conta.

## Características internas, infraestrutura e lazer

Antes de montar o cadastro, consulte as opções gerenciadas em **Gerenciar** na
conta de destino, usando o mesmo token da captação:

```http
GET /api/v1/property_features
Authorization: Bearer <TOKEN_DA_INTEGRACAO>
Accept: application/json
```

Resposta `200 OK` (IDs ilustrativos; consulte os IDs reais de cada conta):

```json
{
  "caracteristicas_internas": [{ "id": 101, "nome": "Área de serviço" }],
  "infraestrutura_lazer": [{ "id": 202, "nome": "Piscina" }]
}
```

Cada lista retorna apenas `id` e `nome`, ordenada por nome; sem opções cadastradas,
retorna `[]`. Não retorna opções de outras contas ou de outras categorias.
Credencial ausente, inválida, revogada ou de conta inativa retorna `401`.
A consulta reflete inclusões, renomeações e exclusões feitas no catálogo da conta.
Não cria opções nem inclui automaticamente sugestões fixas de outras categorias de imóvel.

No `POST /api/v1/property_intakes`, acrescente os campos opcionais:

```json
{
  "imovel": {
    "caracteristicas_internas": [101],
    "infraestrutura_lazer": ["Piscina"],
    "endereco": {
      "tipo_logradouro": "Avenida",
      "logradouro": "Exemplo"
    }
  }
}
```

O trecho acima complementa o exemplo completo; não substitui os demais campos
obrigatórios. As duas listas aceitam IDs inteiros, IDs em strings numéricas ou
nomes, inclusive misturados. Nomes são comparados sem distinguir maiúsculas e
acentos; o cadastro guarda o nome atual da opção e elimina repetições.
Prefira IDs, que permanecem iguais quando uma opção é renomeada. IDs são
específicos da conta e da categoria: não reutilize IDs de outro ambiente/conta.
Consulte novamente o catálogo após alterações no Gerenciar.

Listas omitidas preservam a compatibilidade com os envios anteriores; `[]` indica
nenhuma opção. `null`, valores que não sejam listas, itens inválidos e opções
inexistentes, removidas, de outra conta ou categoria retornam `422`, sem criar a
captação. A API não cria opções a partir de nomes desconhecidos. Cada nome aceita
até 255 bytes. Exemplo de erro:

```json
{ "error": "caracteristicas_internas contém opção desconhecida nesta conta" }
```

`imovel.endereco.tipo_logradouro` é uma string opcional, não vazia, de até 255
bytes (ex.: `Rua`, `Avenida`, `Alameda`), gravada em `tipo_endereco` do endereço.
Quando informado, envie `logradouro` somente com o nome da via. A API mantém esse
texto como recebido: não remove prefixos automaticamente. Envios antigos sem
`tipo_logradouro` continuam aceitos com o logradouro completo.

As regras de reenvio continuam iguais: repita exatamente o conteúdo original
para receber o mesmo protocolo. Acrescentar esses campos a um `external_id` já
recebido resulta em `409`; este endpoint não atualiza captações existentes.

## Documentos internos

Envie `documentos` na raiz, separado de `imovel.fotos`:

```json
"documentos": [
  { "url": "https://midia.example.com/autorizacao.pdf", "tipo": "autorizacao" },
  { "url": "https://midia.example.com/documento.png", "tipo": "documento" }
]
```

Até 10 documentos, 8 MB cada, PDF, JPEG, PNG ou WebP, com as mesmas restrições
HTTPS e de rede das fotos. `autorizacao` vai para autorizações de venda;
`documento` para documentos internos. Usa o armazenamento de documentos da conta,
com a visibilidade administrativa já existente. Falha no arquivo rejeita a captação;
o reenvio idêntico bem-sucedido não duplica anexos.

## Categorias aceitas

`apartamento`, `cobertura`, `loft`, `casa`, `casa_em_condominio`, `sobrado`,
`chacara`, `sitio`, `diferenciado`, `casa_comercial`, `condominio_industrial`,
`galpao`, `galpao_em_condominio`, `loja`, `ponto_comercial`, `predio_comercial`,
`sala_comercial`, `area`, `terreno`, `terreno_em_condominio`, `condominio`,
`empreendimento`.

Também aceita equivalentes com hífen e os nomes acentuados do cadastro.

## Consulta para evitar duplicidade

```http
GET /api/v1/properties/search?cep=88330-000&logradouro=Rua%202000&numero=100&complemento=Apto%201402
Authorization: Bearer <TOKEN_DA_INTEGRACAO>
```

Obrigatório: número e CEP, ou número, logradouro, cidade e UF. Filtros opcionais:
`complemento` e `torre`. A comparação é exata, desconsiderando maiúsculas e acentos;
CEP aceita com ou sem hífen. Omitir complemento inclui todas as unidades; enviar
complemento vazio procura as que não têm complemento. Abreviações diferentes
(ex.: `Apto` e `Apartamento`) não são consideradas iguais.

```json
{
  "imoveis": [{
    "codigo": "12345",
    "endereco": {
      "logradouro": "Rua 2000", "numero": "100", "complemento": "Apto 1402",
      "bairro": "Centro", "cidade": "Balneário Camboriú", "uf": "SC", "cep": "88330-000"
    },
    "torre": "A", "categoria": "Apartamento", "modalidade": "venda", "status": "em_revisao"
  }]
}
```

Retorna somente imóveis da conta do token, incluindo revisão administrativa,
ativos e inativos. Status: `ativo`, `inativo`, `em_revisao`. Não retorna proprietário,
contatos, documentos ou observações. Até 50 resultados; ao atingir esse limite,
refine os filtros. A consulta indica possíveis duplicados, sem impedir automaticamente
um novo envio. O token deve permanecer no backend, inclusive para esta consulta.
