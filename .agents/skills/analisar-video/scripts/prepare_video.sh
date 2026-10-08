#!/usr/bin/env bash
set -euo pipefail

ROOT="${VIDEO_DEMANDA_ROOT:-/Users/thiagodap.fernandes/worksapces/video-demanda}"
VIDEO="${1:-}"

if [[ -z "$VIDEO" ]]; then
  echo "Uso: $0 <video.mp4|base>" >&2
  exit 2
fi

if [[ "$VIDEO" != *.mp4 ]]; then
  VIDEO="${VIDEO}.mp4"
fi

if [[ "$VIDEO" = /* ]]; then
  VIDEO_PATH="$VIDEO"
  ROOT="$(cd "$(dirname "$VIDEO_PATH")" && pwd)"
  VIDEO="$(basename "$VIDEO_PATH")"
else
  VIDEO_PATH="${ROOT}/${VIDEO}"
fi

if [[ ! -f "$VIDEO_PATH" ]]; then
  echo "Video nao encontrado: $VIDEO_PATH" >&2
  exit 1
fi

BASE="${VIDEO%.mp4}"
mkdir -p "${ROOT}/audio" "${ROOT}/transcripts" "${ROOT}/frames" "${ROOT}/keyframes"

cd "$ROOT"

if [[ ! -f "audio/${BASE}.wav" ]]; then
  ffmpeg -y -i "$VIDEO" -vn -ac 1 -ar 16000 "audio/${BASE}.wav"
else
  echo "Audio ja existe: audio/${BASE}.wav"
fi

if [[ ! -f "transcripts/${BASE}.txt" ]]; then
  whisper-cli -m "models/ggml-small.bin" -l pt -f "audio/${BASE}.wav" -otxt -osrt -oj -of "transcripts/${BASE}"
else
  echo "Transcricao ja existe: transcripts/${BASE}.txt"
fi

if ! compgen -G "frames/${BASE}_*.jpg" >/dev/null; then
  ffmpeg -y -i "$VIDEO" -vf fps=1/5 "frames/${BASE}_%03d.jpg"
else
  echo "Frames ja existem: frames/${BASE}_*.jpg"
fi

if ! compgen -G "keyframes/${BASE}_scene_*.jpg" >/dev/null; then
  ffmpeg -y -skip_frame nokey -i "$VIDEO" -vsync vfr "keyframes/${BASE}_scene_%03d.jpg"
else
  echo "Keyframes ja existem: keyframes/${BASE}_scene_*.jpg"
fi

echo "Pronto: ${VIDEO}"
