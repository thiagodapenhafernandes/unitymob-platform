import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).with_name('salute-memory-guard')


class MemoryGuardTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        commands = root / 'bin'
        commands.mkdir()
        self.calls = root / 'calls.jsonl'
        mock = commands / 'mock'
        mock.write_text('#!' + sys.executable + '\n' + '''
import json, os, subprocess, sys
from pathlib import Path
name = Path(sys.argv[0]).name
args = sys.argv[1:]
if name == 'awk':
    if '/proc/meminfo' in args:
        print('10000' if 'MemTotal' in args[0] else os.environ.get('FAKE_AVAILABLE', '500'))
    else:
        result = subprocess.run(['/usr/bin/awk', *args], input=sys.stdin.read(), text=True, capture_output=True)
        print(result.stdout, end='')
elif name == 'systemctl':
    if args[0] == 'show':
        print('123' if 'MainPID' in args else os.environ.get('FAKE_QUEUE_BYTES', '100') if args[1] == 'queue.service' else '200')
    elif args[0] == 'is-active':
        state = os.environ.get('FAKE_PUMA_STATE', 'active')
        print(state)
        sys.exit(0 if state == 'active' else 3)
    else:
        with open(os.environ['CALLS'], 'a') as output:
            output.write(json.dumps(args) + '\\n')
        if args[0] == 'reload' and os.environ.get('FAIL_RELOAD'):
            sys.exit(1)
''')
        mock.chmod(0o755)
        for name in ['awk', 'systemctl', 'ps', 'logger', 'flock']:
            (commands / name).symlink_to(mock)
        self.env = dict(os.environ, PATH=str(commands) + os.pathsep + os.environ['PATH'],
                        STATE_DIR=str(root / 'state'), CALLS=str(self.calls),
                        PUMA_UNIT='puma.service', QUEUE_UNIT='queue.service',
                        REQUIRED_SAMPLES='2', COOLDOWN_SECONDS='900', DEPLOY_MARKER='')

    def run_guard(self):
        return subprocess.run(['bash', str(SCRIPT)], env=self.env, text=True, capture_output=True)

    def actions(self):
        return [json.loads(line) for line in self.calls.read_text().splitlines()] if self.calls.exists() else []

    def test_active_puma_reloads_after_two_samples_and_obeys_cooldown(self):
        self.assertEqual(self.run_guard().returncode, 0)
        self.assertEqual(self.actions(), [])
        self.assertEqual(self.run_guard().returncode, 0)
        self.assertEqual(self.actions(), [['reload', 'puma.service']])
        self.run_guard()
        self.assertEqual(len(self.actions()), 1)

    def test_queue_keeps_its_existing_restart(self):
        self.env['FAKE_QUEUE_BYTES'] = '300'
        self.run_guard()
        self.assertEqual(self.run_guard().returncode, 0)
        self.assertEqual(self.actions(), [['restart', 'queue.service']])

    def test_inactive_puma_starts_with_restart(self):
        self.env['FAKE_PUMA_STATE'] = 'inactive'
        self.run_guard()
        self.assertEqual(self.run_guard().returncode, 0)
        self.assertEqual(self.actions(), [['restart', 'puma.service']])

    def test_failed_reload_does_not_fall_back_to_disruptive_restart(self):
        self.env['FAIL_RELOAD'] = '1'
        self.run_guard()
        self.assertNotEqual(self.run_guard().returncode, 0)
        self.assertEqual(self.actions(), [['reload', 'puma.service']])
        self.assertFalse((Path(self.env['STATE_DIR']) / 'last-action').exists())

    def test_healthy_memory_and_deploy_grace_do_not_touch_services(self):
        self.env['FAKE_AVAILABLE'] = '5000'
        self.run_guard()
        self.run_guard()
        self.assertEqual(self.actions(), [])
        marker = Path(self.tmp.name) / 'deploy'
        marker.touch()
        self.env.update(FAKE_AVAILABLE='500', DEPLOY_MARKER=str(marker))
        self.run_guard()
        self.assertEqual(self.actions(), [])


if __name__ == '__main__':
    unittest.main()
