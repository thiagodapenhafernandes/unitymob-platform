---
name: analisar-card
description: Analisa um card do Trello de forma multimodal — descrição, comentários, checklists e TODOS os anexos (imagens, vídeos e áudios) — para entregar o contexto completo da demanda. Use quando o usuário pedir para analisar/entender um card, ou antes de implementar um card que tenha anexos.
---

# Analisar Card (Trello) — multimodal

## Objetivo

Reunir e analisar o **contexto completo** de um card do Trello, não só o texto:
descrição, comentários, checklists e cada anexo — **imagem, vídeo e áudio**.
Para vídeos e áudios, esta skill **reutiliza a skill `/analisar-video`** (transcrição
pt-BR + frames), evitando duplicação.

Modo de uso preferido, com o card explícito:

```text
/analisar-card 6a43cc7bfa23f69526c6f0a2
/analisar-card https://trello.com/c/QTF30gWg/17-ajustar-visualizacao-fotos
```

Aceita: id de 24 chars, shortLink, ou URL completa do card.

## Pré-requisitos

- Credenciais: `source ~/.trello.env` (exporta `TRELLO_KEY` e `TRELLO_TOKEN`).
- Ferramentas: `ffmpeg` e `whisper-cli` (para a parte de vídeo/áudio via `/analisar-video`).

## Fluxo padrão

1. Rode o coletor de contexto (baixa texto + todos os anexos, classifica e
   prepara as mídias):

```bash
source ~/.trello.env
python3 ~/.claude/skills/analisar-card/scripts/trello_card_context.py <card>
```

A saída imprime:
- `MANIFEST: <caminho>/context.md` — texto do card + inventário dos anexos.
- `IMAGES_TO_VIEW: N` seguido dos caminhos das **imagens** (e frames, se `--transcribe-inline`).
- `ANALISAR_VIDEO: N` seguido dos **nomes de arquivo** já copiados para
  `~/worksapces/video-demanda/` para a skill `/analisar-video`.

2. Leia o manifest `context.md` para o contexto textual (descrição, comentários,
   checklists, lista/coluna atual, labels).

3. Para cada arquivo em `IMAGES_TO_VIEW`, **abra a imagem** com a ferramenta de
   leitura de imagem (Read) e descreva o que aparece (tela, erro, formulário, etc.).

4. Para cada nome em `ANALISAR_VIDEO`, invoque a skill **`/analisar-video`** com
   aquele arquivo, por exemplo `/analisar-video card_QTF30gWg_02.mp4`. Aproveite a
   transcrição pt-BR e os frames que a skill gera. (Ela opera em
   `~/worksapces/video-demanda`, para onde o coletor já copiou as mídias.)

5. **Sintetize tudo** (texto + imagens + vídeo/áudio) numa análise única.

## Quadro/coluna inteira

Para "analise os cards do quadro/coluna tal", use o runner de board (chama o
coletor por card e agrega um índice):

```bash
source ~/.trello.env
# coluna específica (recomendado para não baixar mídia demais de uma vez):
python3 ~/.claude/skills/analisar-card/scripts/trello_board_context.py --board <board|url> --list "Para fazer"
# board inteiro:
python3 ~/.claude/skills/analisar-card/scripts/trello_board_context.py --board <board|url>
# triagem rápida só de texto:
python3 ~/.claude/skills/analisar-card/scripts/trello_board_context.py --board <board|url> --no-media
```

O índice lista, por card, o `context.md`, as imagens e as mídias para `/analisar-video`.
Depois: leia os `context.md`, abra as imagens (Read) e rode `/analisar-video` nas mídias.
Dica de custo: em board grande, faça `--no-media` primeiro e aprofunde a mídia só nos cards relevantes.

## Flags úteis

- `--no-media` — só o contexto textual + inventário, sem baixar anexos (rápido, para triagem).
- `--transcribe-inline` — transcreve/gera frames de vídeo/áudio no próprio script
  (não delega ao `/analisar-video`); útil em lote/headless.
- `--frames-fps N` — taxa de amostragem de frames no modo inline (padrão `1/4`).

## Saída final (pt-BR)

Entregue a análise consolidada no formato:

- **Resumo da demanda** (o que o card pede, em uma frase)
- **Contexto textual** (descrição + comentários + checklists relevantes)
- **O que aparece nas imagens**
- **O que foi dito/mostrado nos vídeos/áudios** (via `/analisar-video`)
- **Lista objetiva de demandas** (itens numerados e acionáveis; separe o confirmado do inferido)
- **Regra/comportamento esperado**
- **Ambiguidades**
- **Recomendação objetiva**
- **Confirmação necessária** (termine com uma pergunta objetiva)

Se a demanda for para código no projeto atual, pare na clarificação: não implemente,
não faça commit e não faça deploy a partir desta análise. Só execute após confirmação
explícita posterior do usuário ("pode ajustar", "aplica", "faz commit", "faz deploy").

## Convenções

- Pasta de trabalho por card: `~/worksapces/trello-cards/<shortLink>/`
  (com `context.md`, `attachments/`, e, no modo inline, `audio/`, `frames/`, `keyframes/`, `transcripts/`).
- Mídias para o `/analisar-video` são copiadas para `~/worksapces/video-demanda/`
  com o nome `card_<shortLink>_<n>.<ext>`.
- Quando áudio e visual divergirem, destaque explicitamente.
- Não invente conteúdo de anexo que não foi baixado/lido; se um download falhar, diga.
