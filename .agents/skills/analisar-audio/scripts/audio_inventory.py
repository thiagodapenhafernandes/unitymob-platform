#!/usr/bin/env python3
import argparse
import json
import shutil
import subprocess
from pathlib import Path


DEFAULT_ROOT = Path("/Users/thiagodap.fernandes/worksapces/audio-demanda")
SUPPORTED_EXTENSIONS = {
    ".mp3",
    ".m4a",
    ".wav",
    ".ogg",
    ".oga",
    ".opus",
    ".aac",
    ".flac",
    ".webm",
    ".mp4",
    ".mov",
}


def run_ffprobe(audio: Path) -> dict:
    if not shutil.which("ffprobe"):
        return {}

    cmd = [
        "ffprobe",
        "-v",
        "error",
        "-show_entries",
        "format=duration,size:stream=codec_type,codec_name,sample_rate,channels",
        "-of",
        "json",
        str(audio),
    ]
    try:
        result = subprocess.run(cmd, check=True, capture_output=True, text=True)
        return json.loads(result.stdout)
    except Exception:
        return {}


def format_duration(seconds: float | None) -> str:
    if seconds is None:
        return "?"
    total = int(round(seconds))
    minutes, sec = divmod(total, 60)
    hours, minutes = divmod(minutes, 60)
    if hours:
        return f"{hours:d}:{minutes:02d}:{sec:02d}"
    return f"{minutes:d}:{sec:02d}"


def iter_audio_files(root: Path) -> list[Path]:
    if not root.exists():
        return []
    return sorted(
        path
        for path in root.iterdir()
        if path.is_file() and path.suffix.lower() in SUPPORTED_EXTENSIONS
    )


def find_audio(root: Path, value: str) -> Path | None:
    candidate = Path(value).expanduser()
    if candidate.is_absolute() and candidate.exists():
        return candidate

    direct = root / value
    if direct.exists():
        return direct

    base = Path(value).stem
    matches = [path for path in iter_audio_files(root) if path.stem == base]
    if len(matches) == 1:
        return matches[0]
    return None


def audio_info(root: Path, audio: Path) -> dict:
    base = audio.stem
    probe = run_ffprobe(audio)
    duration = None
    size = audio.stat().st_size
    codec = "?"
    sample_rate = "?"
    channels = "?"

    if probe.get("format", {}).get("duration"):
        duration = float(probe["format"]["duration"])
    if probe.get("format", {}).get("size"):
        size = int(probe["format"]["size"])

    for stream in probe.get("streams", []):
        if stream.get("codec_type") == "audio":
            codec = stream.get("codec_name") or "?"
            sample_rate = stream.get("sample_rate") or "?"
            channels = stream.get("channels") or "?"
            break

    transcripts = sorted((root / "transcripts").glob(f"{base}.*"))
    normalized = sorted((root / "normalized").glob(f"{base}.*"))

    return {
        "base": base,
        "file": audio.name,
        "path": str(audio),
        "duration": format_duration(duration),
        "duration_seconds": duration,
        "size_mb": round(size / 1024 / 1024, 1),
        "codec": codec,
        "sample_rate": sample_rate,
        "channels": channels,
        "transcripts": [p.name for p in transcripts],
        "normalized": [p.name for p in normalized],
    }


def print_inventory(root: Path, infos: list[dict]) -> None:
    print(f"Root: {root}")
    print("")
    if not root.exists():
        print("Pasta nao existe. Crie a pasta e coloque os audios nela.")
        return
    if not infos:
        print("Nenhum audio encontrado.")
        print("Extensoes aceitas: " + ", ".join(sorted(SUPPORTED_EXTENSIONS)))
        return

    for index, info in enumerate(infos, start=1):
        transcript_status = "sim" if info["transcripts"] else "nao"
        normalized_status = "sim" if info["normalized"] else "nao"
        print(
            f"{index}. {info['file']} | {info['duration']} | {info['size_mb']} MB | "
            f"codec={info['codec']} | sr={info['sample_rate']} | ch={info['channels']} | "
            f"transcript={transcript_status} | normalized={normalized_status}"
        )


def print_commands(root: Path, info: dict) -> None:
    base = info["base"]
    audio = info["file"]
    print("")
    print(f"Comandos para {audio}:")
    print(f"cd {root}")
    print(f'mkdir -p normalized transcripts models')
    print(f'rm -f "normalized/{base}.wav" "transcripts/{base}.txt" "transcripts/{base}.srt" "transcripts/{base}.json"')
    print(f'ffmpeg -y -i "{audio}" -vn -ac 1 -ar 16000 "normalized/{base}.wav"')
    print(
        f'whisper-cli -m "models/ggml-small.bin" -l pt -f "normalized/{base}.wav" '
        f'-otxt -osrt -oj -of "transcripts/{base}"'
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Inventario de audios de demanda.")
    parser.add_argument("--root", default=str(DEFAULT_ROOT), help="Pasta audio-demanda")
    parser.add_argument("--audio", help="Nome/base do audio para mostrar comandos")
    parser.add_argument("--json", action="store_true", help="Saida JSON")
    args = parser.parse_args()

    root = Path(args.root).expanduser().resolve()
    audios = iter_audio_files(root)
    infos = [audio_info(root, audio) for audio in audios]

    if args.json:
        print(json.dumps(infos, ensure_ascii=False, indent=2))
    else:
        print_inventory(root, infos)

    if args.audio:
        selected_path = find_audio(root, args.audio)
        if not selected_path:
            print("")
            print(f"Audio nao encontrado ou ambiguo: {args.audio}")
            return 1
        print_commands(root, audio_info(root, selected_path))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
