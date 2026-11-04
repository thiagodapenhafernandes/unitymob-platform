# Salute — preparação das demandas de 04/11/2026

Este pacote é local. A auditoria do banco de produção foi somente leitura. Não houve deploy, alteração de responsáveis, configuração de filas, ativação de conectores ou envio de mensagens.

## Entrega de código

- Filas: ordenar a listagem sem mudar o desempate de distribuição; arquivar desativando a regra, mantendo seus vínculos e histórico; consultar arquivadas e restaurar inativa. O endpoint antigo de exclusão conserva as proteções existentes.
- Horários: `Sem restrição`, `Somente no horário` e `Fechado o dia todo` por dia. O modo novo é explícito em `represamento_schedule[day][mode]`. Configurações antigas com `active=false` continuam sem restrição; nada fecha automaticamente. A programação continua condicionada ao represamento e à contingência existentes.
- Cadastro de imóvel: confirmação de saída interna via modal compartilhado, com continuar, sair sem salvar e salvar. Erro de validação conserva as alterações. Fechar/recarregar a aba continua usando a proteção nativa do navegador.
- Corporate: título da vitrine editável nas configurações da Home, por tenant. Padrão preservado: `Private Corporate`. A opção usa o mesmo componente nos temas default, saluteimoveis, conexaoimobiliaria e salute_luxury, sem condição por marca.
- WhatsApp: isolamento de conversas por número é opt-in em `WhatsappBusinessIntegration#separate_conversations_by_number`. Cadastro, entrada, campanhas, testes, automações e abertura pelo lead usam o escopo compartilhado. Há chave única por tenant, número e telefone/BSUID. Uma conversa identificada não troca para a credencial principal se seu número estiver sem envio configurado.
- Atendimento: `WhatsappSenderNumber#administrative_inbox_enabled` controla a presença no inbox e o fluxo receptivo. O padrão é ligado para manter as contas atuais. O botão de cartão de contato das notificações continua tratado antes do fluxo receptivo.
- Notificações sem e-mail: novas definições `lead_distribution_alert_no_email`, `lead_pool_alert_no_email` e variantes `_v2` com cartão. São cinco variáveis: corretor, origem, nome, telefone/link e outros dados/link. Os templates atuais não são alterados nem substituídos. Os novos precisam de aprovação e seleção nas configurações de notificações da conta.

A ordenação e o arquivamento mantêm as primitivas existentes. A grade de horários usa os campos compartilhados e tabela com rolagem; o modal reutiliza o foco, teclado e espaçamentos de `ax_quick_modal`. Não há CSS específico novo.

## Auditoria de responsáveis

Comando sem escrita, com conta obrigatória:

```sh
TENANT_ID=1 rvm 3.2.3 do bundle exec rake external_lead_migration:audit_owners
```

O serviço compara os metadados C2S já armazenados, não consulta o estado atual do C2S. O relatório detalhado fica em `outputs/salute-demandas-2026-11-04/`, fora do pacote de deploy.

Snapshot de 04/11: 15.728 registros para análise; 4.719 com seller vinculado e responsável diferente/ausente; 11.009 sem vínculo com usuário local ativo. Há 94 com aceite local e 465 com distribuição ou decisão operacional local. As categorias se sobrepõem. São pendências para conciliação, não 15.728 erros confirmados.

Os leads 41627 e 41657 possuem aceite de responsáveis locais após redistribuições por prazo expirado. O primeiro recebimento, a última distribuição, o seller externo e o aceite constam no relatório. Não sobrescrever esses responsáveis em lote. O histórico C2S pode estar desatualizado; comparar o campo de responsável atual da planilha/CRM com o recebimento original antes de propor mudanças individuais.

## Configurações da Salute a revisar após publicação aprovada

1. Confirmar os dois números cadastrados e suas credenciais. A conta estava com o principal marcado `pending`, enquanto o remetente de notificações estava `connected`; isso não comprova falha real da conexão.
2. Habilitar isolamento por número na conta. No 47 2122-8669, desligar participação no atendimento administrativo; manter notificações. No 47 3311-1067, manter atendimento e o fluxo interno. Não transferir mensagens antigas automaticamente: o isolamento vale para os históricos associados a cada número, e um legado sem número permanece intacto.
3. A migração substitui os índices únicos globais por índices por número. Não desativar o isolamento nem reverter a migration se já houver múltiplos históricos do mesmo contato. O sistema bloqueia essa união; exige conciliação explícita dos dados.
4. Definir com a operação os dias/horários das filas DDS e configurar os modos. O estado atual de todos os dias desmarcados não deve ser interpretado como fila fechada.
5. Definir `Salute Corporate` no campo da Home. Demais contas mantêm seus títulos.
6. Submeter os novos templates sem e-mail e só selecioná-los após aprovação. Não editar o contrato de variáveis de templates que continuam em uso.

## Imovelweb

O conector direto já estava publicado na revisão de produção `b508b3e3`. A Salute não tinha conexão cadastrada, o gate `IMOVELWEB_RECEIVING_ENABLED` estava desligado e não havia recibos associados à conta.

Não desligar o C2S nesta preparação. Seguir `lib/tasks/imovelweb.rake`: preparar conexão desativada, conferir ambiente e autorização do portal, mapear imóveis, sincronizar rota, validar o recebimento ponta a ponta e somente então planejar o corte. Preparar conexão, sincronizar rota, ativar recebimento e reprocessar recibos são operações distintas e não foram executadas.

