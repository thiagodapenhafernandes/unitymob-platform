#!/usr/bin/env python3
"""
Coleta o contexto COMPLETO de um card do Trello e prepara todos os anexos
para análise multimodal (imagem, vídeo, áudio).

- Busca card (nome, desc, labels, due, lista), comentários e checklists.
- Baixa todos os anexos para uma pasta de trabalho.
- Imagens: ficam como arquivos (para o assistente abrir/visualizar).
- Vídeos: extrai áudio -> transcreve (whisper) + amostra frames/keyframes.
- Áudios: transcreve (whisper).
- Gera context.md com todo o texto + transcrições + ponteiros para as imagens.
- Imprime, no final, MANIFEST e a lista de IMAGES_TO_VIEW.

Uso:
  python3 trello_card_context.py <card_id | shortLink | url> [--no-media] [--frames-fps N]

Requer TRELLO_KEY e TRELLO_TOKEN no ambiente (source ~/.trello.env).
Ferramentas opcionais: ffmpeg (vídeo/áudio), whisper-cli (transcrição).
"""

import json
import os
import re
import subprocess
import sys
import urllib.parse
import urllib.request

KEY = os.environ.get("TRELLO_KEY", "")
TOKEN = os.environ.get("TRELLO_TOKEN", "")
HOME = os.path.expanduser("~")
WORKROOT = os.path.join(HOME, "worksapces", "trello-cards")
VIDEO_DEMANDA = os.path.join(HOME, "worksapces", "video-demanda")
WHISPER_MODEL = os.path.join(VIDEO_DEMANDA, "models", "ggml-small.bin")

IMAGE_EXT = {".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".heic", ".tiff"}
VIDEO_EXT = {".mp4", ".mov", ".m4v", ".webm", ".avi", ".mkv", ".3gp"}
AUDIO_EXT = {".mp3", ".wav", ".m4a", ".aac", ".ogg", ".opus", ".flac"}


def die(msg):
    print(f"ERRO: {msg}", file=sys.stderr)
    sys.exit(1)


def have(tool):
    return subprocess.run(["which", tool], capture_output=True).returncode == 0


def resolve_card_id(arg):
    """Aceita id de 24 chars, shortLink, ou URL trello.com/c/<shortLink>/..."""
    arg = arg.strip()
    m = re.search(r"trello\.com/c/([^/\s]+)", arg)
    if m:
        return m.group(1)
    return arg


def api_get(path, params=None):
    params = dict(params or {})
    params["key"] = KEY
    params["token"] = TOKEN
    url = f"https://api.trello.com/1/{path}?{urllib.parse.urlencode(params)}"
    with urllib.request.urlopen(url, timeout=30) as r:
        return json.loads(r.read().decode("utf-8"))


def download(url, dest):
    """Baixa um anexo. Uploads do Trello exigem cabeçalho OAuth."""
    headers = {}
    if "trello.com" in url or "trello-attachments" in url:
        headers["Authorization"] = f'OAuth oauth_consumer_key="{KEY}", oauth_token="{TOKEN}"'
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=120) as r, open(dest, "wb") as f:
            f.write(r.read())
        return os.path.getsize(dest) > 0
    except Exception as e:
        print(f"  ! falha ao baixar {url}: {e}", file=sys.stderr)
        return False


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def ext_of(name, mime):
    _, ext = os.path.splitext(name or "")
    ext = ext.lower()
    if ext:
        return ext
    mime = (mime or "").lower()
    if mime.startswith("image/"):
        return "." + mime.split("/")[-1].split(";")[0]
    if mime.startswith("video/"):
        return "." + mime.split("/")[-1].split(";")[0]
    if mime.startswith("audio/"):
        return "." + mime.split("/")[-1].split(";")[0]
    return ""


def kind_of(ext, mime):
    mime = (mime or "").lower()
    if ext in IMAGE_EXT or mime.startswith("image/"):
        return "image"
    if ext in VIDEO_EXT or mime.startswith("video/"):
        return "video"
    if ext in AUDIO_EXT or mime.startswith("audio/"):
        return "audio"
    return "other"


