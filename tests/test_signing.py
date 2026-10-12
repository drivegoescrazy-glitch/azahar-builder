import base64
import itertools
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SIGNING_KEYS = ('ANDROID_KEYSTORE_BASE64', 'ANDROID_KEYSTORE_PASS', 'ANDROID_KEY_ALIAS')


class SigningTest(unittest.TestCase):
    def environment(self):
        env = os.environ.copy()
        for key in (*SIGNING_KEYS, 'ANDROID_KEYSTORE_FILE', 'GITHUB_OUTPUT'):
            env.pop(key, None)
        return env

    def prepare(self, env):
        return subprocess.run(['bash', 'tools/prepare_signing.sh'], cwd=ROOT,
                              env=env, text=True, capture_output=True)

    def test_no_credentials_explicitly_selects_unsigned(self):
        with tempfile.TemporaryDirectory(dir=ROOT/'.work') as temporary:
            output = Path(temporary)/'outputs'
            env = self.environment()
            env['GITHUB_OUTPUT'] = str(output)
            result = self.prepare(env)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(output.read_text(), 'mode=unsigned\nkeystore_file=\n')
            self.assertIn('cannot be installed', result.stdout)

    def test_partial_credentials_never_fall_back_to_unsigned(self):
        for count in (1, 2):
            for keys in itertools.combinations(SIGNING_KEYS, count):
                with self.subTest(keys=keys), tempfile.TemporaryDirectory(dir=ROOT/'.work') as temporary:
                    env = self.environment()
                    env.update({key: 'incomplete-fixture' for key in keys})
                    output = Path(temporary)/'outputs'
                    env['GITHUB_OUTPUT'] = str(output)
                    env['ANDROID_KEYSTORE_FILE'] = str(Path(temporary)/'out.jks')
                    result = self.prepare(env)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertNotIn('mode=unsigned', output.read_text() if output.exists() else '')
                    self.assertNotIn('incomplete-fixture', result.stdout + result.stderr)

    def test_invalid_base64_is_an_error(self):
        with tempfile.TemporaryDirectory(dir=ROOT/'.work') as temporary:
            env = self.environment()
            env.update(dict(zip(SIGNING_KEYS, ('invalid!base64', 'fixture-password', 'fixture'))))
            env['ANDROID_KEYSTORE_FILE'] = str(Path(temporary)/'out.jks')
            env['GITHUB_OUTPUT'] = str(Path(temporary)/'outputs')
            result = self.prepare(env)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(Path(env['GITHUB_OUTPUT']).exists())
            self.assertNotIn('invalid!base64', result.stdout + result.stderr)

    def test_same_key_restored_twice_and_bad_credentials_fail(self):
        self.assertIsNotNone(shutil.which('keytool'), 'JDK keytool required for signing tests')
        with tempfile.TemporaryDirectory(dir=ROOT/'.work') as temporary:
            d = Path(temporary)
            env = self.environment()
            # Disposable test-only identity; not a release signing key.
            env['ANDROID_KEYSTORE_PASS'] = 'fixture-password-not-a-real-key'
            original = d/'fixture.jks'
            subprocess.run(['keytool', '-genkeypair', '-keystore', str(original), '-storepass:env', 'ANDROID_KEYSTORE_PASS',
                '-keypass:env', 'ANDROID_KEYSTORE_PASS', '-alias', 'fixture', '-keyalg', 'RSA', '-validity', '1',
                '-dname', 'CN=Disposable regression fixture'], env=env, check=True, capture_output=True)
            env['ANDROID_KEYSTORE_BASE64'] = base64.b64encode(original.read_bytes()).decode()
            env['ANDROID_KEY_ALIAS'] = 'fixture'
            for index in (1, 2):
                target = d/f'restored-{index}.jks'
                output = d/f'outputs-{index}'
                env['ANDROID_KEYSTORE_FILE'] = str(target)
                env['GITHUB_OUTPUT'] = str(output)
                result = self.prepare(env)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(target.read_bytes(), original.read_bytes())
                self.assertEqual(target.stat().st_mode & 0o077, 0)
                self.assertEqual(output.read_text(), f'mode=signed\nkeystore_file={target}\n')
            for bad_alias, bad_password in [('wrong-alias', env['ANDROID_KEYSTORE_PASS']), ('fixture', 'wrong-password')]:
                env['ANDROID_KEY_ALIAS'] = bad_alias
                env['ANDROID_KEYSTORE_PASS'] = bad_password
                output = d/f'failed-{bad_alias}'
                env['GITHUB_OUTPUT'] = str(output)
                result = self.prepare(env)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(output.exists())


if __name__ == '__main__':
    unittest.main()
