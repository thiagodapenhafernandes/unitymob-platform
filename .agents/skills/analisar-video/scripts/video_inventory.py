#!/usr/bin/env python3
import argparse
import json
import shutil
import subprocess
from pathlib import Path


DEFAULT_ROOT = Path("/Users/thiagodap.fernandes/worksapces/video-demanda")


def run_ffprobe(video: Path) -> dict:
    if not shutil.which("ffprobe"):
        return {}

    cmd = [
        "ffprobe",
        "-v",
        "error",
        "-show_entries",
        "format=duration,size:stream=codec_type,width,height",
        "-of",
        "json",
        str(video),
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


def video_info(root: Path, video: Path) -> dict:
    base = video.stem
    probe = run_ffprobe(video)
    duration = None
    size = video.stat().st_size
    width = height = None

    if probe.get("format", {}).get("duration"):
        duration = float(probe["format"]["duration"])
    if probe.get("format", {}).get("size"):
        size = int(probe["format"]["size"])

    for stream in probe.get("streams", []):
        if stream.get("codec_type") == "video":
            width = stream.get("width")
            height = stream.get("height")
            break

    transcripts = sorted((root / "transcripts").glob(f"{base}.*"))
    audio = sorted((root / "audio").glob(f"{base}.*"))
    frames = sorted((root / "frames").glob(f"{base}_*.jpg"))
    keyframes = sorted((root / "keyframes").glob(f"{base}_scene_*.jpg"))

    return {
        "base": base,
        "file": video.name,
        "path": str(video),
        "duration": format_duration(duration),
        "duration_seconds": duration,
        "size_mb": round(size / 1024 / 1024, 1),
        "resolution": f"{width}x{height}" if width and height else "?",
        "transcripts": [p.name for p in transcripts],
        "audio": [p.name for p in audio],
        "frames_count": len(frames),
        "keyframes_count": len(keyframes),
    }


def print_inventory(root: Path, infos: list[dict]) -> None:
    print(f"Root: {root}")
    print("")
    if not infos:
        print("Nenhum .mp4 encontrado.")
        return

    for index, info in enumerate(infos, start=1):
        transcript_status = "sim" if info["transcripts"] else "nao"
        audio_status = "sim" if info["audio"] else "nao"
        print(
            f"{index}. {info['file']} | {info['duration']} | {info['resolution']} | "
            f"{info['size_mb']} MB | transcript={transcript_status} | audio={audio_status} | "
            f"frames={info['frames_count']} | keyframes={info['keyframes_count']}"
        )


def print_commands(root: Path, info: dict) -> None:
    base = info["base"]
    video = info["file"]
    print("")
    print(f"Comandos para {video}:")
    print(f"cd {root}")
    print(f'ffmpeg -y -i "{video}" -vn -ac 1 -ar 16000 "audio/{base}.wav"')
    print(
        f'whisper-cli -m "models/ggml-small.bin" -l pt -f "audio/{base}.wav" '
        f'-otxt -osrt -oj -of "transcripts/{base}"'
    )
    print(f'ffmpeg -y -i "{video}" -vf fps=1/5 "frames/{base}_%03d.jpg"')
    print(f'ffmpeg -y -skip_frame nokey -i "{video}" -vsync vfr "keyframes/{base}_scene_%03d.jpg"')


def main() -> int:
    parser = argparse.ArgumentParser(description="Inventario de videos de demanda.")
    parser.add_argument("--root", default=str(DEFAULT_ROOT), help="Pasta video-demanda")
    parser.add_argument("--video", help="Nome/base do video para mostrar comandos")
    parser.add_argument("--json", action="store_true", help="Saida JSON")
    args = parser.parse_args()

    root = Path(args.root).expanduser().resolve()
    videos = sorted(root.glob("*.mp4"))
    infos = [video_info(root, video) for video in videos]

    if args.json:
        print(json.dumps(infos, ensure_ascii=False, indent=2))
    else:
        print_inventory(root, infos)

    if args.video:
        selected = next((i for i in infos if i["base"] == args.video or i["file"] == args.video), None)
        if not selected:
            print("")
            print(f"Video nao encontrado: {args.video}")
            return 1
        print_commands(root, selected)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
