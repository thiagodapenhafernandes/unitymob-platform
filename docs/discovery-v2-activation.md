# Discovery V2 — implementação e ativação

Estado: implementação local na branch `codex/whatsapp-extension`. Não publicada em produção. Envio real pelo Resend e instalação nos domínios de produção ainda precisam ser validados após configuração. Central não é alvo deste pacote.

[Diagrama ampliável](architecture/unitymob-discovery.html) · [SVG](architecture/unitymob-discovery.svg)

## Responsabilidades e comunicação

| Origem → destino | Contrato | Responsabilidade |
| --- | --- | --- |
| CRM → Gateway | `POST /internal/discovery/v2/memberships` | Publica identidade, e-mail, conta, estado e versão temporal. Token exclusivo da instância e tenant permitido. |
| Extensão/mobile → Gateway | `POST /discovery/v2/challenges` | Inicia confirmação de e-mail; resposta não informa existência de vínculo. |
| Gateway → API Resend → usuário | Código de seis dígitos, HTTPS na porta 443 | Entrega do código, inclusive para endereço sem vínculos. Não recebe senha do CRM. |
| Extensão/mobile → Gateway | `POST /discovery/v2/verify` | Consome código, retorna somente vínculos ativos em instâncias aprovadas. |
| Extensão → CRM selecionado | Login web + callback Chrome + troca de código | Mantém login, 2FA e política de acesso; valida instância, conta, e-mail da identidade e emissor. |
| Extensão → API do CRM | Bearer restrito, HTTPS, sem redirecionar requisições | Leads, imóveis, histórico, tarefas e ações confirmadas. |
| Mobile V2 → CRM selecionado | Navegação ao login web normal | O aplicativo deixa de coletar senha na tela local; preserva a autenticação do CRM. |
| CRM ↔ Central | Integração de suporte existente | Não participa da descoberta nem emite sessão da extensão. |

O adaptador WA-JS roda no contexto MAIN do WhatsApp. A extensão usa `chrome.scripting.executeScript` e recebe somente projeção delimitada. Não existe um content script permanente intermediando o fluxo atual. O painel conversa com o service worker; não recebe o token do CRM.

## Isolamento, estado e recuperação

- A chave do vínculo é `(instance_id, tenant_id, user_id)`, com índice único. E-mail deixa de ser identidade global.
- Endereço HTTPS vem de `DISCOVERY_INSTANCES`, não do payload enviado pelo CRM ou do usuário. A credencial de uma instância só publica os tenants expressamente permitidos.
- Cadastros, alterações de e-mail/estado/perfil/conta e exclusões enfileiram sincronização V2 quando configurada. Exclusões e mudanças de tenant publicam desativação da identidade anterior. Usuários espelho usam o e-mail de sua identidade de login; atualizações da identidade principal atualizam os espelhos.
- Timestamp do registro de origem impede uma atualização atrasada de substituir uma mais nova. Retry de rede em ActiveJob, até cinco tentativas. Reconciliador manual permite recuperar falhas; não há backfill automático.
- Código: dez minutos, cinco tentativas, uso único, apenas digest HMAC no banco. Desafios e limites vencidos são removidos pela tarefa de manutenção.
- Limites persistidos por janela: início 10/IP e 3/e-mail a cada dez minutos; verificação 30/IP. Legado recebe limite de 30/IP quando o segredo V2 está configurado. Proxy deve sobrescrever headers de IP encaminhados e impedir acesso externo direto à porta do processo.
- A descoberta não autoriza acesso. CRM revalida usuário/tenant/política e o destino do pareamento; a extensão rejeita servidor antigo sem comprovação da conta na troca de código.
- Resultados da descoberta e pareamento ficam no armazenamento temporário da extensão. Credencial e chaves de repetição ficam em `chrome.storage.local`, restritas aos contextos confiáveis, mantendo validade original de oito horas.
- Pacotes com diretórios diferentes não reutilizam a conexão anterior. Trocar conta revoga a conexão atual antes de iniciar outra. Uma conta ativa por vez.
- Gateway indisponível bloqueia nova descoberta, mas sessões já conectadas consultam o CRM diretamente. Revogação/bloqueio são sempre conferidos no CRM; eventual atraso no índice nunca concede acesso.

## Configuração por alvo

Gateway, configuração privada (modelo em `gateway/.env.example`):

- `DISCOVERY_INSTANCES`: JSON com uma entrada por instância; `token` exclusivo (32+ caracteres), `origin` HTTPS canônica do **CRM**, `tenant_ids` permitidos. Confirmar IDs e origens reais antes de ativar. Não assumir que o domínio do site público é o login administrativo.
- `DISCOVERY_SECRET`: segredo aleatório independente (32+ caracteres) para digests e limites.
- `DISCOVERY_MAIL_FROM`: endereço de um domínio verificado no Resend. `RESEND_API_KEY`: chave privada com permissão de envio. O remetente `onboarding@resend.dev` serve apenas para testes com o e-mail da própria conta Resend.
- Não reutilizar o `INTERNAL_API_TOKEN` de webhooks como token de instância V2.

