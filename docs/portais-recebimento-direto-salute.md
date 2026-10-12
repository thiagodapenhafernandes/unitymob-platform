# Recebimento direto de leads — Salute / Unitymob

Preparação em 11/10/2026. Não representa conexão habilitada ou entrega homologada.

## Situação

Imovelweb, Imovelweb 2, Casa Mineira e Chaves na Mão publicam imóveis,
mas não possuem conector dedicado de entrada de leads na Unitymob.
O recebimento Grupo OLX existente deve ser preservado.

O admin oferece uma solicitação por conta em **Portais → canal → Recebimento direto**.
O código da conta é preenchido quando cadastrado; a ausência deve ser resolvida
com o suporte. Nenhuma chave do feed ou credencial acompanha a solicitação.

## O que pedir aos suportes

### Imovelweb e Imovelweb 2

Enviar a atendimento@imovelweb.com.br, a partir de e-mail cadastrado na conta:

> Queremos integrar as duas contas da Salute diretamente ao CRM Unitymob,
> sem o Gestor de Leads OLX. Confirmem o suporte a CRM próprio, documentação
> do webhook/API de leads, homologação necessária e habilitação independente
> de cada conta. Não alterar a integração atual de anúncios.

### Casa Mineira

Solicitar orientação a atendimento@imovelweb.com.br, contato indicado na
documentação conjunta, ou ao atendimento comercial da conta Casa Mineira:

> Precisamos receber os leads da conta Salute diretamente na Unitymob.
> Existe webhook/API de saída independente do Gestor OLX? Se sim, enviem
> documentação e requisitos de homologação. Caso outro time seja responsável,
> encaminhem a solicitação e identifiquem o contato técnico.

A documentação pública encontrada descreve a via Gestor OLX; não comprova
que a opção direta esteja disponível à Unitymob.

### Chaves na Mão

Enviar a atendimento@chavesnamao.com.br de e-mail cadastrado na conta:

> Queremos cadastrar a Unitymob como integrador de recebimento de leads da
> Salute, mantendo o XML de anúncios atual. Enviem especificação do endpoint
> de leads, autenticação, payload e processo de habilitação/homologação.

## Informações necessárias para os quatro canais

- Entrega por webhook ou consulta via API; campos e exemplo anonimizado.
- Método de autenticação e como cadastrar a URL/chave com segurança.
- Identificador da conta, ID único do lead e referência do imóvel.
- Nome, telefone, e-mail, mensagem, data, finalidade venda/locação e origem.
- Eventos contemplados: formulário, WhatsApp e telefone; restrições de plano.
- Reenvios, timeout, códigos HTTP esperados, limites e recuperação de históricos.
- Ambiente ou lead de teste; eventual custo e homologação de CRM próprio.

Não é necessário compartilhar senha de login, dados de clientes reais ou
token do feed para obter essa documentação.

## Infraestrutura existente e limites

A Unitymob possui `POST /webhooks/inbound/leads`, com Bearer token pessoal,
payload normalizado e escopo da conta do usuário. Não divulgar uma credencial
pessoal como credencial de portal. O endpoint não é um conector homologado
para esses fornecedores: ainda faltam tradução do payload, credencial dedicada,
deduplicação pelo ID externo, referência de imóvel escopada à conta e confirmação
de recebimento vinculada ao portal. Só reutilizar o fluxo de intake após validar
esses contratos. Não encaminhar para o webhook de status de anúncios.

## Critério de ativação

1. Portal confirma disponibilidade, formato e autenticação.
2. Implementar conector no fluxo `Leads::Intake`, com credencial por conta/canal,
   idempotência e tratamento explícito de erro/retry.
3. Testar autenticação inválida, isolamento de contas, imóvel desconhecido,
   venda/locação e reenvio do mesmo lead sem duplicar ou redistribuir.
4. Portal envia lead de teste; conferir criação/complementação e distribuição.
5. Somente então habilitar a conexão e registrar recebimento confirmado no admin.

## Fontes oficiais

- Chaves na Mão aceita informar endpoint de leads ao suporte:
  https://help.chavesnamao.com.br/support/solutions/articles/72000640720-quero-alterar-meu-integrador-de-im%C3%B3veis-o-que-fazer-
- Imovelweb/Casa Mineira: contato e procedimento publicado para integração via Gestor OLX:
  https://developers.grupozap.com/leadManager/imovelweb_casamineira.html

Nenhuma dessas páginas fornece o contrato completo de recebimento direto
que permita declarar a integração da Unitymob operacional.