def transcribe(wav_path, out_base):
    if not have("whisper-cli") or not os.path.exists(WHISPER_MODEL):
        return None
    run(["whisper-cli", "-m", WHISPER_MODEL, "-l", "pt", "-f", wav_path, "-otxt", "-of", out_base])
    txt = out_base + ".txt"
    if os.path.exists(txt):
        with open(txt, encoding="utf-8") as f:
            return f.read().strip()
    return None


def process_video(path, workdir, base, fps, out):
    if not have("ffmpeg"):
        out.append("  (ffmpeg ausente — vídeo não processado)")
        return []
    audio_dir = os.path.join(workdir, "audio")
    frames_dir = os.path.join(workdir, "frames")
    key_dir = os.path.join(workdir, "keyframes")
    for d in (audio_dir, frames_dir, key_dir):
        os.makedirs(d, exist_ok=True)

    wav = os.path.join(audio_dir, base + ".wav")
    run(["ffmpeg", "-y", "-i", path, "-vn", "-ac", "1", "-ar", "16000", wav])

    transcript = None
    if os.path.exists(wav):
        transcript = transcribe(wav, os.path.join(workdir, "transcripts", base))
    if transcript:
        out.append(f"  Transcrição:\n{indent(transcript)}")
    else:
        out.append("  (sem transcrição — whisper indisponível ou áudio vazio)")

    run(["ffmpeg", "-y", "-i", path, "-vf", f"fps={fps}", os.path.join(frames_dir, base + "_%03d.jpg")])
    run(["ffmpeg", "-y", "-skip_frame", "nokey", "-i", path, "-vsync", "vfr",
         os.path.join(key_dir, base + "_scene_%03d.jpg")])
    imgs = sorted(
        [os.path.join(frames_dir, f) for f in os.listdir(frames_dir) if f.startswith(base + "_")]
        + [os.path.join(key_dir, f) for f in os.listdir(key_dir) if f.startswith(base + "_scene_")]
    )
    out.append(f"  Frames extraídos: {len(imgs)}")
    return imgs


def process_audio(path, workdir, base, out):
    os.makedirs(os.path.join(workdir, "audio"), exist_ok=True)
    os.makedirs(os.path.join(workdir, "transcripts"), exist_ok=True)
    wav = os.path.join(workdir, "audio", base + ".wav")
    if have("ffmpeg"):
        run(["ffmpeg", "-y", "-i", path, "-vn", "-ac", "1", "-ar", "16000", wav])
        src = wav if os.path.exists(wav) else path
    else:
        src = path
    transcript = transcribe(src, os.path.join(workdir, "transcripts", base))
    if transcript:
        out.append(f"  Transcrição:\n{indent(transcript)}")
    else:
        out.append("  (sem transcrição)")


def indent(text, prefix="    "):
    return "\n".join(prefix + line for line in text.splitlines())


