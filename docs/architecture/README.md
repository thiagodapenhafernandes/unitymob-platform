# Arquitetura da Unitymob Platform

Baseline desta evolução: `c81db8ae` (12/10/2026). Auditoria original: `671e2fb`. Plataforma Rails, Central Rails, engine de suporte, Gateway, extensão e wrapper Capacitor mantêm suas fronteiras de execução. Não há novo serviço remoto ou engine nesta evolução.

Fontes canônicas existentes:

- [Isolamento por tenant](../tenant_isolation_contract.md)
- [Layout administrativo](../admin_layout_contract.md)
- [Temas públicos](../public-theme-contract.md)
- [Deploy por aplicação](../deploys.md)
- [Payload de saída](../outbound-lead-webhook.md)
- [Política de base legal Unitymob](../integrations-legal-bases.md)

Contratos operacionais:

- [Ingresso e efeitos de leads](contracts/lead-ingress.md)
- [Aceite por canal](contracts/lead-acceptance.md)
- [Identidade de contatos internos](contracts/contact-identity.md)
- [Assinaturas](contracts/webhook-signatures.md)

## Catálogo de reutilização e responsabilidades

| Centro | Responsabilidade | Consumidores | Validação |
| --- | --- | --- | --- |
| `Leads::InternalContactScope` | Seleção/exclusão de contatos internos dentro de uma conta | Dashboard e limpeza | Spec da query, cleanup e dashboard |
| `Reports::DashboardXlsxWriter` | Serialização XML/ZIP com estilos do dashboard | Exportações de corretores e campanhas | Spec do writer e requests do dashboard |
| `Leads::Acceptance` | Transição atômica, reivindicação, avanço do rodízio e atividade accepted | Admin, links seguros e botão WhatsApp | Specs do serviço, canais e concorrência |
| `Leads::Intake` | Matching, deduplicação e complementação | Receptores externos | Specs de intake e receptores |
| `Habitations::BulkPublication` | Publicação em lote, auditoria e invalidação | Admin de imóveis | Requests de imóveis |
| `Leads::Attribution` | Classificação e contexto de aquisição; cookies apenas com aceite | Captura pública e envelope de saída | Specs de attribution e webhook |
| `WebhookService` / `WebhookDeliveryJob` | Envelope único, IDs preservados, entrega com retries e correlação segura | Formulários públicos e eventos CRM | Specs do serviço e job |
| `Privacy::LegalBases` | Declaração padrão e seleção manual | Lead, webhook e automação | Specs de lead/cadastro e webhook |

Autenticação, permissões de endpoint e seleção de recursos permanecem nos adaptadores. Não compartilhar o XLSX do relatório comercial com o do dashboard sem comparar os contratos de estilos e tipos de célula. Não ampliar matching nem executar cleanup como consequência desta refatoração.

[Execução e validação](roadmap.md).

## Decisões e continuidade

Esta entrega extrai consultas, serialização e operações específicas. Não move callbacks de criação de leads nem validações de imóveis. A publicação em lote é o primeiro recorte do módulo de imóveis; não é uma decomposição completa.

Próximos recortes exigem paridade própria: uma família de métricas do dashboard; depois uma operação de imóveis (exportação, anexos ou compartilhamento), incluindo importadores e cache. Evitar concerns destinados apenas a esconder tamanho. A skill de auditoria continua como proposta, sem instalação automática.

Os testes locais registrados na entrega não comprovam produção, performance ou equivalência de todas as integrações. Responsável pela aprovação de regras e finalidade: operação/controlador da conta; contratos técnicos são mantidos junto aos consumidores neste repositório.

Auditoria de rastreamento: [evidências e recorte implementado](tracking-audit.md).

- `WebhookTestForm`: formulário de diagnóstico compartilhado pela listagem e edição de webhooks; reutiliza o envelope e a entrega de `WebhookService`, com destino e permissões da configuração salva.
