# Conexão BC: etapas comerciais no GA4

Estado em 19/10/2026: implementação local para revisão. Sem deploy, chave criada, configuração ativada, alteração de tags ou envio de evento de produção nesta etapa. As configurações da Salute foram preservadas.

## Diagnóstico verificado em produção

Consulta somente leitura na conta 72, Conexão Imobiliária, em 19/10/2026. Contagens acumuladas do cadastro, não desempenho de um período:

- 5.904 leads com avaliação de corretor e de gestor vazias.
- Nenhum lead com client_id persistido e nenhum com o novo comprovante de consentimento.
- 33 visitas agendadas e 13 realizadas; uma ligação agendada.
- Uma proposta registrada, em rascunho.
- Etapas “Negócio fechado” e “Ganho” têm stage_type=won; “Finalizado” está como open.

Esses dados não demonstram ausência de trabalho comercial fora do CRM. Demonstram que o cadastro atual não permite atribuir o histórico ao GA4 nem medir qualificação registrada. Não será feito backfill nem inferência de client_id a partir de telefone/e-mail. A coleta nova passa a depender também do preenchimento das etapas pela operação.

## Contrato proposto

| Fato confirmado no CRM | Evento GA4 | Unicidade |
| --- | --- | --- |
| Primeira mudança de não qualificado para qualified por corretor **ou** gestor | qualify_lead | Uma vez por lead; confirmação do outro papel e requalificação não repetem |
| Appointment do tipo visita muda para realizado | visit_completed | Uma vez por compromisso; visitas distintas podem contar separadamente |
| Proposal muda para enviada | proposal_sent | Uma vez por proposta; rascunho, aceite e reenvio não são outra proposta enviada |
| Lead muda para etapa explicitamente tipada won | close_convert_lead | Uma vez por lead; reabrir e ganhar novamente não repete |

A regra de qualificação foi escolhida pelo usuário nesta conversa. Não há resolução automática de divergência corretor/gestor: registra-se a primeira confirmação. Disqualify_lead e reversões comerciais não fazem parte desta entrega.

Não se usa o nome da etapa para inventar visita ou proposta. Finalizado/open não vira venda. close_convert_lead representa negócio declarado ganho no CRM, incluindo sua modalidade; não é purchase, pagamento ou comissão recebida. Aceite de proposta também não comprova venda. Não se envia valor de imóvel como receita ou valor de lead.

O horário é o da confirmação registrada no CRM. O sistema não dispõe de evidência independente de quando uma visita física aconteceu nem de que um link de proposta foi efetivamente entregue. Atualizar tardiamente um compromisso para realizado registra essa confirmação agora, sem inventar um horário histórico de conclusão.

Formulários comerciais de contratação da plataforma (CommercialContractProposal) e compromissos importados em CrmAppointment não são negociações imobiliárias desse funil e ficam fora.

## Alterações de código

- `Leads::Attribution` mantém o contrato existente e acrescenta o aceite/recusa e sua data a partir do cookie recebido no servidor. Parâmetro declarado pelo formulário não concede consentimento. O client_id continua vindo do cookie GA autorizado.
- `Ga4::ConversionRecorder` é o ponto compartilhado que seleciona esses fatos. Os models Lead, Appointment e Proposal têm hooks curtos de registro, sem HTTP. Lead com skip_automatic_routing continua excluído, preservando importações e rotinas que já suprimem integrações.
- `Ga4ConversionConfig` guarda destino, segredo cifrado, data de ativação e opt-in por conta, com enabled=false por padrão. Não utiliza fallback global nem cria configurações automaticamente. Credenciais exigem as chaves AR_ENCRYPTION_* existentes no servidor.
- `Ga4ConversionEvent` guarda um evento persistente na mesma transação do fato comercial, com chave única no banco. Só enfileira a entrega depois do commit. Rollback desfaz o evento. Um problema de captura isolado em savepoint não bloqueia o atendimento.
- `Ga4ConversionDeliveryJob` revalida conta, destino, ativação, idade, consentimento registrado e client_id antes de tentar enviar. Reserva a tentativa de forma persistente antes da rede; execução repetida não reenvia um evento já reservado.
- `Ga4::MeasurementClient` usa somente o endpoint HTTPS oficial /mp/collect, sem URL configurável. Timeouts são limitados e retries HTTP automáticos desabilitados.
- `Ga4ConversionRecoveryJob`, a cada cinco minutos, resgata eventos pendentes que ainda não tiveram tentativa. Tentativas interrompidas ficam uncertain. A rotina só percorre contas explicitamente habilitadas.

Há uma migration reversível criando duas tabelas, com índices de unicidade e foreign keys. Exclusão de lead ou conta remove a telemetria dependente, evitando impedir os fluxos de exclusão existentes. Não há purge periódico adicional nesta entrega; a política de retenção desse registro deve ser definida antes da ativação continuada.

## Dados e consentimento

O payload é uma lista fechada: client_id pseudônimo, horário real do evento, nome do evento, UUID opaco de diagnóstico, business_type, código público do imóvel e lead_source=crm. Client_id e segredo são cifrados no banco novo. Não são encaminhados contatos, notas, mensagens, tokens públicos de proposta, IP, user-agent, endereço, URLs ou IDs internos do CRM.

Não há user_data nem user_id. ad_user_data e ad_personalization são DENIED neste envio de análise, sem ampliar consentimento publicitário. O rastreamento de aquisição já publicado continua no navegador e não é reenviado por esse serviço.

