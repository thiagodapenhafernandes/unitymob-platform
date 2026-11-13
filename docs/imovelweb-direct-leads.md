# Conector direto Imovelweb — Unitymob

Implementação de 03/11/2026. **Recebimento desativado; homologação pendente.**
A publicação do código e das migrations não autoriza ativação do canal.
A Unitymob é a integradora; a Salute é a cliente piloto. O conector atende qualquer
conta e permite mais de uma conta anunciante por tenant. Nenhum código da Salute,
CNPJ, ID de imóvel ou configuração de produção está embutido na implementação.

## Fronteiras preservadas

- XML, geradores, tokens dos feeds e regras de publicação não são alterados.
- URLs, autenticação, parser e processamento do Grupo OLX permanecem separados.
- Reaproveita `Leads::Intake`, fidelização, distribuição, Solid Queue e o worker
  assíncrono do Gateway. A regra de origem Portais reconhece `Imovelweb`.
- Recebimento não depende de `PortalIntegration.enabled/leads_enabled`, pois esses
  campos também atendem a publicação/compatibilidade de outros canais.
- Nenhum histórico é importado, reenviado ou redistribuído automaticamente.

## Fluxo

1. Credenciais `client_credentials` da **Unitymob** ficam só no Gateway.
2. Cada conexão recebe um `client_code` UUID global, independente de IDs locais.
   O cliente autoriza a associação no portal usando esse código. Filiais/segunda
   conta anunciante usam conexões/códigos distintos. Não presumir que o número
   47294717 é o `clientCode` definido para a nova interface.
3. Gateway recebe `POST /webhooks/imovelweb/sandbox` ou `/production`, autentica
   Bearer dedicado ao ambiente, exige código de cliente conhecido e rota ativa.
4. O callback é normalizado e gravado na fila durável antes de responder 202.
   O worker existente encaminha depois, com assinatura HMAC ligada à rota.
5. Rails recebe `POST /webhooks/imovelweb/:route_key`, valida assinatura, conta,
   ambiente, autorização e ativação. Persiste recibo criptografado e agenda job.
6. Job resolve o imóvel **somente** pelo mapa da conexão. Recibos desconhecidos,
   conflitantes ou sem contato válido ficam em quarentena. Nenhum lookup global.
7. Reenvio usa `eventId`, não ID de contato: não duplica lead nem redistribui.
   Nova manifestação segue as regras atuais de complemento/fidelização da conta.
   E-mail válido sem telefone é aceito exclusivamente no canal direto.

O Gateway mantém somente os campos necessários; CPF e identificadores pessoais
extras não são encaminhados/armazenados por este conector. Recibos Rails são
criptografados; job recebe apenas o ID do recibo; logs do callback filtram contato.
Os recibos no Gateway seguem o armazenamento/controle de acesso já existente no
serviço, contendo dados de contato. Não são enviados aos mirrors genéricos.

## Preparação local e homologação Salute

As tarefas Rails usam RVM 3.2.3. Execute com o ambiente e banco local/de homologação
explicitamente selecionados. O deploy do código pode ser feito com o canal desligado. Não execute os passos
de autorização/ativação em produção antes da homologação com a Salute.

1. Aplicar `db:migrate` no Rails e no Gateway **de homologação**.
2. Configurar as chaves de Active Record Encryption no CRM. Sem elas o canal
   permanece bloqueado. Configurar também, no CRM:
   - `IMOVELWEB_RECEIVING_ENABLED=false` (padrão)
   - `IMOVELWEB_GATEWAY_FORWARDING_SECRET` (exclusivo, >=32 caracteres)
   - variáveis existentes do Gateway (`WHATSAPP_WEBHOOK_GATEWAY_URL`,
     `WHATSAPP_WEBHOOK_GATEWAY_INTERNAL_TOKEN`)
     conforme `Meta::WebhookGatewayClient`, e `APP_HOST` HTTPS do CRM de teste.
3. Preparar conexão desligada:

   ```sh
   TENANT_ID=<tenant-local-da-Salute> ENVIRONMENT=sandbox rvm 3.2.3 do bundle exec rake imovelweb:prepare
   ```

   A saída informa `connection_id` e `client_code`. Guardar ambos; não recriar a
   conexão a cada tentativa. A tarefa não acessa o portal e não ativa nada.
4. Pedir ao suporte credenciais sandbox da Unitymob, origem HTTPS da API,
   identificador `[INTEGRADOR]` do botão Login e vínculo ReadOnly. O botão oficial
   brasileiro usa `https://loginbr-open.navent.com/[INTEGRADOR]/[CODIGOINMOBILIARIA].js`.
   A autorização é feita pelo administrador/supervisor do anunciante. **Não há
   tela nova de autorização nesta entrega:** a preparação é assistida pelo suporte.
   Se o suporte habilitar diretamente, exigir confirmação do código atribuído.
