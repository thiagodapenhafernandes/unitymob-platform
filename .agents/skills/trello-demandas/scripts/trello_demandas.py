#!/usr/bin/env python3
"""
Runner global para demandas do Trello.

Exemplos:
  python3 trello_demandas.py quadro "Prioridades"
  python3 trello_demandas.py card "nome ou id"
  python3 trello_demandas.py mover "nome ou id" "Em desenvolvimento"
  python3 trello_demandas.py comentar "nome ou id" "texto"
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.parse
import urllib.request
from pathlib import Path

KEY = os.environ.get("TRELLO_KEY", "")
TOKEN = os.environ.get("TRELLO_TOKEN", "")
HERE = Path(__file__).resolve().parent
CARD_CONTEXT = HERE / "trello_card_context.py"
BOARD_CONTEXT = HERE / "trello_board_context.py"


def die(message: str, code: int = 1) -> None:
    print(f"ERRO: {message}", file=sys.stderr)
    raise SystemExit(code)


def require_auth() -> None:
    if not KEY or not TOKEN:
        die("TRELLO_KEY/TRELLO_TOKEN ausentes. Rode: source ~/.trello.env")


def api(path: str, params: dict | None = None, method: str = "GET") -> object:
    params = dict(params or {})
    params["key"] = KEY
    params["token"] = TOKEN
    encoded = urllib.parse.urlencode(params)
    url = f"https://api.trello.com/1/{path}?{encoded}"
    req = urllib.request.Request(url, method=method)
    with urllib.request.urlopen(req, timeout=45) as response:
        body = response.read().decode("utf-8")
        return json.loads(body) if body else {}


def normalize(text: str) -> str:
    return re.sub(r"\s+", " ", text.strip().lower())


def is_card_ref(value: str) -> bool:
    value = value.strip()
    return bool(
        re.search(r"trello\.com/c/([^/\s]+)", value)
        or re.fullmatch(r"[0-9a-fA-F]{24}", value)
        or re.fullmatch(r"[A-Za-z0-9]{8}", value)
    )


def resolve_board_ref(value: str) -> str:
    match = re.search(r"trello\.com/b/([^/\s]+)", value)
    return match.group(1) if match else value.strip()


def boards() -> list[dict]:
    return api("members/me/boards", {"fields": "name,url"})  # type: ignore[return-value]


def lists_for_board(board_id: str) -> list[dict]:
    return api(f"boards/{board_id}/lists", {"fields": "name"})  # type: ignore[return-value]


def cards_for_list(list_id: str, fields: str = "name,desc,url,due,shortLink,idList,labels") -> list[dict]:
    return api(f"lists/{list_id}/cards", {"fields": fields})  # type: ignore[return-value]


def resolve_board(value: str) -> dict | None:
    ref = resolve_board_ref(value)
    if re.fullmatch(r"[0-9a-fA-F]{24}|[A-Za-z0-9]{8}", ref):
        try:
            return api(f"boards/{ref}", {"fields": "name,url"})  # type: ignore[return-value]
        except Exception:
            pass

    wanted = normalize(value)
    matches = [board for board in boards() if wanted in normalize(board.get("name", ""))]
    if len(matches) == 1:
        return matches[0]
    if len(matches) > 1:
        print_matches("Boards encontrados", matches)
        die("mais de um board encontrado; informe um nome mais específico ou o ID")
    return None


def all_lists() -> list[tuple[dict, dict]]:
    found = []
    for board in boards():
        for trello_list in lists_for_board(board["id"]):
            found.append((board, trello_list))
    return found


def resolve_list(value: str, board_name: str | None = None) -> tuple[dict, dict] | None:
    if re.fullmatch(r"[0-9a-fA-F]{24}", value.strip()):
        trello_list = api(f"lists/{value.strip()}", {"fields": "name,idBoard"})  # type: ignore[assignment]
        board = api(f"boards/{trello_list['idBoard']}", {"fields": "name,url"})  # type: ignore[index]
        return board, trello_list  # type: ignore[return-value]

    candidates = all_lists()
    if board_name:
        board = resolve_board(board_name)
        if not board:
            die(f"board não encontrado: {board_name}")
        candidates = [(b, l) for b, l in candidates if b["id"] == board["id"]]

    wanted = normalize(value)
    matches = [(b, l) for b, l in candidates if wanted in normalize(l.get("name", ""))]
    if len(matches) == 1:
        return matches[0]
    if len(matches) > 1:
        print("Listas encontradas:")
        for board, trello_list in matches:
            print(f"- {trello_list['id']}\t{board['name']} / {trello_list['name']}")
        die("mais de uma lista encontrada; informe --quadro ou o ID da lista")
    return None


def print_matches(title: str, matches: list[dict]) -> None:
    print(f"{title}:")
    for item in matches:
        name = item.get("name", "(sem nome)")
        url = item.get("url", "")
        short = item.get("shortLink", "")
        print(f"- {item.get('id')}\t{short}\t{name}\t{url}")


def card_search_pool(board_name: str | None, list_name: str | None) -> list[dict]:
    list_pairs = all_lists()
    if board_name:
        board = resolve_board(board_name)
        if not board:
            die(f"board não encontrado: {board_name}")
        list_pairs = [(b, l) for b, l in list_pairs if b["id"] == board["id"]]
    if list_name:
        resolved = resolve_list(list_name, board_name=board_name)
        if not resolved:
            die(f"lista não encontrada: {list_name}")
        _, selected_list = resolved
        list_pairs = [(b, l) for b, l in list_pairs if l["id"] == selected_list["id"]]

    cards = []
    for board, trello_list in list_pairs:
        for card in cards_for_list(trello_list["id"]):
            card["_boardName"] = board["name"]
            card["_listName"] = trello_list["name"]
            cards.append(card)
    return cards


def resolve_card(value: str, board_name: str | None = None, list_name: str | None = None) -> dict:
    if is_card_ref(value):
        ref_match = re.search(r"trello\.com/c/([^/\s]+)", value)
        ref = ref_match.group(1) if ref_match else value.strip()
        return api(f"cards/{ref}", {"fields": "name,desc,url,due,shortLink,idList,labels"})  # type: ignore[return-value]

    wanted = normalize(value)
    pool = card_search_pool(board_name, list_name)
    exact = [card for card in pool if normalize(card.get("name", "")) == wanted]
    partial = [card for card in pool if wanted in normalize(card.get("name", ""))]
    matches = exact or partial

    if len(matches) == 1:
        return matches[0]
    if len(matches) > 1:
        print("Cards encontrados:")
        for card in matches:
            print(
                f"- {card['id']}\t{card.get('shortLink', '')}\t"
                f"{card.get('_boardName', '?')} / {card.get('_listName', '?')} / {card['name']}"
            )
        die("mais de um card encontrado; informe ID, shortLink ou filtro --quadro/--lista")
    die(f"card não encontrado: {value}")


def run_context(card_id: str, passthrough: list[str]) -> int:
    cmd = [sys.executable, str(CARD_CONTEXT), card_id, *passthrough]
    return subprocess.run(cmd, check=False).returncode


def cmd_card(args: argparse.Namespace) -> int:
    card = resolve_card(args.card, args.quadro, args.lista)
    print(f"CARD_RESOLVIDO: {card['id']}\t{card.get('shortLink', '')}\t{card['name']}\t{card.get('url', '')}", flush=True)
    passthrough = []
    if args.no_media:
        passthrough.append("--no-media")
    if args.transcribe_inline:
        passthrough.append("--transcribe-inline")
    if args.frames_fps:
        passthrough.extend(["--frames-fps", args.frames_fps])
    return run_context(card["id"], passthrough)


def cmd_quadro(args: argparse.Namespace) -> int:
    selected_list = resolve_list(args.nome, board_name=args.quadro)
    if selected_list:
        board, trello_list = selected_list
        print(f"LISTA_RESOLVIDA: {board['name']} / {trello_list['name']} ({trello_list['id']})")
        cards = cards_for_list(trello_list["id"], fields="name,url,due,shortLink,labels")
        print(f"CARDS: {len(cards)}")
        for card in cards:
            labels = ",".join(label.get("name") or label.get("color", "") for label in card.get("labels", []))
            due = card.get("due") or ""
            print(f"- {card['id']}\t{card.get('shortLink', '')}\t{card['name']}\t{due}\t{labels}\t{card.get('url', '')}")
        return 0

    board = resolve_board(args.nome)
    if not board:
        die(f"nenhuma lista ou board encontrado para: {args.nome}")
    print(f"BOARD_RESOLVIDO: {board['id']}\t{board['name']}\t{board.get('url', '')}")
    for trello_list in lists_for_board(board["id"]):
        cards = cards_for_list(trello_list["id"], fields="name,url,due,shortLink,labels")
        print(f"\n## {trello_list['name']} ({len(cards)} cards)")
        for card in cards:
            labels = ",".join(label.get("name") or label.get("color", "") for label in card.get("labels", []))
            due = card.get("due") or ""
            print(f"- {card['id']}\t{card.get('shortLink', '')}\t{card['name']}\t{due}\t{labels}\t{card.get('url', '')}")
    return 0


def cmd_mover(args: argparse.Namespace) -> int:
    card = resolve_card(args.card, args.quadro, args.lista)
    resolved_list = resolve_list(args.destino, board_name=args.quadro)
    if not resolved_list:
        die(f"lista de destino não encontrada: {args.destino}")
    _, dest_list = resolved_list
    moved = api(f"cards/{card['id']}", {"idList": dest_list["id"]}, method="PUT")  # type: ignore[assignment]
    print(f"MOVIDO: {moved['id']}\t{moved['name']}\t{dest_list['name']}")  # type: ignore[index]
    return 0


def cmd_comentar(args: argparse.Namespace) -> int:
    card = resolve_card(args.card, args.quadro, args.lista)
    action = api(f"cards/{card['id']}/actions/comments", {"text": args.texto}, method="POST")  # type: ignore[assignment]
    print(f"COMENTARIO_CRIADO: {action['id']}\t{card['name']}")  # type: ignore[index]
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Resolve e analisa demandas do Trello.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    quadro = subparsers.add_parser("quadro", help="Lista cards de uma lista ou board por nome/id.")
    quadro.add_argument("nome")
    quadro.add_argument("--quadro", help="Restringe busca de lista a um board.")
    quadro.set_defaults(func=cmd_quadro)

    card = subparsers.add_parser("card", help="Resolve card por nome/id e gera contexto multimodal.")
    card.add_argument("card")
    card.add_argument("--quadro")
    card.add_argument("--lista")
    card.add_argument("--no-media", action="store_true")
    card.add_argument("--transcribe-inline", action="store_true")
    card.add_argument("--frames-fps")
    card.set_defaults(func=cmd_card)

    mover = subparsers.add_parser("mover", help="Move card para uma lista.")
    mover.add_argument("card")
    mover.add_argument("destino")
    mover.add_argument("--quadro")
    mover.add_argument("--lista", help="Lista atual usada para restringir busca do card.")
    mover.set_defaults(func=cmd_mover)

    comentar = subparsers.add_parser("comentar", help="Comenta em um card.")
    comentar.add_argument("card")
    comentar.add_argument("texto")
    comentar.add_argument("--quadro")
    comentar.add_argument("--lista")
    comentar.set_defaults(func=cmd_comentar)

    return parser


def main() -> int:
    require_auth()
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
