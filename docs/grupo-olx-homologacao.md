# Homologação de leads — Grupo OLX

## Cadastro do CRM

- Aplicação: Unitymob.
- Perfil: Software CRM/Integrador.
- Endpoint de cada anunciante: `https://webhooks.unitymob.com.br/webhooks/grupozap/IDENTIFICADOR-DA-INTEGRACAO`.
- Na homologação, apresentar o formato com identificação por integração e uma URL real de teste já registrada.
- Informar a razão social da empresa responsável e e-mail corporativo. O formulário não aceita Gmail/Outlook.
- Manual: https://developers.grupozap.com/webhooks/integration_leads.html
- Validador funcionando em 07/10/2026: https://developers.grupozap.com/webhooks/endpoint_validator/
- Formulário: https://docs.google.com/forms/d/e/1FAIpQLSd6WJ3xw-qoFzW2-6OvrEihTjurUwVsJYei-P4alae2S1yedQ/viewform

Não declarar validação externa concluída antes de executar o validador contra o ambiente escolhido. Os endereços `/leads/endpoint-validator/` e `/webhooks/endpoint_validator.html` retornaram 404 nesta data.

## Segurança e operação

A SECRET_KEY é emitida pelo Grupo OLX por CRM, não por anunciante. Configurar `GRUPOZAP_SECRET_KEY` no Gateway. A configuração global no CRM permanece apenas para o endpoint direto legado e exige administrador do sistema. Não incluir a chave no formulário ou documentação. Basic Auth inválido recebe 401.

O webhook aceita JSON objeto com `originLeadId`. Anúncios exigem `clientListingId`; ausência recebe 422. MCMV_OLX pode vir sem anúncio. O recebimento retorna 200 após enfileirar no Solid Queue, não após criar o lead.

No modo Gateway, o processamento identifica a conta pela URL e procura o imóvel somente dentro dela. O endpoint direto legado ainda usa resolução por código do imóvel. Ambos exigem recebimento habilitado. Imóveis desconhecidos ou ambíguos ficam em quarentena. Leads MCMV sem imóvel ainda ficam em quarentena; não apresentar esse fluxo como suportado na homologação.

## Automação implementada

Cada integração da família Grupo OLX recebe um UUID estável `lead_route_key`, independente do feed e do código do imóvel. A documentação admite identificar o cliente do CRM pela URL: https://developers.grupozap.com/webhooks/url_encoding.html.

Salvar a configuração agenda `PortalLeadGatewaySyncJob`. `PortalLeadGatewayReconcileJob` revisa as rotas a cada 15 minutos, inclusive as pausadas. Usa `WHATSAPP_WEBHOOK_GATEWAY_URL`, `WHATSAPP_WEBHOOK_GATEWAY_INTERNAL_TOKEN`, `WHATSAPP_WEBHOOK_GATEWAY_FORWARDING_SECRET` e `APP_HOST` (origem HTTPS deste CRM). `GRUPOZAP_GATEWAY_FORWARDING_SECRET` permite uma assinatura independente da Meta; na ausência, usa o segredo compartilhado existente, com pelo menos 20 caracteres. O cadastro da rota verifica se a autenticação Grupo OLX está configurada no Gateway; sem ela a UI não mostra a conexão pronta.

`POST /internal/grupozap/routes` atualiza o destino e o estado ativo sob autenticação interna. O Gateway valida Basic Auth externo, persiste cada entrega com unicidade por rota e `originLeadId`, assina o corpo junto ao UUID e encaminha ao CRM. Falhas usam o retry existente. Eventos pendentes ficam guardados na pausa, e o retry só considera rotas ativas. Novos eventos para rotas pausadas são recusados. O CRM confirma a assinatura e o estado ativo antes de enfileirar.

A vinculação da URL à conta anunciante no Grupo OLX continua manual; não há confirmação automática desse cadastro. A UI mostra preparação, falha, pausa, pronta para vincular e último lead recebido. A chave não é solicitada aos clientes.

## Publicação e movimentação de servidor

Publicar o Gateway e executar sua migration `20261007140000`, configurar a chave Grupo OLX e garantir o agendamento de `webhooks:retry_failed` de `gateway/README.md`. Publicar o CRM e executar sua migration `20261007140000`. A reconciliação gera UUIDs para integrações anteriores e registra as rotas.

Ao mover uma conta, preservar o UUID, atualizar `APP_HOST` no destino e desativar a execução dessa conta no servidor antigo antes da reconciliação no novo. Duas cópias ativas podem disputar o destino. Homologação deve usar outro Gateway ou novas identidades; nunca reconciliar em produção com UUIDs copiados.

Reentregas são verificadas pelo `originLeadId` dentro da conta e protegidas por índice único. Leads existentes seguem a distribuição normal da conta. `ddd` + `phone` têm prioridade sobre `phoneNumber` depreciado.

Antes de validar externamente, confirmar domínio definitivo, chave configurada, fila ativa e código de imóvel de teste único no ambiente. Usar somente contatos fictícios. A aprovação e a emissão da chave dependem do Grupo OLX; não desabilitar autenticação para passar no validador.

Se a chave ainda não foi emitida, informar isso na homologação e pedir o procedimento de validação inicial ao Grupo OLX, sem marcar a validação como realizada. Suporte informado no manual: chamado.integracao@olxbr.com.
