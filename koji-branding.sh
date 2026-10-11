#!/usr/bin/env bash
set -euo pipefail

ROOT="azahar/src/android/app/src/main"
MANIFEST="$ROOT/AndroidManifest.xml"
STRINGS="$ROOT/res/values/strings.xml"
GAME_LAYOUT="$ROOT/res/layout/card_game.xml"
GAMES_FRAGMENT="$ROOT/java/org/citra/citra_emu/fragments/GamesFragment.kt"

python3 - <<'PY'
from pathlib import Path
import re

root = Path("azahar/src/android/app/src/main")
manifest = root / "AndroidManifest.xml"
s = manifest.read_text()
s = s.replace('android:icon="@mipmap/ic_launcher"', 'android:icon="@drawable/koji_icon"')
s = s.replace('android:banner="@mipmap/ic_launcher"', 'android:banner="@drawable/koji_icon"')
s = s.replace('android:roundIcon="@mipmap/ic_launcher_round"', 'android:roundIcon="@drawable/koji_icon"')
manifest.write_text(s)

# Rebrand visible UI copy while retaining Azahar project URLs and upstream attribution.
for file in (root / "res/values").glob("strings*.xml"):
    s = file.read_text()
    s = re.sub(r'(?i)\bAzahar\b', 'Koji', s)
    s = re.sub(r'(?i)\bAzahar\'s\b', "Koji's", s)
    # Keep upstream links and project identifiers intact.
    s = s.replace('https://github.com/azahar-emu/azahar', 'https://github.com/azahar-emu/azahar')
    file.write_text(s)

icon = root / "res/drawable/koji_icon.xml"
icon.write_text("""<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="512dp" android:height="512dp" android:viewportWidth="512" android:viewportHeight="512">
    <path android:fillColor="#000000" android:pathData="M0,0h512v512h-512z"/>
    <path android:fillColor="#E85B00" android:pathData="M256,4 A252,252 0,1 1,255.9 4 Z M256,34 A222,222 0,1 0,256.1 34 Z" />
    <path android:fillColor="#FFF7E9" android:pathData="M256,34 A222,222 0,1 1,255.9 34 Z M256,48 A208,208 0,1 0,256.1 48 Z"/>
    <path android:fillColor="#E85B00" android:pathData="M247,245 C220,193 185,126 157,95 C143,80 119,85 102,101 C73,128 58,163 60,194 C63,224 93,239 126,247 C167,258 215,260 247,260 Z"/>
    <path android:fillColor="#E85B00" android:pathData="M267,245 C290,193 326,126 354,95 C368,80 392,85 409,101 C438,128 453,163 451,194 C448,224 418,239 385,247 C344,258 296,260 267,260 Z"/>
    <path android:fillColor="#E85B00" android:pathData="M244,267 C192,290 125,326 94,354 C79,368 84,392 100,409 C127,438 162,453 193,451 C223,448 238,418 246,385 C257,344 259,296 259,267 Z"/>
    <path android:fillColor="#E85B00" android:pathData="M267,267 C319,290 386,326 417,354 C432,368 427,392 411,409 C384,438 349,453 318,451 C288,448 273,418 265,385 C254,344 252,296 252,267 Z"/>
    <path android:fillColor="#E85B00" android:pathData="M245,247 C193,224 126,188 95,160 C80,146 85,122 101,105 C128,76 163,61 194,63 C224,66 239,96 247,129 C258,170 260,218 260,247 Z"/>
    <path android:fillColor="#E85B00" android:pathData="M267,247 C319,224 386,188 417,160 C432,146 427,122 411,105 C384,76 349,61 318,63 C288,66 273,96 265,129 C254,170 252,218 252,247 Z"/>
    <path android:fillColor="#E85B00" android:pathData="M256,254 L256,254"/>
</vector>
""")

# Turn the main library into a horizontal, swipeable card carousel.
fragment = root / "java/org/citra/citra_emu/fragments/GamesFragment.kt"
s = fragment.read_text()
s = s.replace("import androidx.recyclerview.widget.GridLayoutManager", "import androidx.recyclerview.widget.LinearLayoutManager")
pattern = re.compile(
    r"layoutManager = GridLayoutManager\(\s*requireContext\(\),\s*resources\.getInteger\(R\.integer\.game_grid_columns\)\s*\)",
    re.MULTILINE,
)
replacement = """layoutManager = LinearLayoutManager(
                requireContext(),
                androidx.recyclerview.widget.RecyclerView.HORIZONTAL,
                false
            )"""
s, count = pattern.subn(replacement, s, count=1)
if count != 1:
    raise SystemExit("Could not safely locate the main games grid layout; refusing to build a partial UI change.")
fragment.write_text(s)

# Give each horizontal carousel card a stable width. Keep the upstream 8dp spacing.
layout = root / "res/layout/card_game.xml"
s = layout.read_text()
s = s.replace(
    'android:layout_width="match_parent"\n    android:layout_height="wrap_content"\n    android:layout_margin="8dp"',
    'android:layout_width="220dp"\n    android:layout_height="wrap_content"\n    android:layout_margin="8dp"',
    1
)
layout.write_text(s)
PY
