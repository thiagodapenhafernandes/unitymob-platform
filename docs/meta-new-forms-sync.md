# Meta — busca de novos formulários

22/10/2026. Implementação local, não publicada. Independente do piloto OAuth central.

## Comportamento

- A ação Buscar novos formulários usa o endpoint sync_forms existente e o próprio MetaSyncJob com new_forms_only:true.
- Consulta somente páginas selecionadas e já ativas na integração do usuário autenticado.
- Consulta a listagem paginada da Meta e compara IDs com os formulários daquela página, em uma consulta local. Só os desconhecidos são persistidos, registrados no gateway e incluídos nas regras automáticas já existentes.
- Não renova tokens, páginas, Instagram ou assinaturas no caminho rápido. Não reenvia leads ou eventos históricos.
- Atualizar páginas continua executando o fluxo completo. Login, reconexão e seleção de páginas também mantêm a sincronização completa.
- A rotina de quinze minutos usa o caminho rápido para conexões já sincronizadas e saudáveis. Primeira sincronização, status parcial ou falha continuam no caminho completo para reparo.
- Nova conferência completa diária às03:10, no horário do scheduler, pelo mesmo fan-out existente. Ela atualiza nomes/status de formulários antigos e páginas/autorizações, sem criar outro módulo de sincronização.
- Pendências anteriores não são apagadas pela busca rápida. Página selecionada inativa gera orientação de atualização completa. Falha no registro de um formulário novo gera status parcial; a próxima rotina tenta a atualização completa para reparar.

## Limite explícito

A redução é no processamento local e nas chamadas de registro/inscrição: não foi presumida ordenação dos formulários nem inventado parâmetro since/cursor durável que a API existente não oferece. A consulta à listagem da Meta continua paginada. Não se interrompe na primeira ocorrência conhecida, evitando perder formulários em páginas seguintes. Alterações em formulários antigos e novas páginas ficam para a conferência diária ou Atualizar páginas manual.

## Evidências

74 exemplos passaram nos jobs de sincronização, controllers Meta e callback legado, views e serviços Meta/Instagram. Caso específico:1009 formulários conhecidos mais1 novo resultaram em somente1 registro de rota no gateway, preservando os antigos. Cobertos zero novos, página fora da seleção, pendências anteriores, atualização completa de formulário alterado, seleção do modo na rotina e endpoints manual rápido/completo. Zeitwerk e git diff --check aprovados.

Não houve migration, dependência nova, deploy, mudança Meta ou interrupção da sincronização que já estava em produção. A otimização só entra em vigor após publicação aprovada do pacote compartilhado para Salute e Conexão. Excluir os WIPs do piloto central, schema, lockfiles e outputs desse pacote.

## Arquivos

- app/jobs/meta_sync_job.rb: modo rápido, preservando o caminho completo.
- app/jobs/meta_sync_enabled_integrations_job.rb e config/recurring.yml: seleção da rotina rápida/reparo e conferência diária.
- app/controllers/admin/meta_integrations_controller.rb: ação sync_forms existente agenda o modo rápido.
- app/views/admin/meta_integrations/_pages.html.erb: ação rápida adicional, usando os mesmos botões/ações ax; atualização completa preservada.
- Specs dos jobs, requests e partial existente.
