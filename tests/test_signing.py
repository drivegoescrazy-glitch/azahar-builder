import base64
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class SigningTest(unittest.TestCase):
    def test_requires_existing_key(self):
        env=os.environ.copy()
        for key in ('ANDROID_KEYSTORE_BASE64','ANDROID_KEYSTORE_PASS','ANDROID_KEY_ALIAS','ANDROID_KEYSTORE_FILE'):
            env.pop(key,None)
        r=subprocess.run(['bash','tools/prepare_signing.sh'],cwd=ROOT,env=env,text=True,capture_output=True)
        self.assertNotEqual(r.returncode,0)
        self.assertIn('ANDROID_KEYSTORE_BASE64',r.stderr)

    def test_same_key_restored_twice(self):
        self.assertIsNotNone(shutil.which('keytool'),'JDK keytool required for signing tests')
        with tempfile.TemporaryDirectory(dir=ROOT/'.work') as temporary:
            d=Path(temporary)
            env=os.environ.copy()
            # Disposable test-only identity; not a release signing key.
            env['ANDROID_KEYSTORE_PASS']='fixture-password-not-a-real-key'
            original=d/'fixture.jks'
            subprocess.run(['keytool','-genkeypair','-keystore',str(original),'-storepass:env','ANDROID_KEYSTORE_PASS',
                '-keypass:env','ANDROID_KEYSTORE_PASS','-alias','fixture','-keyalg','RSA','-validity','1',
                '-dname','CN=Disposable regression fixture'],env=env,check=True,capture_output=True)
            env['ANDROID_KEYSTORE_BASE64']=base64.b64encode(original.read_bytes()).decode()
            env['ANDROID_KEY_ALIAS']='fixture'
            for index in (1,2):
                target=d/f'restored-{index}.jks'
                env['ANDROID_KEYSTORE_FILE']=str(target)
                subprocess.run(['bash','tools/prepare_signing.sh'],cwd=ROOT,env=env,check=True,capture_output=True)
                self.assertEqual(target.read_bytes(),original.read_bytes())
                self.assertEqual(target.stat().st_mode & 0o077,0)
            env['ANDROID_KEY_ALIAS']='wrong-alias'
            r=subprocess.run(['bash','tools/prepare_signing.sh'],cwd=ROOT,env=env,capture_output=True)
            self.assertNotEqual(r.returncode,0)


if __name__=='__main__': unittest.main()