5. Confirmar a associação do cliente por canal autenticado/API. O push GET de
   confirmação descrito na documentação não é usado como prova de autorização,
   pois não documenta assinatura. Só após comprovação, registrar `authorized_at`
   na conexão local/de homologação.
6. Associar **um** anúncio de teste à interface de leitura da Unitymob. No Gateway:

   ```sh
   ENVIRONMENT=sandbox CLIENT_CODE=<uuid> REFERENCE=<codigo-local> EXTERNAL_ID=<id-navent> bundle exec rake imovelweb:associate_listing
   ```

   É dry-run; repetir com `APPLY=true` somente após validar os valores. Isso usa
   apenas o endpoint de associação ReadOnly, não publicação/edição do anúncio.
   Depois registrar o mesmo mapa no CRM:

   ```sh
   TENANT_ID=<tenant> CONNECTION_ID=<conexao> HABITATION_ID=<imovel-do-tenant> REFERENCE=<codigo-local> EXTERNAL_ID=<id-navent> rvm 3.2.3 do bundle exec rake imovelweb:map_listing
   ```

7. Configurar no Gateway as variáveis sandbox listadas em `.env.example`.
   Cadastrar callback EN e assinar ambos os eventos:

   ```sh
   ENVIRONMENT=sandbox CALLBACK_URL=https://<gateway-de-teste>/webhooks/imovelweb/sandbox bundle exec rake imovelweb:configure_callbacks
   ```

   Dry-run por padrão. `APPLY=true` é uma alteração remota explícita. A tarefa
   confirma a URL sem imprimir o segredo retornado pela API. Não executar para
   production nesta etapa. Se uma assinatura falhar, a tarefa falha; repetir
   depois da correção é seguro (PUTs idempotentes).
8. No ambiente de homologação, iniciar o worker `webhooks:work` com
   `GATEWAY_ASYNC_DELIVERY_ENABLED=true`. Habilitar o switch Imovelweb nos dois
   serviços e **apenas a conexão sandbox autorizada** (`enabled=true`).
   Sincronizar a rota com `TENANT_ID=... CONNECTION_ID=... rake imovelweb:sync_route`.
   Esta tarefa apenas reflete o estado existente e não autoriza/ativa a conexão.
9. Solicitar eventos sandbox ao suporte (`CONTACTO` e `CONTACTO_MENSAJE`). A API brasileira
   documenta `/v1/callbacks/geracao/eventos`; usar códigos reais de teste.
   Conferir telefone, e-mail sem telefone, interesse no imóvel e distribuição.
10. Reenviar o mesmo evento e provar que recibo, lead e distribuição não duplicam.
    Repetir com nova mensagem do mesmo contato, conta errada, assinatura inválida,
    imóvel não mapeado e mesmo código de imóvel em outro tenant.

Nenhuma tarefa marca autorização ou habilita recebimento automaticamente. Alterar
`enabled`/`authorized_at` é uma operação de suporte explícita após confirmação.
Não se deve manipular XML para fazer essa habilitação.

## Monitoramento, pausa e recuperação

- `TENANT_ID=... CONNECTION_ID=... rake imovelweb:status`: status e totais por motivo,
  sem imprimir contatos.
- Pausar a conexão (`enabled=false`) e sincronizar rota impede novas entregas.
  O job também revalida o estado. Switch global Imovelweb do Gateway pausa a
  seleção de eventos Imovelweb no worker sem parar os outros provedores.
- Gateway responde erro para conta desconhecida/desligada, para que o portal
  possa reenviar; não confirma uma entrega que não tenha dono seguro.
- Eventos aceitos respondem 202 após persistência, sem rede no request; medir o
  SLA de 1,5 segundo na homologação, incluindo proxy, banco e carga reais.
- Retry no Gateway segue a fila existente (10 tentativas); falhas esgotadas ficam
  registradas. Para um único recibo corrigido: `EVENT_ID=<id-local>
  rake imovelweb:retry_event`, dry-run salvo `APPLY=true`. Não reprocessar backlog geral.
- No CRM, falhas transitórias usam retries do job (5 tentativas); jobs esgotados
  ficam no Mission Control. Quarentenas exigem corrigir o vínculo/dado e usar
  `imovelweb:retry_receipt` para **um recibo**, dry-run salvo `APPLY=true`.
- Se o enfileiramento Rails falhar, o recibo pending fica durável; o Gateway
  recebe erro e a próxima entrega agenda novamente sem sobrescrever o payload.
- Mensagem/data/tipo são mantidos; a data original não substitui `created_at`.
  Não se inventa venda/locação: o payload de callback não garante esse campo.

## Pendências externas e limites explícitos

