---
name: conceito-de-tela
description: Use quando o usuário pedir redesign, usabilidade ou dinâmica de uma tela do admin Unitymob a partir de um conceito para aquele contexto (ex.: "/conceito-de-tela /admin/home_sections", "pense um conceito para esta tela", "melhore o fluxo/usabilidade/dinâmica daqui"). Entende o que a tela realmente faz, propõe um conceito de uso e só então implementa e valida.
---

# Conceito de tela

Redesenha uma tela a partir do **contexto de uso**, não só do layout. Complementa `unitymob-admin-analytics-migration` (padrões visuais do admin): esta skill decide *o que* a tela deve ser; aquela diz *como* ela se parece.

## 0. Ler o pedido em 3 camadas

Descubra quais o usuário quer; se não disse, assuma o menor escopo e diga qual assumiu:

| Camada | Significa | Sinal no pedido |
|---|---|---|
| Design | cor, hierarquia, componentes | "redesign", "mais vivo", "colorido" |
| Usabilidade | ordem, o que vem primeiro, menos esforço | "confuso", "não sei por onde começar" |
| Dinâmica | reação ao vivo, cascata, prévia, padrões | "reativo", "dinâmico", "escolher X para depois Y" |

Não copiar a *organização* de outra tela quando o pedido for "faz o mesmo": perguntar (ou declarar) se é o visual ou a estrutura. Na dúvida, aplicar só o visual.

## 1. Entender o contexto (antes de propor)

- Quem usa, em que situação, o que quer conseguir em poucos cliques.
- O que o sistema REALMENTE faz com o que a tela grava: ler controller, model, e o consumidor final (ex.: a Home pública renderiza só 5 comportamentos; o formulário expunha 34 flags). O conceito nasce dessa realidade.
- Contratos que não podem quebrar: nomes de campos, params, hidden fields, permissões, retornos.
- Achados fora de escopo (bugs, dados fixos no código): anotar e reportar, não corrigir sem pedir.

## 2. Propor o conceito (curto)

Em 5 linhas ou menos: a ideia central, a ordem de decisão, o que reage a quê, o que sai. Padrões que já funcionaram aqui:
- **Escolher o tipo primeiro**, depois só as opções daquele tipo (cascata).
- **Prévia com dados reais** da conta, reusando a mesma regra do consumidor (serviço único), com avisos ("nenhum imóvel atende").
- **Padrões inteligentes** (um único número já vem escolhido; só desabilita o que ainda não faz sentido).
- **Não sobrescrever** o que a pessoa digitou; nunca ação destrutiva silenciosa.

Telas grandes ou de organização nova: mostrar o conceito e esperar o ok. Ajustes pequenos ou pedido "execute direto": implementar e explicar depois.

## 3. Implementar

- Reusar componentes do design system (`shared/ui`, `ax_*`) antes de criar; padrão que aparece em 2+ telas vira componente compartilhado. Checkbox = `ax_check_group`/chips; liga/desliga = `ax_switch_field --card`; cabeçalho = `ax_workspace_heading`; KPI = `ax_metric_card icon:/tone:`; tabela = `.ax-table`.
- Ações do módulo na contextbar (`content_for :admin_contextbar_actions`), heading só com contexto.
- Layout sem lacunas: células do grid esticam (`align-items: stretch`), listas altas em colunas/2-col, estados vazios `compact`.
- Lógica compartilhada entre admin e site público vai para um service (fonte única), não duplicada.
- Comportamento reativo em Stimulus pequeno; validação de servidor continua a autoridade.

## 4. Validar (e dizer o que não foi validado)

- Compilar as views (ERB), checar balanço de `div` em views reestruturadas.
- Rodar as specs da tela E de quem consome o que mudou (helpers/partials compartilhados quebram telas vizinhas); atualizar expectativas que travavam o markup antigo.
- Novas specs: contrato de params preservado, o comportamento novo, casos vazios.
- CSS em `admin_tailwind.css` exige `rake admin_tailwind:build` (o servido é `app/assets/builds`); lembrar que o deploy precisa rodar o build.
- Comparar falhas de suíte com o baseline (`git worktree` no HEAD) antes de atribuir falha a alguém.
- Sem navegador disponível: não afirmar validação visual; pedir print e listar o que conferir.

## 5. Entregar

Resumo por: o conceito, o que mudou por dentro (contrato preservado), testes e falhas pré-existentes, o que NÃO foi validado, achados fora de escopo, próximos passos opcionais. Curto, sem repetir o diff.