Aceite capturado não é um registro universal de consentimento em tempo real. Uma recusa posterior anotada no lead impede a entrega pendente. Não foi criada identificação por telefone nem sincronização global de revogação entre dispositivos; esse limite precisa constar no processo de atendimento a revogações. A integração não tenta contornar bloqueadores ou recuperar identificadores ausentes.

Não se fabrica sessão ou tempo de engajamento para fazer uma venda tardia aparecer em Tempo real. Compartilhar client_id ajuda a relacionar eventos, mas não garante atribuição de campanha/sessão para negociações concluídas muito depois da visita. Para previsibilidade comercial, o CRM e suas coortes permanecem a referência; relatórios GA4 mostram a parte mensurável.

## Estados de entrega e limite de duplicação

| Estado | Significado |
| --- | --- |
| pending | Registro persistido sem tentativa de rede |
| sending | Tentativa reservada; não pode ser reenviada automaticamente |
| http_accepted | Google respondeu 2xx; ainda não comprova processamento no GA4 |
| rejected | Resposta HTTP fora de 2xx; exige diagnóstico antes de qualquer reenvio |
| uncertain | Timeout/falha sem conclusão ou execução interrompida; exige conciliação |
| skipped | Impedido antes do envio, com skip_reason categorizado |

Motivos de bloqueio: configuração inativa, outro destino, evento anterior à ativação, evento vencido, data futura, consentimento ausente/revogado no registro, identidade alterada ou conta divergente.

A chave única no banco evita duplicar a captura; a reserva persistente evita duas tentativas automáticas. O event_id **não** é tratado como garantia universal de deduplicação do Google para esses eventos. No intervalo entre recebimento remoto e confirmação local, existe incerteza distribuída: escolheu-se não reenviar cegamente. Isso pode exigir conciliação manual em vez de prometer entrega exatamente uma vez. Nenhum evento é deslocado para a data atual para vencer a janela de 72 horas.

## Ativação proposta após aprovação

1. Após aprovação, publicar o pacote no stage conexaoimobiliaria com a migration e verificar o worker default e o agendamento de recuperação. Configuração continua desativada por padrão; não publicar nem configurar a Salute nesta ativação.
2. Revisar a política de retenção/revogação e criar uma chave Measurement Protocol no fluxo existente da Conexão (G-WX6W71NGHX), em canal seguro; não colar segredo no chat nem salvá-lo em arquivos versionados.
3. Criar/habilitar **somente** Ga4ConversionConfig da conta 72 com measurement_id=G-WX6W71NGHX, segredo cifrado e activated_at definido na ativação. Não criar linha para a Salute. Não alterar GTM, Stape, Ads ou integrações da Salute.
4. Validar o payload com o endpoint de debug do Google em procedimento controlado, sem confundir validação de formato com conversão real. O código normal não adiciona debug_mode nem gera eventos falsos.
5. Acompanhar novos leads consentidos e seus fatos comerciais reais. Comparar evento persistido, resposta HTTP e recebimento processado no GA4. Não simular visita, proposta ou venda de cliente para testar.
6. Registrar business_type e os eventos necessários no relatório da Conexão. Não importar automaticamente todas as etapas ao Ads, pois isso pode somar várias conversões para o mesmo negócio. Escolher o objetivo de otimização em outro recorte.

Sem configuração/identidade/consentimento, nenhuma chamada é feita ao Google. Desativar o config interrompe novos registros e bloqueia entregas pendentes. Voltar o código não exige apagar o histórico: depois de usar em produção, preservar as tabelas e evidências em vez de executar rollback destrutivo da migration.

## Uso para decisões

Medir por coorte de entrada, canal e modalidade: taxa lead→qualificado; qualificado→visita realizada; visita→proposta enviada; proposta→negócio ganho; e tempo entre etapas. Reportar contagens absolutas e cobertura de consentimento/client_id ao lado das taxas. O funil real pode pular etapas; não preencher eventos ausentes artificialmente.

Antes de prever vendas, melhorar o preenchimento da qualificação e os registros de visitas/propostas. Sem essa disciplina, um funil com poucas conversões registradas pode refletir falta de registro, não falta de resultado. Comissão/receita líquida exigem fonte financeira reconciliada e estão fora desta implementação.

## Validação local

- 92 exemplos focados passaram: registro, entrega, privacidade do payload, cifragem, isolamento entre contas, rollback, deduplicação e regressões de atribuição, webhook, agenda e propostas.
- Contratos compartilhados: 389 exemplos, 386 aprovados e três falhas preexistentes em spec/lib/admin/dark_theme_component_contract_spec.rb (painéis, inventário e seletor journey_explorer), fora deste pacote.
- Migration aplicada, revertida e reaplicada somente no banco de testes.
- Zeitwerk e git diff --check passaram. Sem mudanças de CSS/JavaScript nesta implementação, sem build de interface necessário.
- Nenhuma chamada real ao Measurement Protocol nos testes; cliente HTTP foi simulado. A validação com chave e processamento real do Google permanece para a ativação autorizada.

## Referências

- https://developers.google.com/analytics/devguides/collection/ga4/reference/events
- https://developers.google.com/analytics/devguides/collection/protocol/ga4/reference
- https://developers.google.com/analytics/devguides/collection/protocol/ga4/sending-events

O Google documenta que 2xx significa recebimento HTTP, sem garantir processamento, e que eventos retrodatados têm janela de até 72 horas. O período de uma negociação não muda a data do evento: uma venda futura é enviada quando acontece, não na data antiga da aquisição.
