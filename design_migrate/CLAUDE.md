# CLAUDE.md — Projeto Unitymob Design System

## Fluxo de trabalho com o codebase `unitymob-crm`

O usuário mantém o app real na pasta local `unitymob-crm` (Rails 7.1 + Hotwire +
Stimulus + Tailwind/Sass, white-label via `--admin-primary`). Eu consigo **ler**
essa pasta, mas **não escrevo** nela.

O app **já consome o design system nativamente**: camada `.ax-*` em
`app/assets/stylesheets/admin_tailwind.css`, ~60 helpers em
`app/helpers/admin/ui_helper.rb`, partials em `app/views/admin/shared/ui/`.
Portanto **não há "migração" de componente** — há **aplicar refinamentos**.

### Postura de produto (regra fixa)
Pensar sempre **como produto**, não só executar o pedido: apontar retroatividade,
deadlocks, casos-limite, o que falta pro ciclo fechar (ex.: visão de admin/compliance
quando a feature gera dado auditável), e decisões que o usuário deveria tomar — mesmo
que ele não tenha perguntado.

### Densidade e compactação (regra fixa — fundamento do DS)
O design system é **spreadsheet-dense** (estilo Excel Web / Google Sheets): maximizar
informação por tela, minimizar chrome e espaço vazio. TODA criação/refinamento (telas,
componentes, tabelas, formulários, previews e os prompts pro Codex/Claude Code) parte
desse fundamento: linhas curtas (tabelas ~30–34px, ~6px de padding de célula), controles
compactos, grids de 12 colunas com gaps apertados (10–14px), rótulos pequenos, várias
colunas em vez de layout arejado de coluna única. Usar os tokens `--density-*` e as
variantes `--sm`. Na dúvida, **compactar** — nunca adicionar respiro por si só. Está no
`readme.md` (VISUAL FOUNDATIONS) e em `tokens/spacing.css`.

### Pragmatismo (regra fixa)
Nas construções/migrações/implementações, preferir a **solução mínima que resolve**:
reusar componente/CSS/partial/fluxo existente antes de criar; **verificar o que já
existe no código antes de implementar** (ex.: se a auth já protege, não mexer); não
tocar em fluxos delicados (distribuição, real-time, pipeline de envio) sem necessidade
real; migrações **idempotentes e com rollback**; escopar/compartilhar CSS (ex.:
`:is(.a, .b)`) em vez de duplicar tela/coluna/regra. Menos código = menos superfície
de bug. Os prompts pro Codex/Claude Code devem exigir essa postura.

### Como responder a pedidos de refinamento
O **design system inteiro é o manual** (tokens + componentes `.ax-*` + guidelines).
NÃO gerar pacote por tela nem mandar o usuário baixar nada por tela — o manual já
está no repo dele (ver Sincronização). O fluxo é:
1. **Ler os dois lados**: o código real da tela em `unitymob-crm/...` E o manual
   (aqui / no `_ds/` dele). Fazer diff de verdade, nunca supor.
2. **Devolver o PROMPT pronto pro Codex na própria conversa** (não em arquivo), já
   calibrado pro estado atual do repo, mandando o Codex **seguir o manual** e
   aplicar na tela real.
3. Só gerar/atualizar arquivo em `design_migrate/` se o próprio manual precisar
   evoluir (regra nova de componente/token) — não por tela.

### Regras dos prompts pro Codex
- **Componentização primeiro (regra nova):** sempre que possível, o prompt deve
  mandar **criar um componente reutilizável (partial em `app/views/admin/shared/ui/`
  ou helper `ax_*` em `Admin::UiHelper`) onde ainda não existe**, e então aplicar
  as correções/refinamentos EM CIMA desse componente — nunca resolver com marcação
  solta duplicada tela a tela. Reduz fricção e evita divergência futura.
- **Anti-inflação (a regra de ouro):** o Codex deve **REUSAR** as classes `.ax-*`
  e os helpers `ax_*` que já existem no app (eles já são o design system). A
  mudança é **de marcação (ERB)**, não de CSS. Proibido escrever CSS novo em
  volume — foi "implementar do zero" que gerou o CSS de 1.369 linhas. Se CSS de
  tela for inevitável, mínimo, escopado (`.wa-inbox-page`), poucas linhas.
- Citar a regra do manual que embasa cada mudança (ex.: `design_migrate/tokens/
  spacing.css` p/ densidade, `components/.../ContextPin` p/ pin de entidade,
  `LeadLabelChip` p/ etiquetas preenchidas, `Card` p/ painéis).
- Sempre preservar 100% dos `data-controller` / `data-*-target` / `data-action`
  do Stimulus, rotas, controllers, models.
- Nunca redefinir `.ax-*` global nem fixar hex da primária (usar `--admin-primary`).
- **Retorno obrigatório (regra nova):** todo prompt termina pedindo ao Codex/Claude
  Code um **relatório estruturado pra mim** avaliar aqui: (a) o que foi concluído;
  (b) o que ficou **pendente e por quê** (bloqueio, ambiguidade, arquivo/rota que
  não existe, fallback que teve que usar); (c) arquivos tocados; (d) contagem de
  linhas do CSS de tela antes/depois; (e) qualquer desvio do manual e o motivo.
  Sem esse retorno eu não consigo reavaliar a implementação.
- Todo prompt termina com: verificação (comparar com o manual/tokens) + rollback
  via `git checkout`.

### Sincronização (rara)
O usuário baixa o **Project archive (.zip)** deste projeto e desempacota **direto na
raiz de `unitymob-crm/design_migrate/`** — **sem** a pasta `Unitymob Design System`
no meio (ele achata: move o conteúdo de dentro dela pra raiz de `design_migrate/`).
Então o manual fica em `design_migrate/tokens/`, `design_migrate/components/`,
`design_migrate/guidelines/`, `design_migrate/readme.md`, `design_migrate/SKILL.md`.

Isso é raro — só quando o próprio manual evolui. No dia a dia o usuário só pede
refinamentos e eu devolvo prompts; o manual já está lá.

**AVISO DE RE-SYNC (obrigatório):** ao fim de TODA resposta, dizer explicitamente
se o usuário precisa baixar o kit e atualizar o `design_migrate/`. Só pedir re-sync
quando eu alterar/criar arquivo DO MANUAL que um prompt vá referenciar
(`tokens/`, `components/`, `guidelines/`, `styles.css`, `readme.md`, `SKILL.md`,
`assets/`). Mudança só em `CLAUDE.md`/`STATUS.md` (fluxo/continuidade) NÃO exige
re-sync. Formato: "🔄 Re-sync necessário: <arquivos>" ou "✅ Sem re-sync".

**IMPORTANTE — este projeto NÃO pode ter pasta `design_migrate/`.** O `design_migrate/`
existe só no REPO do usuário (é o destino onde ele desempacota o manual). Se este
projeto tiver uma pasta `design_migrate/`, ela vira `design_migrate/design_migrate/…`
no repo (aninhamento duplo) e quebra os caminhos dos prompts. O spec canônico de
telas mora em `guidelines/` (ex.: `guidelines/pattern-atendimento-whatsapp.html`),
que sincroniza pra `design_migrate/guidelines/…`.

**Regra de caminho nos prompts:** referenciar o manual como `design_migrate/tokens/…`,
`design_migrate/guidelines/…`, `design_migrate/components/…` etc. (caminho fixo, sem
espaços). E referenciar o app como `app/...` (raiz do repo).
