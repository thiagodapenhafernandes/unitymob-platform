# Aceite de leads

`Leads::Acceptance.call(tenant:, lead:, actor:, metadata:, claim_statuses: nil, rule_ids: nil)` retorna `accepted`, `already_accepted`, `taken` ou `ineligible`. Exige lead/ator da conta e restaura `Current.tenant` após a chamada.

A linha do lead é travada e dono/status são relidos. Lead sem dono só pode ser reivindicado se o canal fornecer estados elegíveis; usa a primitive existente `claim_unassigned!`, que exige usuário ativo e pode filtrar regras. O avanço do rodízio e a atividade `accepted` participam da mesma transação da reivindicação. Lead com dono só transita de Aguardando Aceite para Em Atendimento quando o ator ainda é o dono. Repetição não produz outra atividade.

- Admin valida regras do bolsão e acesso antes da operação; reivindica somente Aguardando Aceite.
- Link seguro valida token, expiração e destinatário antes da operação; pode reivindicar Novo, Em Atendimento ou Aguardando Aceite. Metadados secure_link/via são preservados.
- WhatsApp valida mensagem de origem, remetente e configuração de vCard; mesmos estados reivindicáveis do link, mantendo via WhatsApp.

Autenticação não é delegada ao serviço. Os estados elegíveis e metadados continuam explícitos por canal. O serviço protege a transição contra redistribuição concorrente; efeitos externos decorrentes de callbacks continuam sujeitos aos contratos atuais, sem promessa de entrega exatamente uma vez.
