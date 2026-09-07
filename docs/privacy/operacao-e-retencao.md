# Privacidade — procedimento operacional e evidências

Revisão: 2026-09-06. Responsável pelo canal: Thiago P Fernandes (confirmado pelo responsável da Unitymob nesta revisão).
Canal: contato@unitymob.com.br.

## Status

Documentos locais preparados para adoção. Os SLAs abaixo são compromissos definidos nesta revisão a pedido do responsável, não medições históricas nem promessa de automação já implantada. Publicar as páginas exige colocar o procedimento em operação. Nenhum expurgo de produção ou alteração de contrato de fornecedor foi executado.

## Atendimento manual

1. Registrar recebimento, data, tipo de pedido, conta, responsável e prazo no canal de suporte adotado. Confirmar em até 2 dias úteis.
2. Verificar identidade e poderes com o mínimo necessário; não solicitar senha ou token. Não exportar a conta inteira para alguém que pede somente seus dados pessoais.
3. Identificar papel: dados comerciais da imobiliária exigem instrução do controlador; dados próprios da Unitymob são tratados pela Unitymob. Direcionar sem abandonar o acompanhamento.
4. Confirmação/acesso: simplificado imediatamente quando possível; declaração completa até 15 dias corridos. Outros direitos seguem o prazo legal aplicável, sem usar o prazo comercial de exportação para postergar direitos.
5. Cancelamento: receber pedidos de exportação em até 30 dias do término. Entregar em até 30 dias corridos após autorização e escopo definidos, por canal autenticado, delimitando tenant e acesso e removendo credenciais. Documentar formato, entrega e expiração do acesso à cópia.
6. Excluir da base ativa em até 30 dias após pedido validado e exportação solicitada concluída. Levantar associações, anexos, integrações e obrigações antes de executar. Não apagar por e-mail não verificado nem rodar delete global. Informar quais categorias são conservadas e o motivo legal.
7. Backups sob gestão Unitymob: expurgar no ciclo de até 90 dias após exclusão ativa. Registrar data máxima, conjuntos afetados e confirmação. Se houver retenção legal, restringir uso e documentar exceção. Antes de restaurar backups, reaplicar o registro de exclusões.
8. Confirmar encerramento ao solicitante e guardar apenas evidência mínima necessária do atendimento.

## Rotinas existentes versus compromissos novos

- `CheckIns::LocationPingRetentionJob`: 90 dias por padrão; previsto em `config/recurring.yml`. Conferir scheduler, execução e parâmetros por produção antes de afirmar expurgo efetivo.
- Extensão: validade de até oito horas no backend; limpeza local por desconexão concluída/verificação de validade/resposta de revogação. Não apaga registros do CRM.
- Exportação/cancelamento/exclusão/backups: os novos prazos são atendidos pelo procedimento manual acima. Não foi criado job genérico de exclusão: apagar dados multi-tenant exige inventário e confirmação do escopo real.

## Mapa de dados confirmado no código

| Fluxo | Destino | Dados e evidência |
| --- | --- | --- |
| CRM e arquivos | Servidor da conta; Disk ou DigitalOcean Spaces conforme ambiente | `config/environments/production.rb`, `config/storage.yml`. Configuração padrão do Spaces: sfo3, não prova região efetivamente contratada. |
| Busca IA | API OpenAI | Áudio de busca (`Transcriber`), texto/filtros/catálogo (`Interpreter`). |
| Conteúdo IA | API OpenAI | Informações do imóvel/página, `Ai::PropertyContentService`, `Ai::SeoContentService`. |
| Inteligência de interesse | API OpenAI quando habilitada/conectada | Nome/id/origem/etapa do lead, perfil de preferência e imóveis sugeridos, `InterestIntelligence::AiSummary`. |
| WhatsApp integrado | Meta e gateways configurados | Contatos, mensagens, anexos, entrega e webhooks. Não confundir com extensão. |
| Extensão | WhatsApp Web + diretório + CRM escolhido | Identificação da conversa; consultas/escritas autorizadas; sem importar histórico. |
| Push nativo | Google Firebase Cloud Messaging quando configurado | Token, título, corpo e dados da notificação, `Notifications::FcmSender`. |
| Tracking público | GTM/Google Ads/Meta Pixel/RD Station configurados | Eventos de navegação/conversão sujeitos ao controle de consentimento. |

## Evidências ainda necessárias antes de alegar conformidade integral

- Região efetiva de cada servidor, bucket, armazenamento de suporte, réplicas, logs e backups; os defaults do código não comprovam a topologia em produção.
- Contratos/DPA e mecanismo de transferência internacional aplicável a cada fornecedor; manter identificação dos destinatários, países, duração e salvaguardas consultáveis pelo titular.
- Política de backups efetivamente configurada que permita cumprir o novo limite, inclusive snapshots manuais e cópias externas. Sem essa conferência, não tratar o limite como controle técnico validado.
- Cadastro de atendimento/controle de prazos e evidências de solicitações. Não foi testada a entrega de e-mail ao canal.

Fontes normativas consultadas: LGPD arts. 9, 18, 19 e 33; Resolução ANPD 19/2024 (transferências internacionais); orientações ANPD para cookies. Nenhum prazo comercial acima é apresentado como benchmark obrigatório de mercado.

## Referências comerciais para a decisão de prazo

Consultadas nesta revisão, sem tratar prazos de outros fornecedores como obrigação da Unitymob:
- Pipedrive: exclusão antecipada solicitada em até um mês; encerramento normal pode ter janela de até 180 dias: https://www.pipedrive.com/en/terms-of-service
- HubSpot: expurgo de contato pode levar até 30 dias: https://knowledge.hubspot.com/privacy-and-consent/how-do-i-perform-a-gdpr-delete-in-hubspot
- HubSpot documenta backups por 30 dias: https://www.hubspot.com/reliability

A janela Unitymob de 30 dias para execução operacional e até 90 dias para backups é uma decisão desta revisão. O limite de backups não foi inferido da configuração existente e precisa ser aplicado a todas as cópias sob gestão da Unitymob antes da publicação.

## Validação da alteração

- 3 testes Node do consentimento: ausência/expiração não revive aceite antigo, aceite/recusa/reaceite preservam sessão de login, oposição bloqueia rastreamento de interesse mesmo em configuração sem consentimento prévio.
- 10 exemplos RSpec aprovados: eventos de navegação, tags de tracking e contrato do tracker.
- Zeitwerk aprovado.
- Browser: páginas legais desktop/mobile; recusa, reabertura, aceite e revogação no Rails local. Revogação recarrega a página para interromper scripts opcionais carregados.