## Evidência nova: modalidade diária na captação

Ao revisar novamente a conversa, foram encontradas mensagens das 17h às 17h13 que não faziam parte do primeiro recorte (até 14h48). Elas identificam o imóvel 9822 e mostram o cadastro como aluguel anual com preço por diária.

Consulta somente leitura confirmou o imóvel 9822 (ID 23894) em produção com `status=Aluguel`, `intake_modalidade=locacao_diaria` e fotografia inicial de 02/11/2026 com `Status comercial=Aluguel` e `Modalidade da captação=Locação diária`. O título atual já difere da imagem e menciona temporada; não foi alterado nesta tarefa.

A causa reproduzida era o mapeamento de modalidade no model e em dois caminhos do controller, que convertia tanto diária quanto anual em `Aluguel`. O mapeamento agora é compartilhado: diária → `Diária`; anual → `Aluguel`; venda e o fluxo de divisão de ambos preservam seu contrato. Reabertura de diária sem modalidade gravada também é reconhecida. Não há atualização automática de registros antigos.

A Central do imóvel agora omite linhas vazias e seções sem informação, preservando a fotografia original e a restrição dos contatos do proprietário. Valores explícitos, inclusive zero e Não, não são descartados por inferência. Os históricos antigos não registram se um valor padrão foi explicitamente preenchido pelo corretor.

Depois de revisão e aprovação, avaliar a correção individual do status do 9822 para `Diária`, sem reescrever sua fotografia inicial. Não foi feita correção em produção nem em massa.

## Pontos sem defeito reproduzido

- Status comercial: o campo existe no formulário compartilhado, sem condição por imóvel. A imagem de hoje mostra o código 6099 com o campo. O teste de renderização garante campo e modal únicos, mas não reproduz desaparecimento no navegador.
- Links: a Salute usa links seguros de sete dias e controla acesso conforme responsável/aceite. Não abrir links reais como teste: o GET registra acesso e pode efetivar atendimento. Sem link afetado identificado, não renovar, reenviar nem retirar a proteção.
- Cadastro manual: continua notificando por push, conforme regra vigente. Não foi adicionado WhatsApp para todo cadastro manual; o teste do fluxo de distribuição deve usar uma entrada controlada e destinatários autorizados.

## Validação local

- Distribuição, isolamento, notificações, auditoria e regressões próximas: 207 exemplos, zero falhas.
- Integrações, inbox, automações, links seguros e formulários: 232 exemplos, zero falhas; smoke final do inbox/novas opções: 52 exemplos, zero falhas.
- Captação, modalidade diária, snapshot, divisão venda/locação e formulários: 95 exemplos, zero falhas.
- Contratos públicos, views, lib e model Habitation: 480 exemplos, zero falhas. Os quatro temas passaram, incluindo título Corporate configurado.
- JavaScript: três testes passaram. Zeitwerk e `git diff --check` passaram. Não houve mudança de CSS, portanto o build CSS não foi necessário.
- Um teste antigo de exclusão de formulários Meta ainda esperava o comportamento anterior às mudanças que já estavam no workspace. A expectativa foi alinhada à regra documentada no WIP existente (exclusão continua valendo com sincronização desligada); essa implementação preexistente foi preservada.

As verificações foram automatizadas, sem smoke autenticado no navegador da aplicação. Não houve commit, push ou deploy. Antes de publicar, inventariar o pacote junto das alterações de distribuição que já estavam no workspace, conforme `docs/deploys.md`.

## Complemento do editor e publicação aprovada

O pacote completo acima, incluindo recebimento/classificação de distribuição que já estava no workspace, foi selecionado para publicação em Salute e Conexão. Central, Gateway, ativação de integrações, alterações operacionais de filas, conciliação de responsáveis e envio/aprovação de templates não fazem parte desta publicação de código.

O complemento corrige o grid mobile do editor, com a rolagem apenas no conteúdo, e preserva a posição do cursor na máscara monetária, incluindo exclusão de separadores e remoção correta de eventos ao reconectar. Uma página local com os estilos reais falhou antes da correção em 390/700/960 px e passou depois em 390/700/960/1280 px. Digitação e exclusão contínuas mantiveram o foco no navegador local. A perda espontânea de foco relatada no vídeo não se reproduziu na sessão administrativa de produção; confirmar também no computador afetado.

A validação adicional passou em 22 testes JavaScript, sete exemplos Rails do formulário e build CSS. As contagens da seção anterior são verificações de etapas anteriores, com sobreposição, e não devem ser somadas. Relatórios, caches, dados pessoais e artefatos locais gerados ficam fora do commit.

A bateria ampliada pré-deploy executou 1.203 exemplos e encontrou quatro falhas. Uma identificou regressão no menu receptivo por número com isolamento desligado; a condição foi corrigida para preservar o comportamento legado. As outras três foram reproduzidas também na revisão base `b508b3e3`, em `whatsapp/thread_broadcaster_spec.rb:9` e `admin/whatsapp_attendances_spec.rb:53,107`: expectativas antigas da quantidade de broadcasts e notificações não lidas. Não houve alteração desses comportamentos ou de suas expectativas neste pacote. Os oito exemplos de navegação mobile/PWA passaram.
