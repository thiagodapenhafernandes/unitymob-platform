# Contingência da distribuição de leads

Implementação local de 08/10/2026. Não representa confirmação de deploy ou de ativação para Salute/Conexão.

## Configurar pela interface

1. Criar uma regra final, por exemplo **Central de atendimento**. Preferir Rotativo, com participantes ativos e habilitados a receber leads. Ajustar horário e check-in à escala real da central.
2. Se a central deve receber **somente encaminhamentos**, deixar as origens de entrada desmarcadas nela. Caso contrário, ela também pode ser encontrada normalmente pelos seus filtros e pela ordem de busca das regras.
3. Nas regras de origem, abrir **Encaminhar para outra regra**, ativar, selecionar a central e escolher os motivos:
   - Nenhum corretor elegível: espera configurável; zero é imediato.
   - Fora do horário: imediato, quando escolhido.
   - Bolsão sem alguém assumir: prazo desde a primeira disponibilização do ciclo; reavisos não reiniciam.
   - Prazo total sem aceite: prazo desde o começo do ciclo, independente de rodízios/reavisos.
   - Regra desativada: pendentes são encaminhados na varredura, sem mexer em atendimentos iniciados.
4. Em **Configurações de Leads → Prazos e automação → Entradas sem regra compatível**, selecionar o destino padrão da conta. Deixar vazio preserva triagem manual.

Gatilhos começam desligados nas regras e o destino padrão começa vazio. Não existe configuração automática de uma central ou seleção de corretores para clientes existentes.

## Comportamento

- Um encaminhamento automático por ciclo, com destino final da mesma conta. Autorreferência, cadeia A→B→C e ciclos A→B→A são bloqueados pela validação; a execução também verifica o destino.
- Encaminhamento utiliza o mesmo cadastro. A nova distribuição segue o modo, participantes, disponibilidade e horário do destino, mas não exige casar seus filtros de origem/campanha/formulário.
- Fidelização/atendimento válidos são avaliados antes de contingência; importações sem ciclo operacional, eventos repetidos e registros encerrados/arquivados não entram na varredura.
- Consulta nova que exige reabertura/redistribuição inicia novo ciclo, limpando marcadores anteriores. Complemento que mantém atendimento não reinicia o cronômetro de distribuição.
- O ciclo persiste entre tentativas e redistribuições por reserva vencida. Uma reserva vencida no destino final segue nele, sem retornar à regra de origem.
- Sem disponibilidade no destino, status **Represado**, marcador de contingência pendente e histórico com motivo. Varredura tenta novamente; aviso push à gestão é tentado uma vez por encaminhamento, respeitando disponibilidade de entrega do usuário/transporte.
- Se houver responsável definido manualmente enquanto aguarda contingência, a varredura preserva a atribuição e encerra a pendência.
- Gestão reconhecida pelos controles existentes: dono da conta ou permissão de gerenciar regras de distribuição. Histórico sempre disponível conforme permissões da ficha, mesmo sem push entregue.
- Rotativo entrega para um responsável. Bolsão no destino é permitido, porém ainda depende de alguém assumir. Usuário ativo não é garantia de atendimento humano.

## Operação e persistência

Migration: `20261008150000_add_lead_distribution_contingency.rb`.

- `distribution_rules`: habilitação, destino, motivos e três prazos.
- `lead_settings.default_distribution_rule_id`: destino sem regra compatível.
- `leads`: início do ciclo, origem/destino da contingência, momento/motivo e pendência.
- Timeline: `contingency_forwarded`, `contingency_pending` e atividades normais da distribuição.
- `Leads::ContingencySweepJob`, fila default, a cada minuto em development e production. Execução por conta e travamento do lead compartilhado com o aceite; erros de um lead não interrompem os outros.
- Segurança adicional em `Leads::DistributorService`, `Leads::PocketExpirationService` e formulários públicos.
- Campos e seletores usam componentes `ax-*`. O seletor de destino é compartilhado entre regras e configurações da conta.
- `ax-checkbox-chips` observa mudanças de disabled para sincronizar aparência/acessibilidade ao abrir/fechar painéis condicionais.

## Conferência após publicar

1. Migration aplicada, processo de filas e agendamento recorrente atualizado.
2. Criar lead em uma regra sem elegíveis: um cadastro, uma atividade de encaminhamento, destino correto.
3. Confirmar manutenção de atendimento/fidelização e bloqueio de cadastro duplicado.
4. Confirmar destinos indisponíveis como Represado, aviso/timeline e retomada após disponibilidade.
5. Confirmar bolsão e prazo total, sem renovação por reaviso/tentativa.
6. Aceitar antes da contingência e confirmar que a gestão não perde o atendimento.
7. Confirmar que uma consulta histórica C2S não entra no encaminhamento.
8. Confirmar que o destino padrão só recebe entradas sem regra compatível, mantendo registros históricos e atendimentos válidos.

Rollback da migration remove a configuração e os marcadores de contingência, mantendo cadastros e histórico de atividades. Ajustar o código em conjunto com o rollback, pois o código novo depende das colunas.