def main():
    if not KEY or not TOKEN:
        die("TRELLO_KEY/TRELLO_TOKEN ausentes. Rode: source ~/.trello.env")
    args = [a for a in sys.argv[1:]]
    if not args:
        die("informe o card: <id | shortLink | url>")
    no_media = "--no-media" in args
    # Por padrão, vídeos/áudios são DELEGADOS à skill /analisar-video:
    # o script os copia para ~/worksapces/video-demanda e os lista como alvos.
    # Use --transcribe-inline para forçar transcrição/frames aqui mesmo.
    transcribe_inline = "--transcribe-inline" in args
    fps = "1/4"
    if "--frames-fps" in args:
        i = args.index("--frames-fps")
        fps = args[i + 1]
        args = args[:i] + args[i + 2:]
    args = [a for a in args if a not in ("--no-media", "--transcribe-inline")]
    card_ref = resolve_card_id(args[0])

    card = api_get(f"cards/{card_ref}", {"fields": "name,desc,due,url,shortLink,idList,labels"})
    card_id = card["id"]
    list_name = ""
    try:
        list_name = api_get(f"lists/{card['idList']}", {"fields": "name"}).get("name", "")
    except Exception:
        pass
    comments = api_get(f"cards/{card_id}/actions", {"filter": "commentCard", "limit": "50"})
    checklists = api_get(f"cards/{card_id}/checklists", {"fields": "name", "checkItem_fields": "name,state"})
    attachments = api_get(f"cards/{card_id}/attachments",
                          {"fields": "name,url,mimeType,bytes,isUpload,date"})

    workdir = os.path.join(WORKROOT, card.get("shortLink") or card_id)
    for d in ("", "attachments", "transcripts"):
        os.makedirs(os.path.join(workdir, d), exist_ok=True)

    out = []
    out.append(f"# Card: {card['name']}")
    out.append(f"- URL: {card['url']}")
    out.append(f"- Lista: {list_name}")
    labels = ", ".join(l.get("name") or l.get("color") for l in card.get("labels", []))
    if labels:
        out.append(f"- Labels: {labels}")
    if card.get("due"):
        out.append(f"- Prazo: {card['due']}")
    out.append("")
    out.append("## Descrição")
    out.append(card.get("desc") or "(vazia)")
    out.append("")

    if comments:
        out.append("## Comentários")
        for c in comments:
            who = c.get("memberCreator", {}).get("fullName", "?")
            when = c.get("date", "")[:10]
            txt = c.get("data", {}).get("text", "")
            out.append(f"- [{when}] {who}: {txt}")
        out.append("")

    if checklists:
        out.append("## Checklists")
        for cl in checklists:
            out.append(f"### {cl.get('name')}")
            for it in cl.get("checkItems", []):
                mark = "x" if it.get("state") == "complete" else " "
                out.append(f"- [{mark}] {it.get('name')}")
        out.append("")

    images_to_view = []
    analisar_video_targets = []  # nomes de arquivo em video-demanda p/ a skill /analisar-video
    short = card.get("shortLink") or card_id
    out.append("## Anexos")
    if not attachments:
        out.append("(nenhum)")
    for idx, att in enumerate(attachments, 1):
        name = att.get("name") or f"anexo_{idx}"
        mime = att.get("mimeType")
        url = att.get("url") or ""
        ext = ext_of(name, mime)
        kind = kind_of(ext, mime)
        safe = re.sub(r"[^A-Za-z0-9._-]", "_", name)[:60] or f"anexo_{idx}"
        base = f"{idx:02d}_{os.path.splitext(safe)[0]}"
        dest = os.path.join(workdir, "attachments", f"{base}{ext or ''}")
        out.append(f"\n### Anexo {idx}: {name}  ({kind}, {mime}, {att.get('bytes')} bytes)")
        out.append(f"- URL: {url}")

        if no_media or not url:
            out.append("  (download pulado)")
            continue
        if not download(url, dest):
            out.append("  (falha no download)")
            continue
        out.append(f"- Arquivo: {dest}")

        if kind == "image":
            images_to_view.append(dest)
        elif kind in ("video", "audio"):
            if transcribe_inline:
                if kind == "video":
                    images_to_view.extend(process_video(dest, workdir, base, fps, out))
                else:
                    process_audio(dest, workdir, base, out)
            else:
                # Delega para a skill /analisar-video: copia para video-demanda
                os.makedirs(VIDEO_DEMANDA, exist_ok=True)
                vd_name = f"card_{short}_{idx:02d}{ext or ('.mp4' if kind == 'video' else '.m4a')}"
                vd_path = os.path.join(VIDEO_DEMANDA, vd_name)
                try:
                    with open(dest, "rb") as s, open(vd_path, "wb") as d:
                        d.write(s.read())
                    analisar_video_targets.append(vd_name)
                    out.append(f"- Para /analisar-video: {vd_name}")
                except Exception as e:
                    out.append(f"  (falha ao copiar p/ video-demanda: {e})")

    manifest = os.path.join(workdir, "context.md")
    with open(manifest, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")

    print(f"MANIFEST: {manifest}")
    print(f"WORKDIR: {workdir}")
    print(f"IMAGES_TO_VIEW: {len(images_to_view)}")
    for p in images_to_view:
        print(f"  {p}")
    print(f"ANALISAR_VIDEO: {len(analisar_video_targets)}")
    for n in analisar_video_targets:
        print(f"  {n}")


if __name__ == "__main__":
    main()
