# ADR: Preview e mapeamento de botões de template no builder de automação

**Status:** Accepted · **Data:** 2026-10-13

## Contexto
O builder (`/admin/automacoes/fluxos/:id/builder`) precisa mostrar o preview do template WhatsApp escolhido e mapear
seus botões em caminhos, como `/admin/whatsapp/fluxos-resposta` já faz.

## Decisão
Reusar o que existe, sem segunda implementação:
- **Preview:** a partial `admin/shared/ui/_whatsapp_message_preview` é a única fonte. O controller renderiza no catálogo
  (`preview_html`) e o JS só injeta e destaca o botão ativo.
- **Mapeamento de botões:** continua em `Automation::TemplateScaffold` (já usado pelo catálogo do builder).
- **Destaque do botão ativo:** regras `.has-active-button` / `.is-active` sobem de `whatsapp_response_flows.css` para
  `message_preview.css` (componente `ax-message-preview`), valendo para as duas telas.

## Alternativas
| Opção | Prós | Contras |
|---|---|---|
| A. Reimplementar o preview em JS no builder | Sem round-trip | Duplica markup/regra; diverge do template real (mídia, carrossel) |
| B. Endpoint JSON/HTML sob demanda | Catálogo menor | Mais uma rota, latência ao escolher |
| **C. `preview_html` no catálogo (escolhida)** | Reuso total, zero rota nova | Catálogo maior (um HTML por template aprovado com botão) |

## Consequências
- Mudança no preview do template vale para as duas telas.
- Se o número de templates crescer muito, migrar para a opção B.
