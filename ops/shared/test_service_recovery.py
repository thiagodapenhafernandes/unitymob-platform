import unittest
import json
import os
import tempfile
from unittest.mock import patch
from subprocess import CompletedProcess
from importlib.machinery import SourceFileLoader
from pathlib import Path

recovery = SourceFileLoader('recovery', str(Path(__file__).with_name('service-recovery.py'))).load_module()

class RecoveryTest(unittest.TestCase):
    def test_target_selection(self):
        self.assertEqual(recovery.failed_targets('active', 'active', 200, {'db': 'ok', 'queue': 'ok'}), [])
        self.assertEqual(recovery.failed_targets('active', 'active', 503, {'db': 'fail', 'queue': 'fail'}), [])
        self.assertEqual(recovery.failed_targets('active', 'active', 503, {'db': 'ok', 'queue': 'fail'}), ['queue'])
        self.assertEqual(recovery.failed_targets('active', 'active', 0, {}), ['puma'])
        self.assertEqual(recovery.failed_targets('failed', 'inactive', 0, {}), ['puma', 'queue'])
        self.assertEqual(recovery.failed_targets('inactive', 'active', 0, {}), ['puma'])

    def test_samples_cooldown_and_deploy_grace(self):
        with tempfile.TemporaryDirectory() as tmp:
            marker = Path(tmp) / 'deploy'
            env = {'STATE_DIR': tmp, 'DEPLOY_MARKER': str(marker), 'PUBLIC_HOST': 'example.com',
                   'PUMA_UNIT': 'puma.service', 'QUEUE_UNIT': 'queue.service'}
            calls = []
            def command(args, **kwargs):
                calls.append(args)
                if args[0] == 'curl':
                    return CompletedProcess(args, 7, stdout='\n000')
                value = 'enabled' if args[1] == 'is-enabled' else 'active'
                return CompletedProcess(args, 0, stdout=value)
            with patch.dict(os.environ, env), patch.object(recovery.subprocess, 'run', side_effect=command):
                recovery.main()
                recovery.main()
                self.assertFalse(any('restart' in call for call in calls))
                recovery.main()
                self.assertEqual(sum('restart' in call for call in calls), 1)
                for _ in range(4):
                    recovery.main()
                self.assertEqual(sum('restart' in call for call in calls), 1)
                marker.touch()
                before = len(calls)
                recovery.main()
                self.assertEqual(len(calls), before)

if __name__ == '__main__':
    unittest.main()
