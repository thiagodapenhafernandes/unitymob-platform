# Unitymob para WhatsApp — piloto 0.4.0

Painel lateral nativo do Chrome para **consultar e registrar atendimentos** na carteira durante uma conversa no WhatsApp Web. A implementação está em `codex/whatsapp-extension`, em checkout separado. Não foi publicada nem ativada em produção.

## Entregue

- Manifest V3, painel nativo e worker com rotas comerciais fixas.
- Identificação da conversa individual, separação entre LID e telefone, tratamento de grupos, logout, ausência de conversa e versão incompatível.
- Busca por telefone dentro dos leads autorizados do usuário/tenant. Múltiplos atendimentos exigem escolha. Telefone não resolvido permite busca manual.
- Resumo do lead, até 30 imóveis vinculados e até 5 tarefas pendentes acessíveis, com abertura da ficha completa para operações comerciais.
- Aprovação na sessão web autenticada da Unitymob; desafio aleatório de uso único, callback assinado, credencial própria da extensão, expiração de 8 horas e revogação.
- Credencial em `chrome.storage.local`, restrita a contextos confiáveis da extensão, sem sincronização entre navegadores, sem cookies do CRM no worker, sem JWT mobile e sem token dentro da página WhatsApp. Atualizar a extensão ou reiniciar o Chrome mantém o login até a expiração original de 8 horas; cada consulta continua validando o acesso no CRM. Pareamento temporário permanece em `chrome.storage.session`.
- Revalidação de usuário ativo, tenant, perfil/equipe, vínculo de espelho, identidade primária, 2FA obrigatório, política de IP e dispositivo. Aprovação recusada enquanto o desafio TOTP estiver pendente.
- Proteção contra resultados atrasados de outra conversa/conta e contra trocas simultâneas do mesmo desafio.

O painel recebe somente a identidade mínima da conversa. A implementação não consulta histórico de mensagens, não persiste conversas, não envia mensagens pelo WhatsApp Web. Cadastros seguem as notificações e automações de criação manual do CRM. A biblioteca WA-JS roda na página e tem capacidades mais amplas; o adaptador chama apenas funções de identificação. Isso não equivale a uma integração oficial da Meta.

## Atendimento — 0.3.0

- Sem lead acessível para o telefone: formulário **Criar lead**, com nome do contato pré-preenchido e editável, e-mail opcional e confirmação do contato. Usa o funil inicial e atribui o cadastro ao usuário conectado; preserva callbacks normais do CRM.
- Com lead selecionado: **Registrar nota interna** grava um evento humano na timeline, sem contar como tentativa de contato. **Agendar tarefa** cria uma tarefa manual para o usuário conectado, com tipo, prioridade e data/hora futura convertida do computador para ISO 8601 com fuso.
- Cada formulário exige confirmação do destinatário. Os campos são descartados ao trocar de conversa; o worker revalida o contexto imediatamente antes do POST. Um salvamento já enviado pertence ao contato confirmado naquele momento.
- API exige permissões `create/leads`, `edit/leads` e `manage/comercial`, respectivamente, além do escopo e telefone do lead para notas/tarefas. O cliente não escolhe tenant, responsável ou status.
- Nova versão dos termos `2026-09-06.v2`: concessões antigas precisam de novo aceite para qualquer operação comercial.
- Migration `20260906023000_create_browser_extension_operations.rb`: recibo com chave UUID, hash do pedido e IDs resultantes, criado na mesma transação. Retry com a mesma chave não duplica registros; reutilizar a chave com outro conteúdo retorna 409. A extensão mantém tentativas incertas até a concessão expirar e reutiliza tentativas concluídas por 30 segundos entre painéis. Recibos pertencem à concessão e são removidos junto dela; não copiam textos de notas.
- O tipo Visita é uma tarefa, não cria um agendamento de visita nem convites. Cadastro de imóveis, mudanças de etapa/dono, histórico de mensagens e envio ficam fora deste incremento.

## Build

Requer Node 20+ com npm. Execute nesta pasta:

```sh
npm ci --ignore-scripts
npm test
npm run build
```

O diretório `dist/` é o pacote descompactado. O build copia somente os arquivos necessários de WA-JS 4.6.0, suas licenças e os componentes visuais compartilhados da Unitymob. Nenhum arquivo da extensão RD ou de perfil Chrome entra no pacote.

ID estável do pacote de desenvolvimento: `hokkkaibgfilkmgaohfblcigmhlppdhl`. `public-key.txt` contém somente a chave pública usada para fixar esse ID. Uma futura publicação na Chrome Web Store exigirá alinhar a chave/ID ao item da loja.

O pacote do piloto já aponta para `https://dev.unitymob.com.br`. O usuário não escolhe endereço no painel. Cada build aceita uma única origem; para outro ambiente, definir `UNITYMOB_CRM_ORIGINS` no build. Isso não ativa o backend em outros ambientes.

Para homologação local, configure as origens exatas no build:

