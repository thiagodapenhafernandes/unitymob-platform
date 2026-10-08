---
name: analisar-video
description: Use quando o usuário pedir $analisar-video 06.mp4, $analisar_video 06.mp4, anexar o skill Analisar Video com um nome de MP4, analisar vídeo de demanda, transcrever áudio de vídeo, ou usar transcrição/keyframes/frames de /Users/thiagodap.fernandes/worksapces/video-demanda para clarificar demandas de produto/desenvolvimento antes de implementar.
---

# Analisar Video

## Objetivo

Facilitar análise de vídeos de demanda no workspace local `video-demanda`, usando preferencialmente um vídeo explícito informado no prompt, por exemplo:

```text
$analisar-video 06.mp4
```

ou:

```text
[$analisar-video](/Users/thiagodap.fernandes/.codex/skills/analisar-video/SKILL.md) 06.mp4
```

A análise combina:

- inventário dos `.mp4` disponíveis;
- transcrição em pt-BR com `whisper-cli`;
- frames/keyframes para entender tela e contexto visual;
- saída final em linguagem de produto: demanda clarificada, regra esperada, ambiguidades e próximos passos para confirmação antes de qualquer execução.

## Fluxo Padrão

1. Se o prompt trouxer um arquivo `.mp4`, use esse arquivo diretamente. Não tente transformar a tarefa em menu interativo.

2. Normalize o nome:

- `06` vira `06.mp4`;
- `06.mp4` usa base `06`;
- caminho absoluto é aceito se apontar para um arquivo existente.

3. Confirme que o arquivo existe em `/Users/thiagodap.fernandes/worksapces/video-demanda` ou no caminho absoluto informado.

4. Rode o inventário somente para o vídeo escolhido:

```bash
python3 /Users/thiagodap.fernandes/.codex/skills/analisar-video/scripts/video_inventory.py --video 06.mp4
```

5. Se o usuário pedir apenas `$analisar-video` sem nome de arquivo, rode o inventário geral e peça para ele reenviar no formato `$analisar-video <arquivo>.mp4`; não dependa de seleção por menu.

```bash
python3 /Users/thiagodap.fernandes/.codex/skills/analisar-video/scripts/video_inventory.py
```

6. Para o vídeo escolhido, trate o `.mp4` atual como fonte de verdade. Mesmo que já exista transcrição, áudio, frames ou keyframes com a mesma base, regenere tudo por padrão, porque o usuário costuma apagar e substituir vídeos mantendo nomes simples como `01`, `02`, `03`.

Exceção: só reutilize artefatos existentes se o usuário pedir explicitamente para "usar artefatos existentes", "não regenerar", "aproveitar a transcrição", ou equivalente.

7. Antes de regenerar, remova artefatos antigos da mesma base para evitar análise de vídeo anterior com nome reaproveitado:

```bash
cd /Users/thiagodap.fernandes/worksapces/video-demanda
rm -f "audio/<base>.wav" \
  "transcripts/<base>.txt" "transcripts/<base>.srt" "transcripts/<base>.json" \
  frames/<base>_*.jpg keyframes/<base>_scene_*.jpg
```

8. Se o usuário pediu explicitamente para reutilizar artefatos existentes, verifique se já existem:

- `transcripts/<base>.txt`, `.srt` ou `.json`;
- `audio/<base>.wav`;
- `keyframes/<base>_scene_*.jpg`;
- `frames/<base>_*.jpg`.

Se já houver transcrição nesse modo de reutilização, leia primeiro `transcripts/<base>.txt`; use `.srt` quando precisar relacionar trecho e tempo.

9. Gere áudio e transcrição:

```bash
cd /Users/thiagodap.fernandes/worksapces/video-demanda
ffmpeg -y -i "<video>.mp4" -vn -ac 1 -ar 16000 "audio/<base>.wav"
whisper-cli -m "models/ggml-small.bin" -l pt -f "audio/<base>.wav" -otxt -osrt -oj -of "transcripts/<base>"
```

No modo explícito de reutilização, pule este passo somente se a transcrição existente for suficiente para a demanda.

10. Gere frames amostrados e keyframes:

```bash
cd /Users/thiagodap.fernandes/worksapces/video-demanda
ffmpeg -y -i "<video>.mp4" -vf fps=1/5 "frames/<base>_%03d.jpg"
ffmpeg -y -skip_frame nokey -i "<video>.mp4" -vsync vfr "keyframes/<base>_scene_%03d.jpg"
```

No modo explícito de reutilização, gere imagens apenas se não houver frames/keyframes suficientes.

11. Inspecione os principais frames/keyframes com `view_image` quando o visual for necessário. Priorize início, transições de tela, tela com erro, tela de formulário e final.

12. Entregue a análise em pt-BR no formato:

- **Resumo da demanda**
- **O que foi dito no áudio**
- **O que aparece na tela**
- **Lista objetiva de demandas**
- **Regra/comportamento esperado**
- **Ambiguidades**
- **Recomendação objetiva**
- **Confirmação necessária**

13. A seção **Lista objetiva de demandas** é obrigatória. Ela deve transformar áudio + tela em itens acionáveis, numerados, separando o que foi confirmado visualmente do que é inferência. Inclua também demandas laterais citadas no áudio, como busca, duplicidade, dados específicos e casos a auditar.

14. A seção **Confirmação necessária** deve sempre terminar com uma pergunta objetiva, por exemplo:

```text
Confirma que devo aplicar essa correção no projeto?
```

ou, se houver mais de uma interpretação:

```text
Confirma a opção A ou prefere a opção B?
```

Se a demanda for para código no projeto atual, pare sempre na clarificação. Não implemente, não faça commit e não faça deploy a partir da análise de vídeo. Só execute depois de uma confirmação posterior explícita do usuário, como "pode ajustar", "aplica", "faz commit" ou "faz deploy".

## Convenções

- Pasta padrão: `/Users/thiagodap.fernandes/worksapces/video-demanda`.
- Base do vídeo: nome sem extensão, por exemplo `06` para `06.mp4`.
- Modo preferido de uso: sempre com nome explícito do vídeo, por exemplo `$analisar-video 06.mp4`.
- Quando o usuário informa um vídeo explícito, regenere transcrição, áudio, frames e keyframes por padrão, mesmo que exista cache com a mesma base.
- Não reutilize transcrições ou imagens antigas de nomes simples (`01`, `02`, `03`, etc.) sem pedido explícito do usuário.
- Quando houver conflito entre áudio e visual, destaque explicitamente.
- Para demandas de produto, não confie só no print/frame: transcreva ou leia a transcrição sempre que houver fala relevante.
- O resultado final da análise deve ser uma demanda pronta para validação do usuário, não uma implementação.
