#!/usr/bin/env python3
"""Build bounded-size Android icons from the exact supplied SVG, never at runtime."""
import io
import sys
from pathlib import Path
from xml.etree import ElementTree as ET


def render(source: Path, res: Path):
    import cairosvg
    from PIL import Image, ImageChops

    xml = ET.fromstring(source.read_bytes())
    if xml.tag != '{http://www.w3.org/2000/svg}svg':
        raise ValueError('Expected an SVG document')
    # Do not load external images/fonts/styles/network URLs from untrusted artwork.
    for element in xml.iter():
        if element.tag.rsplit('}', 1)[-1] not in ('svg', 'g', 'path', 'rect', 'circle', 'ellipse', 'polygon', 'polyline', 'line', 'title', 'desc'):
            raise ValueError('Only self-contained geometric SVG artwork is supported')
        for key, value in element.attrib.items():
            if key.rsplit('}', 1)[-1] in ('href', 'style') or 'url(' in value.lower():
                raise ValueError('External resources and CSS are not allowed in app artwork')
    png = cairosvg.svg2png(bytestring=ET.tostring(xml), output_width=512, output_height=512)
    image = Image.open(io.BytesIO(png)).convert('RGBA')

    def save(name, bitmap):
        target = res / name
        target.parent.mkdir(parents=True, exist_ok=True)
        bitmap.save(target, optimize=True)

    # The unmasked artwork in-app; legacy references keep working via a bitmap drawable.
    save('drawable-nodpi/kojii_artwork.png', image)
    (res / 'drawable/koji_icon.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<bitmap xmlns:android="http://schemas.android.com/apk/res/android"
    android:src="@drawable/kojii_artwork" android:gravity="fill" android:filter="true" />
''')
    # Keep artwork within Android's adaptive-icon safe zone (66 / 108).
    foreground = Image.new('RGBA', (432, 432))
    foreground.alpha_composite(image.resize((264, 264), Image.Resampling.LANCZOS), (84, 84))
    save('drawable-nodpi/kojii_foreground.png', foreground)
    for dpi, size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
        save(f'mipmap-{dpi}/ic_launcher.png', image.resize((size, size), Image.Resampling.LANCZOS))
        # Notification symbols must be monochrome alpha, not a full opaque colour square.
        mono = ImageChops.multiply(image.convert('L').point(lambda value: 255 - value), image.getchannel('A'))
        symbol = Image.new('RGBA', image.size, 'white')
        symbol.putalpha(mono)
        save(f'drawable-{dpi}/ic_stat_notification_logo.png', symbol.resize((size//2, size//2), Image.Resampling.LANCZOS))
    # Derive the themed glyph from the supplied artwork, not a substitute logo.
    mono = Image.new('RGBA', (432, 432))
    symbol = Image.new('RGBA', image.size, 'white')
    symbol.putalpha(ImageChops.multiply(image.convert('L').point(lambda value: 255 - value), image.getchannel('A')))
    mono.alpha_composite(symbol.resize((264, 264), Image.Resampling.LANCZOS), (84, 84))
    save('drawable-nodpi/kojii_monochrome.png', mono)
    adaptive = '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/kojii_foreground" />
    <monochrome android:drawable="@drawable/kojii_monochrome" />
</adaptive-icon>
'''
    (res / 'mipmap-anydpi-v26/ic_launcher.xml').write_text(adaptive)
    print('Kojii launcher, notification and in-app artwork rendered from', source)


if __name__ == '__main__':
    render(Path(sys.argv[1]), Path(sys.argv[2]))