```sh
UNITYMOB_CRM_ORIGINS=http://localhost:3000 npm run build
```

HTTP só é aceito em localhost/127.0.0.1. Não se aceitam origens arbitrárias ou curingas. Reconstrua o pacote padrão antes de distribuí-lo.

## Backend e ativação

A migration `20260905203000_create_browser_extension_grants.rb` cria concessões próprias com hashes, validade e vínculos com conta/usuário/dispositivo. Aplicar via fluxo normal do projeto no ambiente escolhido. Não rodar seeds como parte desta ativação.

O recurso fica **desligado por padrão**. No backend do ambiente do piloto, configurar:

```dotenv
BROWSER_EXTENSION_TENANT_IDS=ID_CONFIRMADO_DA_CONTA_PILOTO
BROWSER_EXTENSION_ALLOWED_IDS=hokkkaibgfilkmgaohfblcigmhlppdhl
```

Mais de uma conta/ID: valores separados por vírgula. Requer reiniciar os processos que recebem essas variáveis. Use IDs confirmados no ambiente alvo; não transporte IDs do teste local.

O bloqueio por conta/ID também invalida o uso de concessões existentes. A tela `/admin/browser_extension_connections` permite ao usuário revogar suas próprias concessões. Revogar não altera sessões mobile. Concessões expiram em 8 horas; nesta versão não há limpeza automática das linhas históricas.

## Instalação do piloto, após disponibilizar o backend

1. No Chrome, abrir `chrome://extensions`, ativar o modo do desenvolvedor e carregar a pasta `dist/` sem compactação. Se já instalada, usar Recarregar para receber a versão 0.3.0 (mesmas permissões do Chrome da 0.2.0).
2. Clicar no **[U]** em qualquer página. A extensão abre o painel e ativa uma aba de WhatsApp na mesma janela; se não existir, cria uma sem substituir a página atual.
3. No painel, clicar em **Entrar na Unitymob**. O Chrome abre o login seguro da Unitymob, com o TOTP existente. Ao concluir, retorna ao painel automaticamente.
4. Ler os **termos de uso e privacidade**, marcar o aceite e clicar em **Aceitar e começar**. Até esse momento não há inspeção do contexto WhatsApp nem consulta comercial.
5. Selecionar uma conversa individual e conferir os dados contra a ficha completa.

O código assinado do login volta somente pelo callback fixo do Chrome (`https://<extension-id>.chromiumapp.org/unitymob`), vinculado ao desafio e trocado junto do verifier. A URL inicial de login não basta para resgatar a concessão. O aceite é validado no servidor e registra data, versão e hash do texto por usuário, conta e concessão. A versão atual apresenta os termos específicos do piloto; publicação ampla deve usar o texto definitivo aprovado pela Unitymob.

A etapa 1 concede permissões ao pacote. Não foi executada automaticamente no perfil do usuário durante a implementação.

## Contrato da API

| Método | Caminho após `/api/v1/browser_extension/` | Função |
| --- | --- | --- |
| POST | `session` | Troca do verifier e código assinado do callback após login |
| POST | `session/terms` | Aceite explícito da versão/hash atuais antes da leitura comercial |
| GET | `session` | Conta/usuário autorizados, capacidades e validade |
| DELETE | `session` | Revoga a concessão atual |
| POST | `leads/resolve` | Busca por `contact_phone`, sem mutação comercial |
| GET | `leads/:id` | Resumo e vínculos do lead autorizado |
| POST | `leads` | Cadastro manual confirmado |
| POST | `leads/:id/notes` | Nota interna confirmada |
| POST | `leads/:id/tasks` | Tarefa manual confirmada |

As consultas autenticadas usam `Authorization: Bearer <credencial>`. Não há endpoint genérico, método remoto arbitrário ou API de envio. As respostas usam `Cache-Control: no-store`. Parâmetros de conexão e telefone são filtrados dos logs Rails.

## Validação e limites

Testes automatizados exercitam contratos com fixtures e mocks do Chrome/WhatsApp. A apresentação foi verificada no navegador com dados fictícios em painel de 360 px. Isso **não substitui** o teste da extensão instalada contra a versão atual do WhatsApp Web e o backend de homologação.

A biblioteca depende de interfaces internas do WhatsApp. Atualizações podem exigir ajuste; versão incompatível interrompe a consulta. O painel consulta o contexto a cada 1,5 s enquanto visível, com limite de 2 s na resolução do telefone; existe esse intervalo até refletir uma mudança. Antes e depois de cada consulta comercial o worker revalida a conversa e descarta o resultado se ela mudou. Permissões são checadas no servidor a cada chamada; o painel revalida a sessão a cada 15 s. Uma revogação não consegue apagar dados que o usuário já visualizou.

Limites por IP: 90 tentativas de pareamento/5 min e 180 chamadas/min. Avaliar esses limites antes de ampliar para equipes grandes atrás do mesmo IP. A resolução usa o normalizador existente e índices de telefone já presentes; não executa backfill de telefones legados.

