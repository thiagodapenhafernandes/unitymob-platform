# Disparos WhatsApp e webhooks de automacao

## Diretriz

A interface e do UnityMob CRM. A dinamica operacional deve seguir o que foi validado no NotificaLead: montagem guiada, validacoes antes do envio, preview de audiencia, preview/teste de template, envio controlado, monitoramento e eventos consumiveis pela Automacao.

Nao copiar views, CSS ou arquitetura visual do NotificaLead. Usar Rails, ActiveJob, views admin e componentes `ax-*` do UnityMob.

## Fases

1. Gap map tecnico
   - Identificar as regras essenciais do NotificaLead que evitam disparo errado.
   - Separar dinamica de campanha, motor de envio, dashboard e webhooks.
   - Registrar quais itens entram no UnityMob e quais ficam fora por nao existir o mesmo dominio.

2. Builder de campanha
   - Formulario em etapas: informacoes, template/variaveis, audiencia, agendamento e revisao.
   - Preview de audiencia antes de enviar.
   - Resumo final com riscos: sem template, sem audiencia, agendamento ausente, rate fora do limite.

3. Preview e teste de template
   - Preview do corpo do template usando variaveis mapeadas.
   - Envio de teste para telefone informado.
   - Validacao de template aprovado antes de disparar.

4. Motor de envio robusto
   - Rate limit confiavel.
   - Retry de falhas.
   - Tratamento de erros Meta conhecidos.
   - Bloqueio de duplicidade por lead/campanha.
   - Logs operacionais sem dados sensiveis excessivos.

5. Dashboard de campanha
   - Metricas de criadas, enviadas, entregues, lidas, respondidas e falhas.
   - Lista filtravel de mensagens.
   - Falhas agrupadas por motivo.
   - Atualizacao periodica para campanhas ativas.

6. Webhook na Automacao
   - Acao `send_webhook` com logs, retries e payload padronizado.
   - Teste de endpoint pela interface.
   - Tokens ricos de lead, evento, corretor e campanha.
   - Eventos de campanha WhatsApp disponiveis como gatilhos.

7. Permissoes e validacao final
   - Permissoes proprias do modulo.
   - Specs de services, jobs, requests e builder.
   - Checks Rails, JS e smoke visual.

## Regras do NotificaLead que precisam ser preservadas como dinamica

- Campanha nao deve ser enviada sem template aprovado.
- Usuario precisa ver quantos leads serao impactados antes de enviar.
- Leads sem telefone valido nao entram na fila.
- Lead ja impactado pela mesma campanha nao deve duplicar mensagem.
- O disparo precisa ser pausavel/cancelavel.
- Falhas devem ser rastreaveis e reprocessaveis.
- Resposta do lead deve ser correlacionada com a campanha.
- Eventos da campanha precisam alimentar automacoes.
- Webhooks precisam ser assincronos, com log e retry para erro transitorio.

## Adaptacoes para UnityMob

- Sem multi-tenant por conta nesta fase, porque o checkout atual trabalha no escopo admin existente.
- Sem sistema de creditos ate existir requisito de produto no UnityMob.
- Sem copiar o wizard visual do NotificaLead; usar `ax-*`, contextbar e paineis densos.
- Redistribuicao pos-campanha deve ser desenhada depois sobre o dominio de leads/distribuicao do UnityMob, nao copiada literalmente.
