# Política de base legal da Unitymob Platform nas integrações externas

## Padrão técnico

Esta é uma política própria da Unitymob Platform. A documentação do RD foi uma referência inicial de formato, não define as opções ou regras da plataforma.

`Privacy::LegalBases` centraliza a declaração solicitada pela operação:
`data_processing / legitimate_interest / granted`, versão `2026-10-12`.
É uma declaração da política do controlador, não uma autorização do titular.
Não declara a categoria `communications`, não marca consentimento e não
habilita cookies, tracking, integrações ou campanhas.

O padrão só é adequado quando a finalidade concreta permite legítimo interesse.
A imobiliária controladora precisa avaliar cada operação; dados sensíveis,
obrigações contratuais e outros tratamentos não recebem adequação jurídica
pelo simples uso deste método. A configuração técnica não é teste de balanceamento.

## Registro de novas entradas

Toda criação/validação de novo `Lead` por ActiveRecord registra em
`other_information.unitymob_data_processing_policy` a declaração, versão,
origem `unitymob_policy_default` e momento do registro. O prefixo Unitymob
é reservado e sobrescrito pelo backend na criação: um formulário externo
não pode usá-lo para fabricar prova de aceite.

O registro cobre entradas por RD Station, Meta, LinkedIn, TikTok, portais,
Lovers, migração externa, WhatsApp, formulários e cadastro administrativo,
porque todas persistem o mesmo model. Dados brutos do fornecedor, incluindo
consentimentos e recusas, continuam em seus campos originais. Não substituímos
um consentimento externo recusado por um consentimento concedido.

Nas consultas complementadas, a informação da nova entrada é conservada
em `LeadActivity.metadata.inquiry_information`. O cadastro principal mantém
sua informação de origem, conforme o fluxo existente de deduplicação.
Não há backfill nem alteração automática da política de cadastros antigos.
`insert_all`, SQL direto e importações que pulem callbacks não são cobertos.

## Saídas por destino

| Destino/fluxo | Implementação |
| --- | --- |
| Webhook de saída / formulário com destino explícito | `legal_bases` no nível principal, produzido pela política compartilhada. |
| Webhook padrão de automação | Mesma declaração no payload registrado em `AutomationWebhookDelivery`; permanece durante retries. |
| Payload personalizado de automação | Preservado integralmente; o operador pode incluir a declaração documentada no template. Não introduzimos chaves inesperadas num contrato personalizado. |
| RD Station | A integração atual é receptiva. Não existe chamada de criação/atualização de contato CRM que registre essa base no RD. |
| Meta/WhatsApp, LinkedIn, TikTok, Lovers, portais, migração | A política fica registrada no lead dentro da Unitymob; o contrato de cada fornecedor permanece intacto. Não injetamos campos da política Unitymob em schemas de fornecedores. |
| IA/OpenAI, push/FCM, email, geocodificação, armazenamento e feeds de imóveis | Nenhum parâmetro de base legal é enviado. Este registro de lead não estabelece a base jurídica desses tratamentos, cujas finalidades e dados devem ser avaliados separadamente pelo controlador. |

Registrar a política na Unitymob não prova que o fornecedor recebeu ou adotou
a mesma base. Não existe campo universal de consentimento em APIs externas.
Uma adequação integral de todos os tratamentos requer inventário de finalidades,
política por finalidade, comprovação de consentimento quando aplicável e gestão
de oposição/retirada, além dos contratos de cada operador. Isso não é produzido
por uma chave JSON e não está implementado nesta etapa.

## Consentimento e oposição

Aceite de cookies permanece restrito ao tracking já implementado. Para declarar
`consent`, é preciso conservar a manifestação específica, sua finalidade,
texto/versão apresentado, origem, data e retirada. A chave de política padrão
não serve como essa evidência. Uma recusa recebida exige revisão do tratamento
correspondente; a política padrão não autoriza contornar a recusa.

Não há nesta entrega bloqueio automatizado global por oposição ou cadastro
retroativo de consentimentos. O procedimento operacional permanece em
`docs/privacy/operacao-e-retencao.md`.

## Referências

- ANPD: https://www.gov.br/anpd/pt-br/assuntos/noticias/anpd-lanca-guia-orientativo-sobre-legitimo-interesse

Os identificadores técnicos são definidos por `Privacy::LegalBases::OPTIONS`, contrato próprio da Unitymob Platform. Alterações nesse conjunto devem considerar a política da plataforma e a compatibilidade dos consumidores dos webhooks.

### Cadastro manual

O cadastro manual oferece o select **Base legal para tratamento de dados**, com labels em português e padrão **Legítimo interesse**. A escolha é validada no servidor e persistida em `other_information.unitymob_data_processing_policy`, com origem `manual_registration`, versão e horário. Os webhooks padrão usam essa base registrada; cadastros sem declaração continuam com o padrão. Não há migration nem alteração retroativa.

Opções: Legítimo interesse (`legitimate_interest`), Consentimento (`consent`), Contrato preexistente (`pre_existent_contract`), Processo judicial (`judicial_process`), Interesse público (`public_interest`) e Proteção da vida (`vital_interest`). A seleção de consentimento é declaração do operador, não coleta ou comprovação da autorização; registre a evidência nas observações. O select se aplica ao cadastro, não altera a base de leads existentes.
