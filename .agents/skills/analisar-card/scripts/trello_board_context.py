#!/usr/bin/env python3
"""
Percorre os cards de um QUADRO ou de uma COLUNA (lista) do Trello e coleta o
contexto multimodal de cada card (texto + imagens + vídeo/áudio), chamando o
coletor por card (trello_card_context.py).

Uso:
  python3 trello_board_context.py --board <board_id|url> [--list "Para fazer"] [flags do card]
  python3 trello_board_context.py --list-id <list_id> [flags do card]

Flags repassadas ao coletor por card: --no-media, --transcribe-inline, --frames-fps N.

Imprime um ÍNDICE: por card, o caminho do context.md, nº de imagens e de mídias
para /analisar-video, e ao final os totais agregados.

Requer TRELLO_KEY/TRELLO_TOKEN (source ~/.trello.env).
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
HERE = os.path.dirname(os.path.abspath(__file__))
CARD_SCRIPT = os.path.join(HERE, "trello_card_context.py")


def die(msg):
    print(f"ERRO: {msg}", file=sys.stderr)
    sys.exit(1)


def api_get(path, params=None):
    params = dict(params or {})
    params["key"] = KEY
    params["token"] = TOKEN
    url = f"https://api.trello.com/1/{path}?{urllib.parse.urlencode(params)}"
    with urllib.request.urlopen(url, timeout=30) as r:
        return json.loads(r.read().decode("utf-8"))


def resolve_board_id(arg):
    m = re.search(r"trello\.com/b/([^/\s]+)", arg)
    return m.group(1) if m else arg.strip()


def main():
    if not KEY or not TOKEN:
        die("TRELLO_KEY/TRELLO_TOKEN ausentes. Rode: source ~/.trello.env")

    argv = sys.argv[1:]
    board = list_name = list_id = None
    passthrough = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--board":
            board = argv[i + 1]; i += 2
        elif a == "--list":
            list_name = argv[i + 1]; i += 2
        elif a == "--list-id":
            list_id = argv[i + 1]; i += 2
        elif a == "--frames-fps":
            passthrough += [a, argv[i + 1]]; i += 2
        elif a in ("--no-media", "--transcribe-inline"):
            passthrough.append(a); i += 1
        else:
            die(f"argumento desconhecido: {a}")

    # Descobrir as listas-alvo e seus cards
    targets = []  # (list_name, list_id)
    if list_id:
        nm = ""
        try:
            nm = api_get(f"lists/{list_id}", {"fields": "name"}).get("name", "")
        except Exception:
            pass
        targets = [(nm, list_id)]
    elif board:
        bid = resolve_board_id(board)
        lists = api_get(f"boards/{bid}/lists", {"fields": "name"})
        if list_name:
            wanted = list_name.strip().lower()
            lists = [l for l in lists if l["name"].strip().lower() == wanted]
            if not lists:
                die(f"coluna '{list_name}' não encontrada no board")
        targets = [(l["name"], l["id"]) for l in lists]
    else:
        die("informe --board <id|url> ou --list-id <id>")

    print(f"# Índice de análise — {len(targets)} coluna(s)\n")
    total_cards = total_imgs = total_media = 0
    env = dict(os.environ)

    for lname, lid in targets:
        cards = api_get(f"lists/{lid}/cards", {"fields": "name,shortLink"})
        print(f"## Coluna: {lname}  ({len(cards)} cards)")
        for c in cards:
            total_cards += 1
            res = subprocess.run(
                [sys.executable, CARD_SCRIPT, c["id"], *passthrough],
                capture_output=True, text=True, env=env,
            )
            out = res.stdout
            manifest = next((l.split("MANIFEST:", 1)[1].strip()
                             for l in out.splitlines() if l.startswith("MANIFEST:")), "?")
            n_img = next((int(l.split(":", 1)[1].split()[0])
                          for l in out.splitlines() if l.startswith("IMAGES_TO_VIEW:")), 0)
            n_vid = next((int(l.split(":", 1)[1].split()[0])
                          for l in out.splitlines() if l.startswith("ANALISAR_VIDEO:")), 0)
            total_imgs += n_img
            total_media += n_vid
            status = "" if res.returncode == 0 else "  [FALHA]"
            print(f"- {c['name']}{status}")
            print(f"    manifest: {manifest}")
            print(f"    imagens: {n_img} | midias p/ /analisar-video: {n_vid}")
            # Repassa as linhas de arquivo (imagens e nomes de vídeo) para o assistente
            capture = False
            for l in out.splitlines():
                if l.startswith("IMAGES_TO_VIEW:") or l.startswith("ANALISAR_VIDEO:"):
                    capture = True
                    continue
                if capture and l.startswith("  "):
                    print(f"    {l.strip()}")
                elif capture and l and not l.startswith("  "):
                    capture = l.startswith(("IMAGES", "ANALISAR"))
        print()

    print(f"# Totais: {total_cards} cards | {total_imgs} imagens | {total_media} mídias p/ /analisar-video")


if __name__ == "__main__":
    main()
