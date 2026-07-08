# STATUS — estado em andamento (handoff entre conversas)

> Leia junto com `CLAUDE.md` (regras do fluxo) e o repo `unitymob-crm/`.
> Este arquivo é transitório: descreve ONDE paramos, não as regras.
> Atualizar/limpar conforme a tela avança.

## Foco atual: tela `/admin/atendimento/whatsapp` (WhatsApp inbox)

### Spec visual canônico (fonte da verdade)
`guidelines/pattern-atendimento-whatsapp.html` — cores/fonte/tamanhos exatos.
No repo do usuário sincroniza pra `design_migrate/guidelines/pattern-atendimento-whatsapp.html`.

### Histórico curto
1. Round VISUAL — ✅ aprovado (cores, chips preenchidos, prévia cinza, composer
   rotulado, componentização com `wa_initials` + `_context_section`). CSS 251→249.
2. Round FUNCIONAL (menu "Mais opções", ações no painel, remover telefone, etiqueta
   na linha da prévia) + fix de "gaps" via **Turbo Frame** + coluna full-height via
   **grid + display:contents** — ❌ QUEBROU a tela.

### Estado: FUNCIONAL de novo (rollback aplicado)
Rollback feito: removido turbo_frame + display:contents/grid; painel voltou a flex
(header/workspace flex:1/composer); scroll, composer, navegação e busca OK.
Mantidos os aditivos seguros (visual do card, etiqueta na linha da prévia, menu ⋮,
ações no painel, sem telefone). Bugs extras corrigidos: `[hidden]{display:none}` e
`.wa-inbox-list{align-content:start}`.

### Pendente (polimento do contexto — prompt enviado)
- Coluna de contexto deve ir do TOPO ao RODAPÉ e ficar COLADA (só hairline, sem gap).
- Solução SEGURA prescrita: `position:absolute` do contexto (top/right/bottom:0,
  width:300px) + `margin-right:300px` no header/workspace/composer (≥1120px).
  NÃO usar display:contents/grid-areas/turbo_frame (foi o que quebrou).

### Causa raiz (confirmada lendo o repo)
- `_conversation_item.html.erb`: links ganharam `data-turbo-frame="wa-thread"` +
  `data-turbo-action="advance"`; `index.html.erb` virou `<turbo-frame id="wa-thread">`.
- `whatsapp_inbox_refresh.css`: `.wa-inbox-panel--thread` virou grid com
  `grid-template-areas` e `.wa-inbox-thread__workspace` ganhou `display:contents`
  (≥1120px). Isso tirou a altura limitada do `.wa-inbox-thread__scroll` → sem scroll,
  composer fora da viewport (painel tem overflow:hidden).

### Próximo passo (JÁ TEM PROMPT PRONTO — enviado ao usuário)
Prompt de "revisar e ajustar tudo": **reverter estrutura** (tirar turbo_frame +
display:contents + grid; voltar ao painel FLEX header/scroll(flex:1,overflow auto)/composer)
e **reaplicar só o seguro** (visual do card, etiqueta na linha da prévia, menu,
ações no painel, remover telefone). Full-height do contexto fica pra DEPOIS, isolado.
Pendências a confirmar com o usuário:
- Ele tem **commit bom** antes da rodada quebrada? (define se é `git checkout <hash>` limpo).
- Depois de funcionar: passo isolado pra contexto full-height SEM quebrar scroll/composer
  (NÃO usar turbo_frame nem display:contents).
- Gap do scroll (reclamação original): refazer com `data-turbo-permanent` só na lista,
  sem frame.

### Lições gravadas (já refletidas no CLAUDE.md)
- Não empacotar mudança arquitetural (navegação/Turbo Frame) com polimento visual.
- Claude Code não tem login → screenshot dele é estático; teste funcional autenticado
  é sempre do usuário. Por isso todo prompt pede relatório estruturado.
- Nunca usar `display:contents`/grid restructure que tire a altura do scroll do thread.
