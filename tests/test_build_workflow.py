"""Exercise the actual workflow's signing wiring and metadata verification run script."""
import json
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]


class BuildWorkflowTest(unittest.TestCase):
    def setUp(self):
        self.workflow = yaml.safe_load((ROOT/'.github/workflows/build.yml').read_text())
        self.steps = self.workflow['jobs']['build']['steps']

    def step(self, name):
        return next(step for step in self.steps if step.get('name') == name)

    def test_signing_outputs_are_used_by_the_actual_build(self):
        selector = self.step('Select APK signing mode')
        self.assertEqual(selector['id'], 'signing')
        build = self.step('Build APK')
        self.assertEqual(build['env']['ANDROID_KEYSTORE_FILE'], '${{ steps.signing.outputs.keystore_file }}')
        self.assertEqual(build['env']['KOJII_UNSIGNED_RELEASE'], "${{ steps.signing.outputs.mode == 'unsigned' }}")
        self.assertEqual(self.step('Verify APK signer')['if'], "steps.signing.outputs.mode == 'signed'")
        self.assertIn('steps.signing.outputs.mode', self.step('Upload APK')['with']['name'])
        for step in self.steps:
            if 'run' in step:
                script = re.sub(r'\$\{\{.*?\}\}', 'TEST', step['run'])
                subprocess.run(['bash', '-n'], input=script, text=True, check=True)

    def test_signed_and_unsigned_metadata_through_workflow_script(self):
        script = self.step('Verify package metadata and report signing mode')['run']
        cases = [
            ('signed', 'app-vanilla-release.apk', 'org.azahar_emu.azahar', True),
            ('unsigned', 'app-vanilla-release-unsigned.apk', 'org.azahar_emu.azahar', True),
            ('unsigned', 'app-vanilla-release.apk', 'org.azahar_emu.azahar', False),
            ('signed', 'app-vanilla-release.apk', 'wrong.package', False),
            ('unknown', 'app-vanilla-release.apk', 'org.azahar_emu.azahar', False),
        ]
        for mode, name, package, expected in cases:
            with self.subTest(mode=mode, name=name, package=package), tempfile.TemporaryDirectory(dir=ROOT/'.work') as temporary:
                directory = Path(temporary)
                metadata = directory/'azahar/src/android/app/build/outputs/apk/vanilla/release/output-metadata.json'
                metadata.parent.mkdir(parents=True)
                metadata.write_text(json.dumps({'applicationId': package, 'elements': [{'versionCode': 123, 'outputFile': name}]}))
                summary = directory/'summary'
                env = {**os.environ, 'SIGNING_MODE': mode, 'GITHUB_STEP_SUMMARY': str(summary)}
                result = subprocess.run(['bash', '-e', '-o', 'pipefail', '-c', script], cwd=directory,
                                        env=env, text=True, capture_output=True)
                self.assertEqual(result.returncode == 0, expected, result.stderr)
                if expected:
                    self.assertIn(f'Kojii APK: {mode}', summary.read_text())
                    if mode == 'unsigned':
                        self.assertIn('Not installable yet', summary.read_text())


if __name__ == '__main__':
    unittest.main()
