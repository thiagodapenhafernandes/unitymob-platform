---
name: analisar-audio
description: Use quando o usuário pedir $analisar-audio 01, $analisar_audio 01, $analisar_audio 01.mp3, analisar áudio de demanda, transcrever áudio, ou transformar gravações de /Users/thiagodap.fernandes/worksapces/audio-demanda em demandas objetivas de produto/desenvolvimento antes de implementar.
---

# Analisar Audio

## Objetivo

Analisar áudios de demanda no workspace local `audio-demanda`, usando preferencialmente um arquivo explícito informado no prompt, por exemplo:

```text
$analisar_audio 01
```

ou:

```text
$analisar-audio 01.mp3
```

A análise combina:

- inventário dos áudios disponíveis;
- normalização para WAV mono 16 kHz quando necessário;
- transcrição em pt-BR com `whisper-cli`;
- saída final em linguagem de produto: demanda clarificada, regras esperadas, ambiguidades e próximos passos para confirmação antes de qualquer execução.

## Fluxo Padrão

1. Se o prompt trouxer um arquivo ou base, use esse arquivo diretamente. Não transforme a tarefa em menu interativo.

2. Normalize o nome:

- `01` pode resolver para `01.mp3`, `01.m4a`, `01.wav`, `01.ogg`, `01.oga`, `01.opus`, `01.aac`, `01.flac`, `01.webm`, `01.mp4` ou `01.mov`;
- `01.mp3` usa base `01`;
- caminho absoluto é aceito se apontar para um arquivo existente.

3. Confirme que o arquivo existe em `/Users/thiagodap.fernandes/worksapces/audio-demanda` ou no caminho absoluto informado.

4. Rode o inventário para o arquivo escolhido:

```bash
python3 /Users/thiagodap.fernandes/.codex/skills/analisar-audio/scripts/audio_inventory.py --audio 01
```

5. Se o usuário pedir apenas `$analisar_audio` sem nome de arquivo, rode o inventário geral e peça para ele reenviar no formato `$analisar_audio <arquivo>`; não dependa de seleção por menu.

```bash
python3 /Users/thiagodap.fernandes/.codex/skills/analisar-audio/scripts/audio_inventory.py
```

6. Para o áudio escolhido, trate o arquivo atual como fonte de verdade. Mesmo que já exista WAV normalizado ou transcrição com a mesma base, regenere tudo por padrão, porque o usuário pode apagar e substituir áudios mantendo nomes simples como `01`, `02`, `03`.

Exceção: só reutilize artefatos existentes se o usuário pedir explicitamente para "usar artefatos existentes", "não regenerar", "aproveitar a transcrição", ou equivalente.

7. Antes de regenerar, remova artefatos antigos da mesma base para evitar análise de áudio anterior com nome reaproveitado:

```bash
cd /Users/thiagodap.fernandes/worksapces/audio-demanda
rm -f "normalized/<base>.wav" \
  "transcripts/<base>.txt" "transcripts/<base>.srt" "transcripts/<base>.json"
```

8. Se o usuário pediu explicitamente para reutilizar artefatos existentes, verifique se já existem:

- `transcripts/<base>.txt`, `.srt` ou `.json`;
- `normalized/<base>.wav`.

Se já houver transcrição nesse modo de reutilização, leia primeiro `transcripts/<base>.txt`; use `.srt` quando precisar relacionar trecho e tempo.

9. Gere WAV normalizado e transcrição:

```bash
cd /Users/thiagodap.fernandes/worksapces/audio-demanda
ffmpeg -y -i "<audio>" -vn -ac 1 -ar 16000 "normalized/<base>.wav"
whisper-cli -m "models/ggml-small.bin" -l pt -f "normalized/<base>.wav" -otxt -osrt -oj -of "transcripts/<base>"
```

No modo explícito de reutilização, pule este passo somente se a transcrição existente for suficiente para a demanda.

10. Leia a transcrição completa antes de concluir. Se a transcrição vier ruim, registre isso como risco e use trechos com baixa confiança como ambiguidade, não como fato.

11. Entregue a análise em pt-BR no formato:

- **Resumo da demanda**
- **O que foi dito no áudio**
- **Lista objetiva de demandas**
- **Regra/comportamento esperado**
- **Ambiguidades**
- **Recomendação objetiva**
- **Confirmação necessária**

12. A seção **Lista objetiva de demandas** é obrigatória. Ela deve transformar a fala em itens acionáveis, numerados, separando o que foi explicitamente dito do que é inferência. Inclua também demandas laterais citadas no áudio, como busca, duplicidade, dados específicos, telas afetadas e casos a auditar.

13. A seção **Confirmação necessária** deve sempre terminar com uma pergunta objetiva, por exemplo:

```text
Confirma que devo aplicar essa correção no projeto?
```

ou, se houver mais de uma interpretação:

```text
Confirma a opção A ou prefere a opção B?
```

Se a demanda for para código no projeto atual, pare sempre na clarificação. Não implemente, não faça commit e não faça deploy a partir da análise de áudio. Só execute depois de uma confirmação posterior explícita do usuário, como "pode ajustar", "aplica", "faz commit" ou "faz deploy".

## Convenções

- Pasta padrão: `/Users/thiagodap.fernandes/worksapces/audio-demanda`.
- Pastas de artefatos: `normalized/` para WAV e `transcripts/` para `.txt`, `.srt` e `.json`.
- Modelos: `models/ggml-small.bin` dentro de `audio-demanda`, igual ao fluxo de vídeo quando possível.
- Base do áudio: nome sem extensão, por exemplo `01` para `01.mp3`.
- Modo preferido de uso: sempre com nome explícito, por exemplo `$analisar_audio 01`.
- Quando o usuário informa um áudio explícito, regenere transcrição e WAV por padrão, mesmo que exista cache com a mesma base.
- Não reutilize transcrições antigas de nomes simples (`01`, `02`, `03`, etc.) sem pedido explícito do usuário.
- Quando a fala mencionar uma tela, regra, bug ou projeto sem contexto suficiente, destaque como ambiguidade e peça confirmação.
- O resultado final da análise deve ser uma demanda pronta para validação do usuário, não uma implementação.
