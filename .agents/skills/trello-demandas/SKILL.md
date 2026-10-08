---
name: trello-demandas
description: Use quando o usuário pedir $trello-quadro "nome", $trello-card "nome ou id", analisar demandas no Trello, ler cards com anexos multimodais, mover cards ou comentar em cards usando ~/.trello.env e ~/.trello-cli.sh.
---

# Trello Demandas

## Objetivo

Usar o Trello como fonte global de demandas, com leitura multimodal de cards:

- texto do card;
- comentários;
- checklists;
- etiquetas;
- anexos;
- imagens;
- vídeos;
- áudios.

Este skill é global e não pertence a um projeto específico.

## Comandos de conversa suportados

```text
$trello-quadro "Prioridades"
$trello-quadro "Nome do board" --lista "Prioridades"
$trello-card "nome ou id"
$trello-card "nome ou id" --quadro "Nome do board"
$trello-card "nome ou id" --lista "Prioridades"
$trello-card "nome ou id" mover "Em desenvolvimento"
$trello-card "nome ou id" comentar "texto do comentário"
```

## Pré-requisitos

As credenciais e helpers vivem no home do usuário:

```bash
source ~/.trello.env
source ~/.trello-cli.sh
```

O script principal deste skill é:

```bash
python3 ~/.codex/skills/trello-demandas/scripts/trello_demandas.py --help
```

## Fluxo padrão para `$trello-quadro`

1. Rode:

```bash
source ~/.trello.env
python3 ~/.codex/skills/trello-demandas/scripts/trello_demandas.py quadro "Prioridades"
```

2. Se o nome resolver para uma lista em algum board, liste os cards dessa lista.

3. Se resolver para um board, liste as listas e cards.

4. Use `--no-media` para triagem inicial em board/lista grande.

5. Entregue uma visão objetiva: cards encontrados, prioridade aparente, cards com mídia, ambiguidades e próximos passos.

## Fluxo padrão para `$trello-card`

1. Rode:

```bash
source ~/.trello.env
python3 ~/.codex/skills/trello-demandas/scripts/trello_demandas.py card "nome ou id"
```

2. O comando aceita:

- id de card;
- shortLink;
- URL;
- nome completo;
- trecho do nome.

3. Se houver mais de um match, não escolha silenciosamente. Mostre as opções e peça o identificador mais específico.

4. Após resolver o card, o runner chama `trello_card_context.py`, que gera:

- `MANIFEST: <path>/context.md`;
- `IMAGES_TO_VIEW`;
- `ANALISAR_VIDEO`;
- `ANALISAR_AUDIO`.

5. Leia o `context.md`.

6. Para cada imagem em `IMAGES_TO_VIEW`, abra com `view_image`.

7. Para cada mídia em `ANALISAR_VIDEO`:

- aplique o skill `analisar-video`.

8. Para cada mídia em `ANALISAR_AUDIO`:

- aplique o skill `analisar-audio`.

9. Entregue a análise final em pt-BR:

- **Resumo da demanda**
- **Contexto do card**
- **Evidências encontradas**
- **O que aparece nas imagens**
- **O que foi dito/mostrado em vídeos/áudios**
- **Lista objetiva de demandas**
- **Regra/comportamento esperado**
- **Ambiguidades**
- **Riscos**
- **Recomendação objetiva**
- **Confirmação necessária**

Se a demanda for para código no projeto atual, pare na clarificação. Não implemente, não faça commit e não faça deploy só a partir da análise do Trello. Execute apenas após confirmação explícita posterior.

## Mover e comentar

Mover card e comentar são ações externas reais no Trello.

- Se o usuário pedir análise/leitura, pode executar sem confirmação adicional.
- Se o usuário pedir explicitamente `mover` ou `comentar`, execute a ação.
- Se a ação estiver implícita ou ambígua, confirme antes.

Exemplos:

```bash
source ~/.trello.env
python3 ~/.codex/skills/trello-demandas/scripts/trello_demandas.py mover "Card X" "Em desenvolvimento"
python3 ~/.codex/skills/trello-demandas/scripts/trello_demandas.py comentar "Card X" "Análise registrada..."
```

## Convenções

- Pasta de trabalho por card: `~/worksapces/trello-cards/<shortLink>/`.
- Mídias de card são baixadas para `attachments/`.
- Vídeos são copiados para `~/worksapces/video-demanda/`.
- Áudios são copiados para `~/worksapces/audio-demanda/`.
- Não invente conteúdo de anexos não lidos.
- Quando um download falhar, registre como lacuna.
- Quando áudio e visual divergirem, destaque explicitamente.
