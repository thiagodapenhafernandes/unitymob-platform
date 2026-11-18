# Chaves na Mão — preparação do recebimento direto

## Estado da implementação

Implementação de **captura para homologação**, disponível para todas as
contas em Portais → Chaves na Mão. Nasce desativada e tem configuração própria
por tenant. Não é ainda o conector operacional de criação de leads.

O contrato técnico imobiliário do fornecedor (campos, autenticação efetivamente
enviada, ID de evento, retries e resposta esperada) ainda precisa ser confirmado.
A página Meus Dados fornece um token de integração de leads, mas isso não prova
o formato de entrega. Não presumir o contrato da API de veículos.

## Captura implementada

- Configuração isolada por conta, com ID do anunciante e token criptografado.
- `POST /webhooks/chaves_na_mao/:route_key`: URL específica da conexão.
- Autenticação que o receptor suporta para homologação: `Authorization: Basic <token>`
  ou `Authorization: Bearer <token>`, comparado ao token configurado. Esses formatos
  **não estão confirmados pelo Chaves na Mão**; precisam ser acordados antes de
  apontar qualquer tráfego. Não enviar credencial pessoal da Unitymob.
- Captura exclusivamente objetos JSON não vazios, com até 64 KiB; 120 pedidos
  por minuto/IP. Identidade da conta é resolvida pela URL autenticada, nunca
  pelo tenant informado no corpo.
- Corpo criptografado no banco e removido dos parâmetros de log antes do parser
  Rails. A interface mostra apenas ID e data dos últimos dez eventos.
- Retry com os mesmos bytes retorna 200 e reutiliza o recibo. Esse digest serve
  só à captura; não substitui o ID estável do fornecedor na integração definitiva.
- Desativada/conta inativa: 409; credencial inválida: 401; rota desconhecida: 404;
  JSON inválido: 400; objeto vazio/não objeto: 422; corpo excessivo: 413.
- Não cria leads, não altera atribuição, não agenda jobs nem envia notificações.
  Recibos de validação não serão reproduzidos automaticamente ao ativar o conector.

O feed XML e as configurações C2S são independentes e não são alterados.
Não substituir o e-mail de propostas nem desligar o C2S para testar esta etapa.
Publicar o Rails requer a migration `20261117220000`; não exige mudanças no Gateway.

## O que falta para concluir o conector operacional

1. Obter documentação ou payload anonimizado e confirmar a autenticação, ID de
   conta, ID único por contato/evento, referência do imóvel e venda/locação.
2. Confirmar com o fornecedor se é possível entregar em paralelo ao fluxo atual.
   A captura não garante que o portal suporte dois destinos.
3. Implementar o adaptador a partir desse contrato, com quarentena para casos
   inválidos e resolução do imóvel apenas dentro da conta.
4. Reutilizar `Leads::Intake`, acrescentando a referência estável do provedor;
   testar também chegada direta seguida/precedida pelo C2S. Coincidência de
   telefone não basta para evitar redistribuição de uma mesma consulta.
5. Validar contato novo, reenvio, e-mail sem telefone, imóvel desconhecido,
   venda/locação, isolamento e os eventos WhatsApp/telefone/formulário suportados.
6. Conferir teste real, resultado esperado e habilitação por conta antes da
   virada. A captura atual não oferece ativação operacional.

## Solicitação ao portal

O bloco de solicitação existente permanece na tela. Enviar a partir de endereço
cadastrado, somente quando autorizado pelo responsável pela conta:

> Precisamos homologar o recebimento de leads no CRM Unitymob. Enviem o contrato
> do webhook imobiliário: headers de autenticação, JSON anonimizado, ID estável
> do evento, identificação da conta e imóvel, eventos contemplados, retries e
> resposta esperada. Precisamos manter o fluxo atual pelo C2S enquanto validamos.
> É possível entregar também no endpoint de homologação, sem substituir o destino
> atual? Não alterar o XML de anúncios nem o e-mail de propostas nesta etapa.

Fonte oficial: [procedimento para alterar o integrador](https://help.chavesnamao.com.br/support/solutions/articles/72000640720-quero-alterar-meu-integrador-de-im%C3%B3veis-o-que-fazer-).