Cada CRM:

- `DISCOVERY_INSTANCE_ID`: chave correspondente à instância cadastrada no Gateway.
- `DISCOVERY_INSTANCE_TOKEN`: somente o token daquela instância.
- `DISCOVERY_GATEWAY_URL`: origem HTTPS aprovada do Gateway.
- Manter o ID da extensão liberado e `BROWSER_EXTENSION_TENANT_IDS` restrito aos tenants autorizados.
- Garantir execução da fila ActiveJob/Solid Queue `default` existente.

## Sequência de publicação

1. Revisar o pacote acumulado da extensão e os arquivos V2; selecionar commits. Não incluir alterações alheias de outros checkouts.
2. Backup do banco do Gateway e revisão do cadastro de instâncias. Publicar Gateway pelo Docker Compose documentado em `gateway/README.md`. Executar `bundle exec rake db:migrate` antes de liberar a aplicação nova. São tabelas aditivas; não há migração destrutiva da rota legada. Ordem operacional: `docker compose build whatsapp-gateway`, depois `docker compose run --rm whatsapp-gateway bundle exec rake db:migrate`, e só então `docker compose up -d whatsapp-gateway` (com backup e configurações já revisados).
3. Configurar Resend/segredos no ambiente privado e agendar `bundle exec rake discovery:cleanup` por hora. Verificar domínio remetente e entrega com um endereço de teste autorizado.
4. Publicar o código da extensão/API e sincronizador nos CRMs Salute e Conexão pelo Mina multistage do projeto. Central não precisa de deploy.
5. Em cada CRM, rodar `RAILS_ENV=production TENANT_ID=<id-validado> bundle exec rake discovery:reconcile` (dry-run). Revisar quantidade/alvo. Depois, repetir com `EXECUTE=1` para enfileirar os vínculos daquele tenant.
6. Conferir Gateway com um usuário de uma conta, um usuário com duas contas e um usuário desativado. Verificar destinos, login/2FA, bloqueio de conta divergente, revogação e persistência. Não salvar notas/tarefas em leads reais no smoke test.
7. Distribuir o pacote Discovery da extensão, não o pacote de desenvolvimento. O Chrome concede acesso apenas ao domínio escolhido em um gesto explícito do usuário; a permissão potencial `https://*/*` é opcional, não acesso concedido a todos os sites.
8. Ativar Mobile V2 em `mobile/www/discovery-config.js` e publicar uma nova versão nativa após validar. `cap sync`/assinatura/publicação não foram executados neste trabalho.

## Compatibilidade e rollback

`/discovery/resolve` mantém `{tenant_url}` para um destino único. Quando há registros V2, eles prevalecem; múltiplos vínculos retornam `409 multiple_accounts` em vez de encaminhar silenciosamente para o último cadastro. Apps antigos mostrarão erro nesse caso e precisam da versão V2 para escolher a conta. Sem registros V2, a rota legada permanece como estava: ainda exige sua aposentadoria após a migração dos clientes para eliminar a consulta pública por e-mail.

Não remova o endpoint nem suas tabelas antigas antes da adoção do mobile V2. Não rebaixe o Gateway durante a transição sem avaliar os dados V2: o binário antigo ignora esses vínculos e volta a resolver pelo índice antigo. Os webhooks Meta permanecem nos contratos atuais e têm testes de regressão no mesmo pacote.

A extensão de desenvolvimento continua em `browser-extension/dist`, apontada para `dev.unitymob.com.br`. A versão com descoberta é gerada em `browser-extension/dist-discovery`:

```sh
UNITYMOB_DISCOVERY_ORIGIN=https://webhooks.unitymob.com.br npm run build --prefix browser-extension
```

Se a ativação V2 precisar ser interrompida, mantenha os CRMs e o Gateway publicados; interrompa a distribuição do cliente novo. Sessões existentes continuam válidas e independentes do Gateway. Nenhuma senha, e-mail de teste real ou segredo foi colocado no pacote.

## Validação local concluída

- CRM: 37 exemplos focados na API da extensão, sincronização do diretório e revogação de vínculos, sem falhas.
- Gateway: 42 exemplos, incluindo descoberta V2, envio Resend simulado, erros de entrega e regressão dos webhooks, sem falhas.
- Extensão: 41 testes, sem falhas; builds de desenvolvimento e Discovery 0.4.0 gerados.
- `zeitwerk:check` e `git diff --check` passaram.
- Interfaces da extensão e mobile verificadas com respostas simuladas para duas contas; nenhum e-mail real foi enviado e nenhum lead real foi alterado.
- Login completo contra Gateway/Resend e CRMs de produção permanece pendente da ativação acima.
