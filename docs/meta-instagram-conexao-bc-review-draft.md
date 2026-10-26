# Rascunho — Instagram Direct da Conexão BC

Referência consolidada atual: [Revisão Meta Salute + Instagram](meta-access-review-consolidated.md).

Preparado em 22/10/2026. Documento local para revisão; não inserido nem enviado
na Meta. Não modifica o pedido existente Marketing API Access Tier.

App: Unitymob — 1766223014200910.
Implantação piloto Instagram: Conexão BC, tenant 72.
Endereço: https://conexaobc.com/admin/meta_integrations.
Perfil: imobiliariaconexaobc, vinculado à página Conexão BC.

## Pedido proposto

Solicitar acesso avançado para `pages_messaging`, `instagram_basic` e
`instagram_manage_messages`, conforme os recursos demonstrados abaixo. Os três
constavam em acesso padrão, sem análise solicitada na conferência do painel.
Preservar todas as permissões e recursos já aprovados, as seleções de ativos e
os callbacks e webhooks existentes. Não pedir comentários, publicação, insights
ou permissões `instagram_business_*` neste fluxo de login via Facebook.

### pages_messaging — justificativa para revisão

A Unitymob permite que usuários autorizados da imobiliária conectem sua Página
Facebook e o Instagram profissional vinculado para atender contatos no CRM.
Na implantação Conexão BC, a autorização de mensagens da Página é necessária
para concluir a inscrição de mensagens utilizada pelo fluxo Instagram Direct.
O sistema consulta as inscrições existentes e acrescenta messages preservando
leadgen e os demais campos já inscritos. O recebimento de cadastros dos anúncios
permanece independente do atendimento por mensagens.

A permissão será solicitada no login Facebook do administrador do ativo. Não
usamos esse acesso para disparos em massa ou para iniciar conversas não
solicitadas. O escopo demonstrado nesta análise é o atendimento pelo Instagram
Direct integrado ao CRM; não afirmar que há atendimento Messenger implementado.

### instagram_basic — justificativa para revisão

Usamos instagram_basic para identificar o Instagram profissional vinculado à
Página selecionada pelo usuário, consultar seu identificador e nome de usuário
e apresentar qual perfil será conectado ao CRM. O usuário escolhe os ativos
que administra. A integração mantém o vínculo da Página à conta da imobiliária
para evitar encaminhamento de contatos entre contas.

### instagram_manage_messages — justificativa para revisão

Usamos instagram_manage_messages para receber mensagens enviadas ao Instagram
profissional da imobiliária e permitir que um atendente autorizado responda
pelo CRM. Os eventos recebidos pelo gateway são encaminhados à implantação
correta e processados no contexto da conta. A resposta é uma ação explícita do
atendente no histórico do contato, sujeita às limitações da API Meta. A análise
deve demonstrar o recebimento de uma nova mensagem e a resposta dentro da janela
permitida, sem reutilizar mensagens históricas nem enviar mensagens comerciais
não solicitadas.

## Instruções propostas para o analista

RASCUNHO: preencher e testar o acesso de demonstração antes de enviar.

1. Acessar a implantação de demonstração autorizada e entrar com usuário
   exclusivo de análise, com permissão limitada de integrações e atendimento.
   Não fornecer credenciais administrativas de produção.
2. Abrir Integrações > Meta Leads > Acesso e suporte. Iniciar ou renovar o login
   Facebook com usuário autorizado sobre os ativos de demonstração. Conceder
   pages_messaging, instagram_basic, instagram_manage_messages e os acessos de
   Página necessários, preservando ativos e permissões já selecionados.
3. Em Páginas e formulários, selecionar somente a Página de demonstração e
   confirmar o perfil Instagram profissional vinculado. Após autorização,
   atualizar as páginas e verificar que Mensagens do Instagram ficou ativo.
4. Na conta Instagram de teste autorizada, enviar uma mensagem inédita ao perfil
   de demonstração. Confirmar no CRM o mesmo evento no contato e na conta corretos.