## Porta de saída do piloto

Antes de ampliar o piloto de escrita ou publicar, registrar evidência dos seguintes casos no WhatsApp instalado:

- Telefone salvo, contato não salvo, LID resolvido/não resolvido e telefone internacional.
- Troca rápida de chats, duas abas, duas contas WhatsApp, reload, logout e suspensão/reinício do worker.
- Um lead, nenhum lead e múltiplas oportunidades para o mesmo telefone.
- Corretor, gestor, usuário espelho, troca de conta e revogação de perfil/membership/dispositivo.
- 2FA real, aprovação expirada, permissão de host recusada, rede indisponível, 401/403/429.
- Imóveis/tarefas corretos e ausência de histórico de mensagens e documentos no payload; notas são enviadas apenas pelo formulário explícito.

## Próximo incremento previsto

Após a prova do atendimento: vínculo explícito de imóveis; sugestões de imóveis com justificativa e separadas de vínculos confirmados. Compartilhamento deve distinguir **preparado** de **enviado**. Captura de histórico, IA e envio automático ficam fora deste pacote e precisam de contratos próprios. A arquitetura mantém as regras comerciais no Rails.


## Ajustes de interface — 0.3.1

Painel nativo por aba (`sidePanel.open({tabId})`), configuração global desabilitada e habilitação somente no WhatsApp. A atualização remove o estado global antigo; navegação para outros sites desabilita o painel. O ícone continua abrindo/reutilizando WhatsApp na mesma janela. Referência: https://developer.chrome.com/docs/extensions/reference/api/sidePanel .

A conta fica em uma linha compacta com dropdown usando o componente compartilhado `ax-menu`, ações Gerenciar acesso/Desconectar e fechamento com clique externo/Escape. A versão instalada aparece no topo. Ao selecionar um lead, Registrar nota interna e Agendar tarefa aparecem antes de imóveis/tarefas; múltiplos candidatos recebem uma instrução explícita de seleção. As permissões do backend permanecem obrigatórias.

Validado com 29 testes JavaScript e prévia de 360 px. O comportamento nativo de troca de abas precisa ser confirmado no Chrome instalado após recarga. Esta alteração não modifica o backend nem os registros comerciais.


## Identificação dos cadastros — 0.3.2

Resultados exibem responsável, origem e data de cadastro, junto de uma indicação explícita da imobiliária consultada. Um telefone pode existir em contas distintas sem que a busca atravesse tenants. O caso de Grasiele foi confirmado nas bases reais em modo somente leitura: os três resultados são atendimentos antigos da Conexão importados de seu C2S; a pessoa também é corretora da Salute. Nenhum vínculo foi movido. Teste de isolamento cobre usuário com acesso a toda a conta e telefone/nome idênticos em outra imobiliária.

## Nome do contato — 0.3.3

Lê somente o nome salvo ou de perfil da conversa individual para sugerir o cadastro. O nome pode ser um apelido e permanece editável; só é enviado ao CRM na confirmação de criação do lead. Não consulta mensagens nem preenche dados de outro telefone buscado manualmente.

## Ações do lead — 0.3.4

Painel com a grade e as seções de Ações do lead: agenda, tarefas, etiquetas, histórico de contatos, propostas e imóveis vinculados. Notas salvas aparecem imediatamente após atualizar a ficha, com texto, autor e data. Tarefas mostram tipo, prioridade e vencimento. Os botões + de tarefas e histórico abrem os formulários na extensão; agenda, etiquetas, propostas, fechamento e arquivamento abrem a ficha completa para concluir a ação. Consultas mantêm o escopo de conta, lead e permissões comerciais, com até 20 registros por seção de histórico/agenda/tarefas/propostas.

## Persistência — 0.3.5

Login e chaves de repetição de operações persistem entre reinícios e atualizações, sem renovar o prazo de oito horas. Desconexão, expiração ou revogação removem a credencial e essas chaves. Na primeira atualização da 0.3.4, é necessário entrar novamente, pois o Chrome apaga o armazenamento temporário da versão anterior ao recarregá-la.

## Discovery V2 — 0.4.0

O build padrão mantém o piloto local em `dist`. Com `UNITYMOB_DISCOVERY_ORIGIN=https://webhooks.unitymob.com.br`, gera `dist-discovery`, com confirmação de e-mail, escolha de imobiliária e login no domínio retornado pelo Gateway. Não distribuir esse pacote antes de ativar/configurar o Gateway V2 e publicar a API nos CRMs.

O worker aceita somente contas recebidas da verificação, com validade de dez minutos. Origem, instância, conta e e-mail são conferidos no pareamento e na resposta do CRM. Tokens de outro diretório/ambiente não são reutilizados. A nova permissão potencial HTTPS é opcional; o navegador pede acesso ao domínio efetivamente escolhido. O Gateway não recebe a senha nem as operações do atendimento.

Arquitetura, configuração, migração do mobile e publicação: `../docs/discovery-v2-activation.md`.
