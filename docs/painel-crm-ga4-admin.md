# Painel CRM e GA4 no admin

Pacote aprovado para publicação; configuração da leitura somente na Conexão BC.

## Onde fica

- Dashboard → Leads: o frame de funil existente mostra **Funil comercial e cobertura** em todas as contas, independentemente da conexão externa.
- Integrações → Google → **Analytics**: disponível ao titular com permissão de gerenciar integrações, sem tenant, domínio ou propriedade fixos no código. Abrir a aba não cria configuração nem faz uma chamada ao Google.
- Todas as contas recebem o mesmo painel e menu. Conta sem integração continua sem chamadas ao GA4; abrir o painel não cria configuração. A Salute recebe o código, sem configuração/credencial/ativação de integração.

## Reutilização e atualização

A mesma rota e o mesmo frame assíncrono do dashboard mantêm período, corretor, modalidade, escopo de visibilidade, exclusão de contatos internos e status operacionais inválidos. A consulta nova é `Dashboard::CrmFunnelQuery`, escopada pela conta e pelo conjunto de leads autorizado recebido do dashboard.

Preservam-se também os gargalos por perdas/reaberturas e os links de investigação de leads quentes/mornos existentes. A composição usa `ax_operational_panel`, `ax_field_grid`, `ax_status_list`, `ax_inline_notice`, `ax-table` e os campos e ações de formulário compartilhados. Não há CSS novo nem alteração de temas públicos. O controller Stimulus compartilhado `ax-frame-refresh` recarrega somente o frame a cada 60 segundos, pausa em aba oculta, não sobrepõe um carregamento em curso e remove timer/listener ao desconectar.

CRM é lido novamente enquanto o painel está aberto. O GA4 é consultado sob demanda com cache por conta, versão da configuração e datas por até 15 minutos; não há coleta em segundo plano quando ninguém abre o painel. Falha preserva a última leitura boa por até um dia, com status de desatualizada e data original. Sem resultado válido anterior, exibe indisponibilidade, nunca zero fictício. O processamento do Google pode ter atraso adicional.

## Contratos dos números

- CRM: coorte por criação no intervalo escolhido, com situação/desfechos registrados até a consulta. Leads distintos são IDs de registro, não deduplicação por pessoa/telefone. Não se infere uma sequência de etapas a partir de status atuais.
- Qualificação: qualquer um dos papéis atualmente qualificado; emissão do evento de primeira qualificação continua com a regra já publicada, sem alteração.
- Visita: `visita` e `realizado`, contado uma vez por lead; quantidade de compromissos aparece separada. Agendamento passado ainda aberto é uma pendência de conferência, não visita presumida.
- Proposta: envio documentado por `sent_at`; rascunho não conta. Ganhos usam o contrato `Lead.won_in_crm`, inclusive o fallback legado já existente. Não equivalem a receita/baixa financeira.
- Entrega: eventos CRM persistidos pela data `occurred_at` dentro do período, entre leads visíveis; não apenas os leads criados na coorte. HTTP aceito não comprova processamento.
- GA4: `eventCount` por `eventName`, por data do evento, no total da propriedade. Não são pessoas distintas nem a coorte CRM. Não somar as fontes ou calcular diferença direta como perda. Geração inicial de lead permanece no navegador; o painel não cria outro emissor.
- Totais GA4 ficam restritos ao titular e não são consultados com filtro de corretor/modalidade, pois a propriedade inteira não representa esses filtros. Usuários com escopo próprio mantêm somente seus dados CRM e não recebem totais globais.
- Lacunas mostram ausência de avaliação, visitas vencidas, visitados sem qualificação atual, canal vazio, etapa ausente e cobertura de consentimento/identificador. A base antiga não é reconstruída nem recebe consentimento presumido.

## Configurar a leitura após aprovação/publicação

O usuário informou que ainda não possui conta de serviço. Portanto, o pacote deixa a conexão operacional pronta, mas não declara leitura real validada.

1. Em um projeto Google Cloud, habilitar **Google Analytics Data API** e criar uma conta de serviço específica para leitura. Não usar a credencial de Agenda/FCM nem a chave Measurement Protocol.
2. Na propriedade GA4 da Conexão (431425110), conceder **Leitor** ao e-mail da conta de serviço. Outras contas usam suas próprias propriedades e credenciais.
3. No admin da conta correta, acessar Integrações → Google → Analytics. Informar o ID numérico da propriedade e o JSON, ativar a leitura e salvar. Não enviar o JSON por chat ou versioná-lo.
4. Abrir Dashboard → Leads sem filtro de corretor/modalidade e conferir status, hora, fuso, contagens e eventual aviso de limiares/amostragem. O ID `G-...` é de medição, não substitui o ID numérico da propriedade.
5. Para interromper consultas, desligar a leitura e salvar. Isso preserva credencial cifrada para reconexão e não desliga o envio CRM→GA4, GTM ou Ads.

A configuração nova tem leitura desativada por padrão. Ela não altera `enabled`, `measurement_id`, `api_secret` ou `activated_at` do envio. A credencial é cifrada por Active Record Encryption, filtrada dos parâmetros/logs e nunca preenchida de volta em formulários, inclusive com erro de validação. O backend usa apenas os endpoints oficiais de OAuth e Analytics, escopo `analytics.readonly`, destinos fixos, timeouts e nenhum identificador de contato na consulta.

## Revisão e limites

- Migration aditiva e reversível: três colunas em `ga4_conversion_configs`; sem backfill e sem alterar valores existentes de envio.
- Testes verificam contagem distinta, limites da coorte, isolamento/escopo próprio, integração por conta, ausência de escrita ao abrir, cifragem, não reexibição de chave, endpoint arbitrário rejeitado, cache/falha/stale, permissões e preservação do fluxo anterior.
- Teste de comportamento do refresh cobre aba oculta, frame ocupado, retomada, intervalo mínimo e limpeza.
- Prévia visual usa as views Rails reais e CSS existente, com registros isolados no banco de testes. Não é uma captura de produção.
- Sem credencial de leitura, API e processamento em produção ainda não foram validados. Não há previsão de vendas, custo ou receita fabricados.

Referências oficiais: [Data API — runReport](https://developers.google.com/analytics/devguides/reporting/data/v1/rest/v1beta/properties/runReport), [acesso por conta de serviço](https://developers.google.com/analytics/devguides/reporting/data/v1/quickstart).

## Validação desta revisão

- 112 exemplos focados e de regressão aprovados (dashboard, consultas, integração Google, leitura GA4, captura e entrega existentes), mais uma renderização isolada de prévia.
- Verificação específica do refresh em Node aprovada; Zeitwerk e git diff --check aprovados.
- Migration aplicada, revertida e reaplicada exclusivamente no banco de testes.
- Views reais verificadas em desktop e 360 px; campos, lacunas e leitura pendente acessíveis, sem overflow horizontal do painel. Tabela usa contêiner compartilhado quando precisa de rolagem.
- Sem alteração de SCSS/CSS/temas nesta revisão; nenhum build de estilos necessário. Sem validação de acesso real à Data API, pois ainda falta a conta de serviço informada pelo usuário.
