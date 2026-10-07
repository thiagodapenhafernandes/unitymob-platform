# TikTok Lead Generation na Unitymob

Implementação de entrada de leads de Instant Forms pela Marketing API v1.3.
O postback de eventos do CRM não faz parte desta entrega.

## Fluxo

1. O administrador abre Integrações → TikTok Ads e conecta sua conta.
2. O CRM registra no Gateway um state de uso único, com validade de dez minutos e URL de retorno HTTPS.
3. O TikTok retorna a autorização ao Gateway; o Gateway consome o state e redireciona para a instância original.
4. O CRM valida state, sessão, usuário e tenant, troca `auth_code` pelo token e armazena o token com Active Record Encryption.
5. O administrador seleciona anunciantes; o job registra as rotas no Gateway e cria subscriptions `LEAD` / `INSTANT_FORM` por anunciante. A atualização periódica reconcilia inscrições e formulários a cada 15 minutos.
6. O Gateway recebe `object: 1` / `entry`, separa cada lead e encaminha somente à conexão cadastrada para aquele anunciante. Um anunciante tem um único destino; conflitos exigem revisão do vínculo pelo suporte.
7. O CRM enfileira o processamento, cria o Lead com campanha, anúncio, formulário e respostas, e usa o roteamento/distribuição existente. Filtros por anunciante e formulário ficam nas regras. Regras do site não capturam leads TikTok.

Sem regra compatível, o lead fica salvo sem atribuição automática. Histórico anterior à inscrição e leads de direct messages não são importados. Leads de teste recebidos pela subscription podem criar leads no CRM; use uma conta de homologação.

## Configuração do aplicativo e servidores

Criar/aprovar o aplicativo no TikTok API for Business, com os escopos:

- Ad Account Management → Ad Account Information.
- Creative Management → Instant Page Management.
- Lead Management → Leads Retrieval; Test Leads para homologação.

O usuário deve ter acesso ADMIN ao anunciante para criar a subscription.

Nas instâncias Rails:

- `TIKTOK_APP_ID`, `TIKTOK_APP_SECRET`: mesmo aplicativo Unitymob.
- `TIKTOK_REDIRECT_URI`: `https://webhooks.unitymob.com.br/oauth/tiktok/callback`, registrada no aplicativo. Deve corresponder à URL configurada do Gateway.
- `TIKTOK_WEBHOOK_TOKEN`: segredo hexadecimal de 64 caracteres (256 bits), igual ao Gateway. Gere com `SecureRandom.hex(32)` e mantenha fora do Git.
- `TIKTOK_GATEWAY_FORWARDING_SECRET`: segredo opcional específico do provider, com pelo menos 20 caracteres; fallback para o segredo de encaminhamento Meta já configurado.
- Configuração existente do Gateway (`WHATSAPP_WEBHOOK_GATEWAY_URL`, `WHATSAPP_WEBHOOK_GATEWAY_INTERNAL_TOKEN`, `WHATSAPP_WEBHOOK_GATEWAY_FORWARDING_SECRET`) e `APP_HOST` HTTPS da instância.
- Chaves existentes de Active Record Encryption.

No Gateway: `TIKTOK_WEBHOOK_TOKEN`, token interno existente e banco migrado.

A URL de webhook é cadastrada automaticamente pelo job:
`https://webhooks.unitymob.com.br/webhooks/tiktok?webhook_token=<segredo>&connection_key=<vínculo>`.
O código registra um único endpoint compartilhado; a chave identifica a conexão e impede reutilizar uma subscription de outro tenant. A URL contém credencial: não enviar em prints, relatórios ou logs. O aplicativo mascara o query string nos access logs desses endpoints; configurar também o proxy/Nginx para registrar `$uri`, sem `$args`/`$request`, nos endpoints TikTok e de retorno OAuth.

