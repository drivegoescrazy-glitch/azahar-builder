"""Verify how a release signing identity is selected, reused and provisioned.

Every build must end up signed: Android cannot install an unsigned APK, and a rotating
identity is what previously made in-place updates impossible.
"""
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
TEST_PASSWORD = 'fixture-password-not-a-real-key'
TEST_ALIAS = 'fixture'


def keytool_available():
    return shutil.which('keytool') is not None


def create_fixture_key(directory, alias=TEST_ALIAS, password=TEST_PASSWORD):
    """Disposable test-only identity. Never used for a release."""
    keystore = Path(directory)/'fixture.p12'
    env = {**os.environ, 'KOJII_FIXTURE_PASS': password}
    subprocess.run([
        'keytool', '-genkeypair', '-keystore', str(keystore), '-storetype', 'PKCS12',
        '-storepass:env', 'KOJII_FIXTURE_PASS', '-keypass:env', 'KOJII_FIXTURE_PASS',
        '-alias', alias, '-keyalg', 'RSA', '-keysize', '2048', '-validity', '1',
        '-dname', 'CN=Disposable regression fixture',
    ], env=env, check=True, capture_output=True)
    return keystore


class SigningTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(dir=ROOT/'.work')
        self.addCleanup(self.temporary.cleanup)
        self.dir = Path(self.temporary.name)
        self.signing_dir = self.dir/'signing'
        self.env_file = self.dir/'signing.env'
        self.outputs = self.dir/'outputs'

    def environment(self, with_output=True):
        env = os.environ.copy()
        for key in (*SIGNING_KEYS, 'ANDROID_KEYSTORE_FILE', 'GITHUB_OUTPUT', 'KOJII_SIGNING_DIR',
                    'KOJII_SIGNING_ENV'):
            env.pop(key, None)
        env['KOJII_SIGNING_DIR'] = str(self.signing_dir)
        env['KOJII_SIGNING_ENV'] = str(self.env_file)
        if with_output:
            env['GITHUB_OUTPUT'] = str(self.outputs)
        return env

    def prepare(self, env):
        return subprocess.run(['bash', 'tools/prepare_signing.sh'], cwd=ROOT, env=env,
                              text=True, capture_output=True)

    def provision(self, env):
        return subprocess.run(['bash', 'tools/generate_signing_key.sh'], cwd=ROOT, env=env,
                              text=True, capture_output=True)

    def modes(self):
        if not self.outputs.exists():
            return []
        return [line.split('=', 1)[1] for line in self.outputs.read_text().splitlines()
                if line.startswith('mode=')]

    def sourced_identity(self):
        """Read the env file the build step sources, without echoing secrets into the test log."""
        script = 'set -a; . "$KOJII_SIGNING_ENV"; set +a; ' \
                 'printf "%s\\n" "$ANDROID_KEY_ALIAS"; ls -l "$ANDROID_KEYSTORE_FILE" >&2'
        result = subprocess.run(['bash', '-c', script], env={**os.environ, 'KOJII_SIGNING_ENV': str(self.env_file)},
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.splitlines()[0]

    def test_missing_key_requests_provisioning_instead_of_failing(self):
        result = self.prepare(self.environment())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.modes(), ['generate'])
        self.assertFalse((self.signing_dir/'provisioned.p12').exists())
        self.assertFalse(self.env_file.exists(), 'No key means no signing env file yet')

    def test_partial_credentials_never_fall_back_to_provisioning(self):
        for count in (1, 2):
            for keys in itertools.combinations(SIGNING_KEYS, count):
                with self.subTest(keys=keys):
                    shutil.rmtree(self.signing_dir, ignore_errors=True)
                    self.outputs.unlink(missing_ok=True)
                    env = self.environment()
                    env.update({key: 'incomplete-fixture' for key in keys})
                    result = self.prepare(env)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(self.modes(), [])
                    self.assertNotIn('incomplete-fixture', result.stdout + result.stderr)
                    self.assertFalse(self.env_file.exists())

    def test_invalid_base64_is_an_error(self):
        env = self.environment()
        env.update(dict(zip(SIGNING_KEYS, ('invalid!base64', TEST_PASSWORD, TEST_ALIAS))))
        env['ANDROID_KEYSTORE_FILE'] = str(self.dir/'out.p12')
        result = self.prepare(env)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.modes(), [])
        self.assertNotIn('invalid!base64', result.stdout + result.stderr)
        self.assertFalse(self.env_file.exists())

    @unittest.skipUnless(keytool_available(), 'JDK keytool required for signing tests')
    def test_complete_credentials_materialize_a_private_validated_identity(self):
        original = create_fixture_key(self.dir)
        env = self.environment()
        env['ANDROID_KEYSTORE_BASE64'] = base64.b64encode(original.read_bytes()).decode()
        env['ANDROID_KEYSTORE_PASS'] = TEST_PASSWORD
        env['ANDROID_KEY_ALIAS'] = TEST_ALIAS
        for index in (1, 2):
            materialized = self.dir/f'materialized-{index}.p12'
            env['ANDROID_KEYSTORE_FILE'] = str(materialized)
            self.outputs.unlink(missing_ok=True)
            result = self.prepare(env)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(self.modes(), ['secrets'])
            self.assertEqual(materialized.read_bytes(), original.read_bytes())
            self.assertEqual(materialized.stat().st_mode & 0o077, 0, 'Signing key must not be group/world readable')
            self.assertEqual(self.env_file.stat().st_mode & 0o077, 0, 'Signing env file must be private')
            self.assertEqual(self.sourced_identity(), TEST_ALIAS)
            self.assertNotIn(TEST_PASSWORD, result.stdout + result.stderr)

    @unittest.skipUnless(keytool_available(), 'JDK keytool required for signing tests')
    def test_wrong_alias_or_password_fails_instead_of_signing_with_a_new_key(self):
        original = create_fixture_key(self.dir)
        env = self.environment()
        env['ANDROID_KEYSTORE_BASE64'] = base64.b64encode(original.read_bytes()).decode()
        env['ANDROID_KEYSTORE_FILE'] = str(self.dir/'materialized.p12')
        for alias, password in (('wrong-alias', TEST_PASSWORD), (TEST_ALIAS, 'wrong-password')):
            self.outputs.unlink(missing_ok=True)
            env['ANDROID_KEY_ALIAS'] = alias
            env['ANDROID_KEYSTORE_PASS'] = password
            result = self.prepare(env)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(self.modes(), [])
            self.assertNotIn(password, result.stdout + result.stderr)

    @unittest.skipUnless(keytool_available(), 'JDK keytool required for signing tests')
    def test_provisioned_identity_is_reused_and_masked(self):
        env = self.environment()
        generated = self.provision(env)
        self.assertEqual(generated.returncode, 0, generated.stderr)
        keystore = self.signing_dir/'provisioned.p12'
        passphrase = (self.signing_dir/'provisioned.pass').read_text()
        second = self.provision(env)
        self.assertNotEqual(second.returncode, 0, 'Provisioning must never silently replace an existing key')

        self.outputs.unlink(missing_ok=True)
        result = self.prepare(env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.modes(), ['cached'])
        # prepare must add-mask the passphrase and never print it any other way.
        lines = result.stdout.splitlines()
        self.assertIn(f'::add-mask::{passphrase}', lines)
        self.assertNotIn(passphrase, '\n'.join(line for line in lines if not line.startswith('::add-mask::')))
        self.assertEqual(self.sourced_identity(), 'kojii')
        self.assertGreaterEqual(len(passphrase), 32)
        self.assertEqual(keystore.stat().st_mode & 0o077, 0)

    @unittest.skipUnless(keytool_available(), 'JDK keytool required for signing tests')
    def test_unusable_provisioned_key_warns_and_provisions_a_replacement(self):
        env = self.environment()
        self.signing_dir.mkdir(parents=True, exist_ok=True)
        create_fixture_key(self.dir)
        shutil.copy(self.dir/'fixture.p12', self.signing_dir/'provisioned.p12')
        (self.signing_dir/'provisioned.pass').write_text('not-the-right-password')
        (self.signing_dir/'alias').write_text(TEST_ALIAS)
        result = self.prepare(env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.modes(), ['generate'])
        self.assertIn('Signing identity replaced', result.stdout)
        self.assertFalse(self.env_file.exists())
        # The dead key was cleared, so a replacement identity can be provisioned and reused.
        replaced = self.provision(env)
        self.assertEqual(replaced.returncode, 0, replaced.stderr)
        self.outputs.unlink(missing_ok=True)
        again = self.prepare(env)
        self.assertEqual(again.returncode, 0, again.stderr)
        self.assertEqual(self.modes(), ['cached'])

    @unittest.skipUnless(keytool_available(), 'JDK keytool required for signing tests')
    def test_provisioned_key_can_actually_sign_and_verify(self):
        jarsigner = shutil.which('jarsigner')
        jar = shutil.which('jar')
        if not jarsigner or not jar:
            self.skipTest('JDK jarsigner required')
        env = self.environment()
        result = self.provision(env)
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = self.dir/'payload.txt'
        payload.write_text('Kojii signing regression fixture\n')
        archive = self.dir/'payload.jar'
        subprocess.run([jar, 'cf', str(archive), '-C', str(self.dir), payload.name], check=True, capture_output=True)
        env = {**os.environ,
               'KOJII_VALIDATE_PASS': (self.signing_dir/'provisioned.pass').read_text()}
        subprocess.run([jarsigner, '-keystore', str(self.signing_dir/'provisioned.p12'),
                        '-storepass:env', 'KOJII_VALIDATE_PASS', '-keypass:env', 'KOJII_VALIDATE_PASS',
                        str(archive), 'kojii'], env=env, check=True, capture_output=True)
        verified = subprocess.run([jarsigner, '-verify', str(archive)], text=True, capture_output=True)
        self.assertEqual(verified.returncode, 0, verified.stdout + verified.stderr)


if __name__ == '__main__':
    unittest.main()
