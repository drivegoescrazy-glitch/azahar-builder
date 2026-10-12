import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / '.work/source'


class BrandingTest(unittest.TestCase):
    def test_visible_copy_and_links(self):
        with tempfile.TemporaryDirectory(dir=ROOT / '.work') as temporary:
            temp = Path(temporary)
            shutil.copytree(SOURCE, temp / 'azahar', symlinks=True)
            res = temp / 'azahar/src/android/app/src/main/res'
            locale = res / 'values-test'
            locale.mkdir()
            (locale/'strings.xml').write_text('''<resources>
<string name="brand_test">Koji / Azahar</string>
<string name="docs_test">Azahar help: https://github.com/azahar-emu/azahar/wiki/Example</string>
<string name="support_link">https://azahar-emu.org</string>
<string name="persistent_id">Azahar</string>
</resources>''')
            result = subprocess.run(['bash', str(ROOT/'koji-branding.sh')], cwd=temp, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('artwork is supplied', result.stderr)
            values = {e.get('name'):e.text for e in ET.parse(locale/'strings.xml').getroot()}
            self.assertEqual(values['brand_test'], 'Kojii / Kojii')
            self.assertEqual(values['docs_test'], 'Kojii help: https://github.com/azahar-emu/azahar/wiki/Example')
            self.assertEqual(values['persistent_id'], 'Azahar')
            self.assertEqual(values['support_link'], 'https://azahar-emu.org')
            app = ET.parse(res/'values/strings.xml').getroot()
            strings = {e.get('name'):e.text for e in app if e.tag=='string'}
            self.assertEqual(strings['app_name'], 'Kojii')
            self.assertEqual(strings['koji_menu_title'], 'Kojii menu')
            for file in res.rglob('*.xml'):
                ET.parse(file)
                # No upstream app logo on screens (fallback monochrome is explicit).
                if file.parent.name == 'layout':
                    self.assertNotRegex(file.read_text(), r'@drawable/ic_citra(?:_full)?"')
            for name in ('GamesFragment','SearchFragment'):
                fragment=res.parent/f'java/org/citra/citra_emu/fragments/{name}.kt'
                self.assertIn('grid.spanCount = columns',fragment.read_text())
                self.assertNotIn('RecyclerView.HORIZONTAL',fragment.read_text())
            self.assertIn('?attr/colorOnSurface',(res/'layout/card_game.xml').read_text())
            self.assertIn('@mipmap/ic_launcher', (res.parent/'AndroidManifest.xml').read_text())
            self.assertEqual((res/'drawable/ic_citra_full.xml').read_bytes(),
                             (res/'drawable/koji_icon.xml').read_bytes())

    def test_artwork_integrated_branding(self):
        with tempfile.TemporaryDirectory(dir=ROOT/'.work') as temporary:
            temp=Path(temporary)
            shutil.copytree(SOURCE, temp/'azahar', symlinks=True)
            shutil.copytree(ROOT/'tools',temp/'tools')
            (temp/'assets').mkdir()
            (temp/'assets/kojii-icon.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" width="800" height="800"><rect width="800" height="800" fill="white"/><circle cx="400" cy="400" r="250" fill="#d95702"/></svg>')
            # Resolve the test renderer dependencies before changing directories.
            environment = os.environ.copy()
            environment['PYTHONPATH'] = os.pathsep.join(str(Path(part).resolve())
                for part in environment.get('PYTHONPATH','').split(os.pathsep) if part)
            result=subprocess.run(['bash',str(ROOT/'koji-branding.sh')],cwd=temp,
                env=environment,text=True,capture_output=True)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertNotIn('WARNING',result.stderr)
            res=temp/'azahar/src/android/app/src/main/res'
            self.assertIn('kojii_artwork',(res/'drawable/ic_citra_full.xml').read_text())
            self.assertIn('kojii_foreground',(res/'mipmap-anydpi-v26/ic_launcher.xml').read_text())
            self.assertTrue((res/'drawable-nodpi/kojii_artwork.png').exists())

    def test_artwork_renderer(self):
        import sys
        sys.path.insert(0, str(ROOT/'tools'))
        from render_icons import render
        from PIL import Image
        with tempfile.TemporaryDirectory(dir=ROOT/'.work') as temporary:
            temp=Path(temporary)
            (temp/'res/drawable').mkdir(parents=True)
            (temp/'res/mipmap-anydpi-v26').mkdir()
            svg=temp/'sample.svg'
            svg.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="800" height="800"><rect width="800" height="800" fill="white"/><circle cx="400" cy="400" r="250" fill="#d95702"/></svg>')
            render(svg,temp/'res')
            with Image.open(temp/'res/drawable-nodpi/kojii_artwork.png') as icon:
                self.assertEqual(icon.size,(512,512))
            with Image.open(temp/'res/mipmap-xxxhdpi/ic_launcher.png') as icon:
                self.assertEqual(icon.size,(192,192))
            self.assertEqual(Image.open(temp/'res/drawable-nodpi/kojii_foreground.png').getbbox(),(84,84,348,348))
            self.assertGreater(Image.open(temp/'res/drawable-nodpi/kojii_monochrome.png').getchannel('A').getextrema()[1],0)
            self.assertIn('kojii_foreground', (temp/'res/mipmap-anydpi-v26/ic_launcher.xml').read_text())
            svg.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="800" height="800"><circle cx="400" cy="400" r="250" fill="#d95702"/></svg>')
            render(svg,temp/'res')
            with Image.open(temp/'res/drawable-nodpi/kojii_monochrome.png') as icon:
                self.assertEqual(icon.getpixel((84,84))[3], 0)
            svg.write_text('<svg xmlns="http://www.w3.org/2000/svg"><image href="https://example.test/x"/></svg>')
            with self.assertRaises(ValueError): render(svg,temp/'res')


if __name__ == '__main__':
    unittest.main()
