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

    def index(self, name):
        return [step.get('name') for step in self.steps].index(name)

    def test_every_build_is_signed_with_a_reused_or_provisioned_identity(self):
        restore = self.step('Restore provisioned signing identity')
        self.assertEqual(restore['uses'], 'actions/cache/restore@v4')
        self.assertEqual(restore['with']['path'], '.signing')
        self.assertEqual(restore['with']['key'], 'koji-provisioned-signing-v1')

        selector = self.step('Select APK signing identity')
        self.assertEqual(selector['id'], 'signing')
        for key in ('ANDROID_KEYSTORE_BASE64', 'ANDROID_KEYSTORE_PASS', 'ANDROID_KEY_ALIAS'):
            self.assertEqual(selector['env'][key], f'${{{{ secrets.{key} }}}}')

        provision = self.step('Provision signing identity')
        self.assertEqual(provision['if'], "steps.signing.outputs.mode == 'generate'")
        self.assertIn('tools/generate_signing_key.sh', provision['run'])

        # A restored key must be in place before the identity is selected.
        self.assertLess(self.index('Restore provisioned signing identity'),
                        self.index('Select APK signing identity'))
        self.assertLess(self.index('Select APK signing identity'),
                        self.index('Provision signing identity'))

        # The build consumes the selected identity instead of hardcoding one mode.
        build = self.step('Build APK')
        self.assertNotIn('KOJII_UNSIGNED_RELEASE', build.get('env', {}))
        self.assertNotIn('ANDROID_KEYSTORE_FILE', build.get('env', {}))
        self.assertIn('. "$KOJII_SIGNING_ENV"', build['run'])
        self.assertIn('assembleVanillaRelease', build['run'])

        # Every artifact is signed, so the signer check is unconditional.
        self.assertNotIn('if', self.step('Verify APK signer'))
        self.assertEqual(self.step('Verify package metadata and report signing identity')['env']['SIGNING_SOURCE'],
                         '${{ steps.signing.outputs.mode }}')
        self.assertEqual(self.step('Upload APK')['with']['name'], 'kojii-${{ steps.ver.outputs.tag }}')

        # The provisioned key is persisted before the temporary material is removed.
        for name in ('Save provisioned signing identity', 'Upload provisioned signing identity'):
            self.assertEqual(self.step(name)['if'], "steps.signing.outputs.mode == 'generate'")
        self.assertLess(self.index('Save provisioned signing identity'),
                        self.index('Remove temporary signing material'))
        self.assertLess(self.index('Upload provisioned signing identity'),
                        self.index('Remove temporary signing material'))

        self.assertNotIn('KOJII_UNSIGNED_RELEASE',
                         '\n'.join(step.get('run', '') + json.dumps(step.get('env', {})) for step in self.steps))

        for step in self.steps:
            if 'run' in step:
                script = re.sub(r'\$\{\{.*?\}\}', 'TEST', step['run'])
                subprocess.run(['bash', '-n'], input=script, text=True, check=True)

    def test_job_level_environment_avoids_the_unavailable_runner_context(self):
        # ${{ runner.* }} in jobs.<job_id>.env invalidates the whole workflow ("Unrecognized
        # named-value: runner"), and an invalid workflow runs zero jobs, so the signing env path
        # is set on each step that consumes it instead.
        self.assertNotIn('runner.', json.dumps(self.workflow['jobs']['build']['env']))
        for name in ('Select APK signing identity', 'Provision signing identity', 'Build APK',
                     'Remove temporary signing material'):
            self.assertEqual(self.step(name)['env']['KOJII_SIGNING_ENV'],
                             '${{ runner.temp }}/signing.env')

    def test_provisioning_artifact_can_be_promoted_to_secrets(self):
        upload = self.step('Upload provisioned signing identity')
        paths = upload['with']['path'].split()
        for name in ('provisioned.p12', 'provisioned.pass', 'alias', 'keystore.b64',
                     'PROMOTE-TO-SECRETS.txt'):
            self.assertTrue(any(path.endswith(name) for path in paths), f'{name} must be uploaded')
        self.assertLessEqual(int(upload['with']['retention-days']), 7)
        generator = (ROOT/'tools/generate_signing_key.sh').read_text()
        self.assertIn('ANDROID_KEYSTORE_BASE64', generator)
        self.assertIn('PROMOTE-TO-SECRETS.txt', generator)

    def test_metadata_script_requires_signed_output_from_a_known_identity(self):
        script = self.step('Verify package metadata and report signing identity')['run']
        cases = [
            ('secrets', 'app-vanilla-release.apk', 'org.azahar_emu.azahar', True),
            ('cached', 'app-vanilla-release.apk', 'org.azahar_emu.azahar', True),
            ('generate', 'app-vanilla-release.apk', 'org.azahar_emu.azahar', True),
            ('unsigned', 'app-vanilla-release.apk', 'org.azahar_emu.azahar', False),
            ('secrets', 'app-vanilla-release-unsigned.apk', 'org.azahar_emu.azahar', False),
            ('secrets', 'app-vanilla-release.apk', 'wrong.package', False),
        ]
        for source, name, package, expected in cases:
            with self.subTest(source=source, name=name, package=package), \
                    tempfile.TemporaryDirectory(dir=ROOT/'.work') as temporary:
                directory = Path(temporary)
                metadata = directory/'azahar/src/android/app/build/outputs/apk/vanilla/release/output-metadata.json'
                metadata.parent.mkdir(parents=True)
                metadata.write_text(json.dumps({'applicationId': package, 'elements': [{'versionCode': 123, 'outputFile': name}]}))
                summary = directory/'summary'
                env = {**os.environ, 'SIGNING_SOURCE': source, 'GITHUB_STEP_SUMMARY': str(summary)}
                result = subprocess.run(['bash', '-e', '-o', 'pipefail', '-c', script], cwd=directory,
                                        env=env, text=True, capture_output=True)
                self.assertEqual(result.returncode == 0, expected, result.stderr)
                if expected:
                    self.assertIn(f'Kojii APK: signed ({source})', summary.read_text())
                    if source == 'generate':
                        self.assertIn('provisioned a new signing identity', summary.read_text())
                    else:
                        self.assertIn('updates an install', summary.read_text())


if __name__ == '__main__':
    unittest.main()
