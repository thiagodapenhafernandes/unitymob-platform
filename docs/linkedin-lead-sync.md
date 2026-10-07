# LinkedIn Lead Sync

## Uso

- Integrações → LinkedIn: conectar e escolher contas de anúncios.
- Regras de distribuição → LinkedIn Ads: escolher campanhas → formulários e equipe.
- Campanhas vazias = todas as campanhas das contas selecionadas. Formulários vazios = todos os formulários das campanhas escolhidas, inclusive novos após atualização.
- A conexão é compartilhada pelos administradores autorizados do tenant; a pessoa que autorizou o acesso fica registrada.
- O recebimento começa na ativação de cada conta, sem importação histórica automática. Desmarcar uma conta interrompe seu recebimento; reativá-la estabelece um novo marco.
- Desconectar preserva leads e recibos de idempotência. Excluir o usuário que autorizou também remove sua conexão.

## Configuração da plataforma

O aplicativo deve estar aprovado para **Lead Sync API**, com `r_marketing_leadgen_automation` e `r_ads`. A autorização do usuário precisa cobrir a conta de anúncios e a página empresarial associada.

Defina no servidor (não na tela do cliente):

- `LINKEDIN_CLIENT_ID`
- `LINKEDIN_CLIENT_SECRET`
- `LINKEDIN_REDIRECT_URI`: URL HTTPS exata cadastrada no aplicativo, terminando em `/admin/linkedin_integration/callback`. Cada ambiente deve cadastrar sua URL de retorno.
- `LINKEDIN_API_VERSION`: padrão `202601`; atualizar antes do encerramento dessa versão.
- `AR_ENCRYPTION_PRIMARY_KEY`, `AR_ENCRYPTION_DETERMINISTIC_KEY`, `AR_ENCRYPTION_KEY_DERIVATION_SALT`: chaves estáveis do Active Record Encryption já usadas pela plataforma.

Tokens são criptografados. OAuth verifica state, prazo, usuário e tenant antes de salvar. O cliente não informa segredos nem URLs de webhook.

## Recebimento

`LinkedinSyncEnabledIntegrationsJob` agenda `LinkedinSyncJob` a cada minuto no Solid Queue, fila `sync`. O worker e o scheduler precisam estar ativos. Recursos de campanhas/formulários são atualizados a cada 15 minutos ou pelo botão de atualização. Esta versão consulta a API, sem assinatura de webhook.

Cada conta mantém o marco inicial e o cursor da última consulta bem-sucedida. A sobreposição de dez minutos cobre disponibilização tardia nesse intervalo. Falhas de acesso em uma conta não impedem as demais. Falhas não avançam o cursor da conta afetada; o job retenta e mostra mensagem segura na integração. Respostas de teste são ignoradas. Falhas persistentes ficam nas execuções falhas do Solid Queue.

A unicidade de recibos por tenant + ID de resposta impede dupla entrada/distribuição, inclusive após complemento ou exclusão do lead. O lead nasce sem corretor e segue `Leads::RoutingService`, preservando rodízio, represamento, fidelização e notificações existentes. Sem regra compatível, continua salvo sem atribuição.

Nome, telefone/e-mail, campanha, formulário, perguntas respondidas e consentimentos são preservados. A ausência de telefone é permitida somente para leads nativos LinkedIn com e-mail válido. A listagem reutiliza a identidade LinkedIn existente; o atendimento mostra as respostas no desktop e mobile.

## Validação externa após habilitação

Conectar com usuário autorizado, escolher uma conta e configurar uma regra. Gerar uma submissão real no formulário e conferir recebimento, atribuição, origem, respostas e notificações. Repetir a consulta deve manter um único recibo/lead. Leads marcados como teste pela API não entram no CRM.

Sem credenciais aprovadas, os testes automatizados usam respostas simuladas; eles não confirmam aprovação ou acesso real no LinkedIn.

Referências: [Lead Sync](https://learn.microsoft.com/en-us/linkedin/marketing/lead-sync/leadsync?view=li-lms-2026-01), [acesso](https://learn.microsoft.com/en-us/linkedin/marketing/lead-sync/getting-access-leadsync?view=li-lms-2026-01), [OAuth](https://learn.microsoft.com/en-us/linkedin/shared/authentication/authorization-code-flow).