- Credenciais e permissão ReadOnly da Unitymob, vínculo real da Salute e anúncios.
- Documento mistura nomes/idiomas e exemplos inconsistentes. O callback configurado
  é EN, que inclui `clientCode`. PT/ES com código de cliente também são aceitos.
  EN2 sem identificação de conta é recusado: nunca rotear só por código de imóvel.
- Confirmar API regional HTTPS com suporte. Não inferir sandbox/produção de exemplos
  antigos HTTP. Client usa Bearer, token por expiração e uma renovação em HTTP 401.
- Telefone/WhatsApp são tipos de consulta do portal, não captura de conversas de
  WhatsApp. A cobertura real brasileira precisa ser demonstrada na homologação.
- Recebimento para imóvel ainda não associado fica em quarentena, preservado para
  correção explícita. Sem contato utilizável, não criar cadastro fictício.
- Nenhum teste de carga/SLA real, ativação, credencial ou chamada remota foi feito.

## Fontes consultadas

- [Autenticação](https://open-classifieds.notion.site/bra-api-uso-da-api-autenticacao)
- [Callbacks, SLA, reenvios e formatos](https://open-classifieds.notion.site/5-Callbacks-API-29b3593785528101b2fde522463e8fd5)
- [ReadOnly e associação de anúncios](https://open-classifieds.notion.site/8-Integra-o-ReadOnly-API-29b359378552810992b8cdb02aed23cf)
- [Autorização das imobiliárias](https://open-classifieds.notion.site/9-Associar-Imobili-rias-2b8359378552800fa785c3d124fa3137)

## Validação local

- Testes de recebimento, vínculo por conta, reenvio, complemento, e-mail sem
  telefone, quarentena, rollback do lead, assinaturas e tarefas dry-run.
- Regressões Rails de Intake, distribuição, webhooks/jobs OLX, workspace de Portais,
  feeds XML e serializador OpenNavent.
- Suíte completa do Gateway, incluindo normalização, fila assíncrona, retry,
  isolamento, cliente API e tarefas de configuração.
- `zeitwerk:check`, sintaxe Ruby e `git diff --check`.
- Migrations Rails/Gateway aplicadas, revertidas e reaplicadas em bancos de teste.
- Não executados: homologação remota, medição real de SLA, deploy ou ativação.

## Revalidação do sandbox brasileiro — 12/11/2026

O Swagger público informado pelo suporte (`api-br.sandbox.open.navent.com`,
`/v2/api-docs?group=opennavent-realestate`) usa os caminhos brasileiros
`/v1/configuracao/callbacks`, `/v1/configuracao/callbacks/{evento}` e
`/v1/imobiliarias/{codigoImobiliaria}/anuncios/{codigoAnuncio}/asociar/{idAnuncio}`.
O cliente e os testes locais foram alinhados a esse contrato, mantendo HTTPS obrigatório.

A documentação HTTP respondeu, mas HTTPS/443 deu timeout na estação e no servidor.
Nenhuma credencial foi transmitida por HTTP. Autenticação e geração de eventos remotos
continuam pendentes da confirmação da origem HTTPS pelo suporte, do vínculo da conta
e dos identificadores de teste. Não houve deploy nem ativação nesta revalidação.

O chamado SB-129147 recebeu resposta esclarecendo Unitymob como integradora e
Salute como piloto; callbacks ficam globais no Gateway por ambiente, com roteamento
por `clientCode` e autorização por conta, inclusive para futuros clientes.

## Bloco de vínculo por conta no admin

A tela existente de Portais, nas abas Imovelweb e Imovelweb 2, compartilha o bloco
“Vínculo com a Unitymob”. O formulário salva somente `advertiser_code` (código da
conta anunciante), em uma conexão de produção desativada e não autorizada.
`client_code` provisório é apenas identidade interna do rascunho; não é exibido
como código confirmado pelo portal. GET não prepara conexões automaticamente.

As ações create/update exigem gerenciar integrações, limitam consultas ao tenant
corrente e não aceitam ambiente, tenant, credenciais, ativação ou autorização
por parâmetros. Conexões sandbox, habilitadas ou já autorizadas não são editáveis
nesse formulário. Nenhuma rota é sincronizada ao salvar; publicação de imóveis,
feeds, tokens e distribuição permanecem independentes.

Conexões, ambiente, clientCode confirmado, última entrega processada e contagens
de recibos são apresentados apenas para a conta atual, sem payloads de contato,
segredos ou valores de credenciais. Credenciais da integradora e chaves de callback
continuam exclusivamente no Gateway, separadas por ambiente.

Autorização comercial e produção continuam pendentes nesta interface: não há
botão funcional de autorização nem interruptor para ativar recebimento. O fluxo
oficial de consentimento e a confirmação do clientCode dependem do portal; a
identidade imutável de conexões existentes não é alterada pelo formulário.

A migration `20261113130000` adiciona o código anunciante opcional e sua unicidade
por tenant/ambiente, preservando conexões existentes sem backfill ou ativação.