5. No CRM, responder pelo atendimento autorizado. Confirmar a chegada da resposta
   na conta remetente. Gravar ambas as pontas do fluxo sem expor dados de clientes.
6. Mostrar Acesso e suporte com as permissões concedidas e comprovar que os
   formulários Lead Ads continuam selecionados e funcionando após a inscrição.

Para suporte técnico, registrar somente IDs de correlação necessários, horários
e resultado. Não anexar tokens, segredos, mensagens de clientes ou logs integrais.

## Tratamento de dados — proposta a confirmar

Finalidade: atendimento dos contatos que procuram a imobiliária pelo Instagram,
identificação do perfil conectado e organização do histórico no CRM.
Categorias pertinentes: identificadores técnicos do perfil, Página e remetente,
nome de usuário quando fornecido, conteúdo e metadados das mensagens processadas.
Acesso deve seguir as permissões dos usuários do CRM e o isolamento por conta.

Estas frases descrevem a finalidade; não substituem as respostas factuais do
questionário Meta. Antes do envio, confirmar responsáveis pelo tratamento,
controlador/operador, subprocessadores efetivos, retenção de mensagens e eventos,
procedimento de exclusão e revogação, atendimento a solicitações de titulares,
medidas de segurança e eventual transferência internacional. Não declarar
retenção, exclusão automática, certificação ou política que não esteja comprovada.

## Bloqueios antes do envio

- Confirmar se a demonstração poderá usar Conexão BC com consentimento do
  responsável ou se será necessária conta separada com dados de demonstração.
- Preparar usuário de revisão e ativos Meta/Instagram de teste acessíveis ao
  analista; confirmar funções sobre Página/Instagram e acesso a mensagens nas
  ferramentas conectadas do Instagram. Não expor dados operacionais da Conexão BC.
- Revisar URL do site e privacidade cadastradas no app: a última conferência
  ainda mostrava endereço NotificaLead; não foi corrigido nesta entrega.
  Confirmar URLs finais e aderência da política ao fluxo Instagram antes de enviar.
- Gravar o fluxo real completo para cada permissão, com recebimento e resposta.
- Confirmar as declarações de tratamento de dados acima.
- Revisar este texto e somente então preparar o pedido no painel Meta, mantendo
  o rascunho de Ads existente e todas as permissões aprovadas.

## Diagnóstico que motivou a alteração

Na investigação da Conexão BC, o token já concedia instagram_basic e
instagram_manage_messages. A descoberta do perfil e a assinatura Instagram do
app foram confirmadas. A assinatura da Página continha apenas leadgen; os logs
de inscrição apontaram erro Meta 200 citando pages_messaging, ausente no token
e no scope do login. A consulta de conversas retornou erro 1/99, inconclusivo.
Essas evidências não equivalem a recebimento ou resposta Instagram validados.

## Pacote de código local e ativação futura

O login compartilhado acrescenta somente pages_messaging aos dez escopos
anteriores. O diagnóstico compartilhado de permissões passa a mostrar esse
acesso. Nenhum token existente é renovado por essa alteração e nenhum job é
executado automaticamente pela edição do código.

O código é compartilhado entre implantações; uma publicação futura em outras
contas também afetará suas novas autorizações. O ajuste pages_messaging foi publicado em ambas as implantações: Salute release
827 e Conexão BC release 410, revisão 99d26560. O piloto central permaneceu fora. Antes dela,
isolar o pacote aprovado do WIP existente e do pacote central ainda não publicado.
Após aprovação/publicação, renovar o login com o administrador da integração,
conferir todas as permissões/ativos, confirmar messages sem remover leadgen e
validar um evento natural até o CRM. Não reprocessar históricos.

## Validação desta entrega

43 testes passaram, cobrindo os parâmetros OAuth reais com todos os escopos
anteriores mais pages_messaging, diagnóstico de concessão/recusa/ausência,
preservação das inscrições existentes, callback legado, sincronização, mensagens
Instagram, resposta e proteção contra redução de permissões. Zeitwerk e
`git diff --check` passaram. Testes de integração Meta usam respostas simuladas;
não houve autorização real, inscrição, envio, deploy nem alteração no painel.