A documentação consultada da Subscription API não especifica a assinatura `TikTok-Signature` do produto TikTok for Developers. Por isso, esta implementação autentica a URL de callback com segredo aleatório sobre HTTPS; não afirma verificar uma assinatura do TikTok. O encaminhamento Gateway → CRM usa HMAC SHA-256 vinculado à chave da conexão e ao corpo bruto. Homologar a URL com query string e o payload real no aplicativo aprovado antes de ativar produção.

## Persistência, falhas e desconexão

- Gateway deduplica por anunciante + ID externo e reutiliza retry existente; também retoma eventos `received` após interrupção. Falhas após dez tentativas permanecem disponíveis na auditoria do Gateway.
- CRM deduplica por tenant + anunciante + ID externo em índice único. Recibos sobrevivem à exclusão de leads. Falhas de processamento ficam na fila e geram aviso na integração, sem registrar contatos nos argumentos do job.
- Desmarcar um anunciante interrompe imediatamente a aceitação no CRM; a reconciliação desativa a rota e cancela subscriptions correspondentes. A conexão precisa manter credenciais até a limpeza terminar.
- Desconectar preserva leads/recibos, desativa rotas e cancela subscriptions. Falhas de limpeza mantêm o token para permitir retry e mostram aviso.
- Token da Marketing API é de longa duração, sem refresh token. Revogação exige nova autorização e subscriptions atualizadas. O aplicativo não revoga o token remoto ao desconectar para não afetar outras autorizações; cancela suas subscriptions e apaga a credencial local.
- Não mover um anunciante entre contas alterando diretamente a seleção: o Gateway bloqueia mudança de proprietário. Rever rotas pendentes e recibos antes de transferir um vínculo.

## Publicação e homologação

Publicar migrations e código do Gateway antes de habilitar o TikTok nas instâncias. Publicar Rails e migrar o banco de cada instância, configurar secrets e validar workers `sync` e `default` do Solid Queue. Seguir `docs/deploys.md`: Gateway tem publicação própria; `mina all deploy` cobre apenas Salute/Conexão.

Validar em homologação: conectar via callback central; selecionar anunciante ADMIN; confirmar inscrição; criar lead de teste; conferir evento `forwarded`, Lead, campanha/formulário/respostas e regra de distribuição; reenviar e confirmar ausência de duplicata; desmarcar e confirmar interrupção; testar anunciantes de outra conexão e indisponibilidade temporária do CRM. Não considerar HTTP 200 prova de distribuição.

Comandos locais:

```sh
rvm 3.2.3 do bundle exec rspec spec/services/tiktok spec/jobs/tiktok_sync_job_spec.rb spec/requests/admin/tiktok_integrations_spec.rb spec/requests/webhooks/tiktok_spec.rb
node --test spec/javascript/source_form_selection_test.mjs
# Em gateway/, com banco exclusivamente de testes:
DATABASE_URL=postgres://localhost/unitymob_gateway_test rvm 3.2.3 do bundle exec rspec spec/tiktok_spec.rb spec/grupozap_spec.rb spec/meta_isolation_spec.rb spec/services/retry_failed_events_spec.rb
```

## Contratos oficiais consultados

- [Export leads and postback CRM events](https://business-api.tiktok.com/portal/docs?id=1806817505894402).
- [Subscription API / webhook payload](https://business-api.tiktok.com/portal/docs?id=1810521739537409).
- [Criar subscription](https://business-api.tiktok.com/portal/docs?id=1739092028876801).
- [Listar subscriptions](https://business-api.tiktok.com/portal/docs?id=1739093832125442).
- [Cancelar subscription](https://business-api.tiktok.com/portal/docs?id=1739094758789122).
- [Autenticação Marketing API](https://business-api.tiktok.com/portal/docs?id=1738373164380162).
- [Anunciantes autorizados](https://business-api.tiktok.com/portal/docs?id=1738455508553729).
- [Formulários publicados](https://business-api.tiktok.com/portal/docs?id=1820826387779586).
