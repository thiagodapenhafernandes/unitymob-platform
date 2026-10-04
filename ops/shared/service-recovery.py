#!/usr/bin/env python3
"""Recuperação limitada de Puma/fila. Não reinicia banco/cache por falha HTTP."""
import json
import os
from pathlib import Path
import subprocess
import time


def failed_targets(puma, queue, code, checks):
    targets = []
    if puma in ('inactive', 'failed') or (puma == 'active' and code not in (200, 503)):
        targets.append('puma')
    if queue in ('inactive', 'failed') or (checks.get('db') == 'ok' and checks.get('queue') == 'fail'):
        targets.append('queue')
    return targets


def main():
    state_dir = Path(os.environ['STATE_DIR'])
    state_dir.mkdir(parents=True, exist_ok=True)
    marker = Path(os.environ['DEPLOY_MARKER'])
    now = time.time()
    if marker.exists() and now - marker.stat().st_mtime < 600:
        print('deploy grace period')
        return
    units = {name: os.environ[name.upper() + '_UNIT'] for name in ('puma', 'queue')}
    states = {name: subprocess.run(['systemctl', 'is-active', unit], capture_output=True, text=True).stdout.strip()
              for name, unit in units.items()}
    probe = subprocess.run(['curl', '-sS', '--max-time', '12', '-H', 'X-Forwarded-Proto: https',
                            '-H', 'Host: ' + os.environ['PUBLIC_HOST'], '-w', '\n%{http_code}',
                            'http://127.0.0.1:9292/healthz'], capture_output=True, text=True)
    body, _, code = probe.stdout.rpartition('\n')
    try:
        checks = json.loads(body)
        if not isinstance(checks, dict):
            checks = {}
    except ValueError:
        checks = {}
    try:
        state = json.loads((state_dir / 'state.json').read_text())
    except (FileNotFoundError, ValueError):
        state = {}
    failed = failed_targets(states['puma'], states['queue'], int(code or 0), checks)
    for name, unit in units.items():
        count = state.get(name + '_failures', 0) + 1 if name in failed else 0
        state[name + '_failures'] = count
        if count >= 3 and now - state.get(name + '_restart', 0) >= 900:
            # Uma unit mascarada é manutenção explícita; nunca desfazer a máscara.
            enabled = subprocess.run(['systemctl', 'is-enabled', unit], capture_output=True, text=True).stdout.strip()
            if enabled.startswith('masked'):
                continue
            state[name + '_restart'] = now
            (state_dir / 'state.json').write_text(json.dumps(state))
            subprocess.run(['systemctl', 'reset-failed', unit], check=True)
            subprocess.run(['systemctl', 'restart', unit], check=True)
            state[name + '_failures'] = 0
            print('recovered ' + unit, flush=True)
    (state_dir / 'state.json').write_text(json.dumps(state))
    print(json.dumps({'services': states, 'http': code, 'checks': checks, 'failures': failed}), flush=True)


if __name__ == '__main__':
    main()
