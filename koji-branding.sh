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
s = s.replace('android:banner="@mipmap/ic_launcher"', 'android:banner="@drawable/koji_icon"')
s = s.replace('android:roundIcon="@mipmap/ic_launcher_round"', 'android:roundIcon="@mipmap/ic_launcher"')
if 'android:roundIcon=' not in s:
    s = s.replace('android:icon="@mipmap/ic_launcher"',
                  'android:icon="@mipmap/ic_launcher" android:roundIcon="@mipmap/ic_launcher"')
manifest.write_text(s)

# Rebrand every locale without changing working links, resource IDs, or attribution.
from xml.etree import ElementTree as ET

def rebrand_text(text):
    # Preserve URLs (including escaped/HTML forms) rather than inventing nonexistent Kojii URLs.
    return re.sub(r'https?://[^\s<>\"]+|\b(?:azahar|koji)\b',
                  lambda m: m[0] if m[0].startswith(('http://', 'https://')) else 'Kojii',
                  text, flags=re.IGNORECASE)

for directory in (root / "res").glob("values*"):
    for file in directory.glob("*.xml"):
        original = file.read_text()
        # Only string/plural/array contents are visible text, never resource/style names.
        tree = ET.fromstring(original)
        names = {el.get('name') for el in tree
                 if el.tag in ('string', 'plurals', 'string-array')}
        pattern = re.compile(r'(<(string|plurals|string-array)\b[^>]*name="([^"]+)"[^>]*>)(.*?)(</\2>)', re.S)
        def replace_copy(match):
            if match[3] not in names or match[3].endswith(('_link', '_url', '_id')):
                return match[0]
            return match[1] + rebrand_text(match[4]) + match[5]
        file.write_text(pattern.sub(replace_copy, original))

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

# Responsive, vertically scrollable library/search grids. Span count follows the actual
# RecyclerView width (including split screen and tablets), not whole-screen orientation.
for fragment_name, binding_name in (("GamesFragment", "gridGames"), ("SearchFragment", "gridGamesSearch")):
    fragment = root / f"java/org/citra/citra_emu/fragments/{fragment_name}.kt"
    text = fragment.read_text()
    anchor = f"        binding.{binding_name}.apply {{"
    injection = anchor + """
            addOnLayoutChangeListener { view, left, _, right, _, _, _, _, _ ->
                val available = right - left - view.paddingLeft - view.paddingRight
                val minTile = (resources.displayMetrics.density * 156).toInt().coerceAtLeast(1)
                val columns = (available / minTile).coerceIn(2, 8)
                val grid = layoutManager as? GridLayoutManager
                if (grid != null && grid.spanCount != columns) grid.spanCount = columns
            }
            itemAnimator = null
"""
    if text.count(anchor) != 1:
        raise SystemExit(f"Missing library grid anchor in {fragment_name}")
    text = text.replace(anchor, injection, 1)
    text = text.replace("resources.getInteger(R.integer.game_grid_columns)", "2", 1)
    fragment.write_text(text)

layout = root / "res/layout/card_game.xml"
text = layout.read_text().replace('android:textColor="#F5F7FA"', 'android:textColor="?attr/colorOnSurface"')
text = text.replace('TextAppearance.Material3.LabelSmall', 'TextAppearance.Material3.TitleSmall')
text = text.replace('android:padding="4dp"', 'android:padding="10dp"')
text = text.replace('app:cardBackgroundColor="@android:color/transparent"',
                    'app:cardBackgroundColor="?attr/colorSurfaceVariant"')
text = text.replace('app:strokeWidth="0dp"', 'app:strokeWidth="1dp" app:strokeColor="?attr/colorOutline"')
text = text.replace('android:maxLines="2"', 'android:maxLines="2" android:minLines="2"')
layout.write_text(text)

PY

# ---------------------------------------------------------------------------
# Kojii visual identity
#
# Azahar ships a stock Material 3 look: a blue accent, lightly rounded stock
# components and dense, flat settings lists. Kojii replaces that with its own
# design language - a warm orange accent on charcoal/paper surfaces, generous
# rounding, accent rails and "console tile" menus. Only appearance is touched:
# every screen, preference, id and navigation path stays exactly as it was, so
# behaviour is unchanged. This runs after the patch so the patch stays focused
# on features.
# ---------------------------------------------------------------------------
python3 - <<'PY'
from pathlib import Path
import re

root = Path("azahar/src/android/app/src/main")
res = root / "res"

PY_HEADER = '<?xml version="1.0" encoding="utf-8"?>\n'

def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)

# ---------------------------------------------------------------------------
# 1. Kojii colour palette
#
# Every Azahar theme keeps its own accent hue, but all surface/background
# colours are normalised to the Kojii neutrals and the default (Blue) theme
# becomes the Kojii orange accent. Resource names are untouched, so the theme
# picker and every R.color.* reference keep working.
# ---------------------------------------------------------------------------
NEUTRAL = {
    "background":          {"light": "#FFF8F2", "night": "#0B0D12"},
    "onBackground":        {"light": "#211A14", "night": "#E8E2DA"},
    "surface":             {"light": "#FFF8F2", "night": "#0F1219"},
    "onSurface":           {"light": "#211A14", "night": "#EDE7DF"},
    "surfaceVariant":      {"light": "#F2E4D8", "night": "#262A33"},
    "onSurfaceVariant":    {"light": "#52443A", "night": "#B9B2A8"},
    "outline":             {"light": "#9A8574", "night": "#6E6A62"},
    "inverseOnSurface":    {"light": "#F5EEE7", "night": "#0B0D12"},
    "inverseSurface":      {"light": "#372F28", "night": "#E8E2DA"},
}
KOJI_ACCENT = {
    "light": {
        "primary": "#A63C00",             "onPrimary": "#FFFFFF",
        "primaryContainer": "#FFD9C4",    "onPrimaryContainer": "#351000",
        "secondary": "#78594A",           "onSecondary": "#FFFFFF",
        "secondaryContainer": "#FFDBCB",  "onSecondaryContainer": "#2B160C",
        "tertiary": "#00696E",            "onTertiary": "#FFFFFF",
        "tertiaryContainer": "#9CF1F3",   "onTertiaryContainer": "#002021",
        "inversePrimary": "#FFB68C",      "surfaceTint": "#A63C00",
    },
    "night": {
        "primary": "#FFB68C",             "onPrimary": "#5A1B00",
        "primaryContainer": "#E85B00",    "onPrimaryContainer": "#FFD9C4",
        "secondary": "#E8BFA9",           "onSecondary": "#452B1E",
        "secondaryContainer": "#5E4132",  "onSecondaryContainer": "#FFDBCB",
        "tertiary": "#4FD8D8",            "onTertiary": "#003737",
        "tertiaryContainer": "#004F4F",   "onTertiaryContainer": "#A9F0F0",
        "inversePrimary": "#A63C00",      "surfaceTint": "#FFB68C",
    },
}

COLOR_RE = re.compile(
    r'(<color name="citra_([A-Za-z]+)_([a-z0-9]+)">)(#[0-9A-Fa-f]{3,8})(</color>)'
)

def apply_koji_palette(path, mode):
    text = path.read_text()

    def repl(m):
        head, role, hue, _value, tail = m.groups()
        if role in NEUTRAL:
            return head + NEUTRAL[role][mode] + tail
        if hue == "blue" and role in KOJI_ACCENT[mode]:
            return head + KOJI_ACCENT[mode][role] + tail
        return m.group(0)

    text, count = COLOR_RE.subn(repl, text)
    if count < 200:
        raise SystemExit(
            "Unexpected Kojii colour palette in {} (matched {} entries).".format(path, count)
        )
    path.write_text(text)

apply_koji_palette(res / "values/citra_colors.xml", "light")
apply_koji_palette(res / "values-night/citra_colors.xml", "night")

# ---------------------------------------------------------------------------
# 2. Kojii shape language, panels and navigation bar styles
# ---------------------------------------------------------------------------
styles = res / "values/styles.xml"
text = styles.read_text()
if "ShapeAppearance.Kojii.Medium" in text:
    raise SystemExit("Kojii styles are already present; refusing to duplicate them.")
koji_styles = '''
    <!-- Kojii shape language: generous, softly rounded surfaces. -->
    <style name="ShapeAppearance.Kojii.ExtraSmall" parent="">
        <item name="cornerFamily">rounded</item>
        <item name="cornerSize">10dp</item>
    </style>
    <style name="ShapeAppearance.Kojii.Small" parent="ShapeAppearance.Kojii.ExtraSmall">
        <item name="cornerSize">14dp</item>
    </style>
    <style name="ShapeAppearance.Kojii.Medium" parent="ShapeAppearance.Kojii.ExtraSmall">
        <item name="cornerSize">20dp</item>
    </style>
    <style name="ShapeAppearance.Kojii.Large" parent="ShapeAppearance.Kojii.ExtraSmall">
        <item name="cornerSize">28dp</item>
    </style>

    <!-- Kojii panel: the container used by every menu card. -->
    <style name="Widget.Kojii.Panel" parent="Widget.Material3.CardView.Outlined">
        <item name="cardCornerRadius">22dp</item>
        <item name="cardElevation">0dp</item>
        <item name="strokeColor">?attr/colorOutline</item>
        <item name="strokeWidth">1dp</item>
        <item name="cardBackgroundColor">?attr/colorSurfaceVariant</item>
        <item name="rippleColor">?attr/colorControlHighlight</item>
    </style>

    <!-- Kojii bottom navigation bar -->
    <style name="Widget.Kojii.NavigationBar" parent="Widget.Material3.BottomNavigationView">
        <item name="android:background">@drawable/koji_nav_background</item>
        <item name="itemIconTint">@color/koji_navigation_tint</item>
        <item name="itemTextColor">@color/koji_navigation_tint</item>
    </style>
</resources>'''
styles.write_text(text.replace("</resources>", koji_styles, 1))

# ---------------------------------------------------------------------------
# 3. Wire the Kojii shapes and navigation bar into the base theme
# ---------------------------------------------------------------------------
themes = res / "values/themes.xml"
text = themes.read_text()
anchor = '        <item name="android:windowLayoutInDisplayCutoutMode">shortEdges</item>'
if anchor not in text:
    raise SystemExit("Could not find the base Kojii theme anchor; refusing a partial restyle.")
injection = anchor + '''
        <!-- Kojii: rounded, non-flat Material 3 surfaces for every menu. -->
        <item name="shapeAppearanceSmallComponent">@style/ShapeAppearance.Kojii.Small</item>
        <item name="shapeAppearanceMediumComponent">@style/ShapeAppearance.Kojii.Medium</item>
        <item name="shapeAppearanceLargeComponent">@style/ShapeAppearance.Kojii.Large</item>
        <item name="bottomNavigationStyle">@style/Widget.Kojii.NavigationBar</item>'''
themes.write_text(text.replace(anchor, injection, 1))

# ---------------------------------------------------------------------------
# 4. Kojii drawables and colour state lists
# ---------------------------------------------------------------------------
write(res / "drawable/koji_accent_rail.xml", PY_HEADER + '''<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <solid android:color="?attr/colorPrimary" />
    <corners android:radius="3dp" />
</shape>
''')

write(res / "drawable/koji_icon_disc.xml", PY_HEADER + '''<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="oval">
    <solid android:color="?attr/colorPrimaryContainer" />
</shape>
''')

write(res / "drawable/koji_row_background.xml", PY_HEADER + '''<ripple xmlns:android="http://schemas.android.com/apk/res/android"
    android:color="?attr/colorControlHighlight">
    <item android:id="@android:id/mask">
        <shape android:shape="rectangle">
            <corners android:radius="18dp" />
            <solid android:color="#FFFFFFFF" />
        </shape>
    </item>
    <item>
        <shape android:shape="rectangle">
            <solid android:color="?attr/colorSurfaceVariant" />
            <corners android:radius="18dp" />
            <stroke android:width="1dp" android:color="?attr/colorOutline" />
        </shape>
    </item>
</ripple>
''')

write(res / "drawable/koji_screen_background.xml", PY_HEADER + '''<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <gradient
        android:angle="270"
        android:startColor="?attr/colorSurfaceVariant"
        android:endColor="?attr/colorSurface"
        android:type="linear" />
</shape>
''')

write(res / "drawable/koji_nav_background.xml", PY_HEADER + '''<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <solid android:color="?attr/colorSurfaceVariant" />
    <corners
        android:topLeftRadius="26dp"
        android:topRightRadius="26dp" />
    <stroke android:width="1dp" android:color="?attr/colorOutline" />
</shape>
''')

write(res / "drawable/koji_rail_background.xml", PY_HEADER + """<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <solid android:color="?attr/colorSurfaceVariant" />
    <corners
        android:topRightRadius="26dp"
        android:bottomRightRadius="26dp" />
    <stroke android:width="1dp" android:color="?attr/colorOutline" />
</shape>
""")

write(res / "color/koji_navigation_tint.xml", PY_HEADER + '''<selector xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:color="?attr/colorPrimary" android:state_checked="true" />
    <item android:color="?attr/colorOnSurfaceVariant" />
</selector>
''')

# ---------------------------------------------------------------------------
# 5. Kojii menus: option tiles, settings rows, headers and containers
# ---------------------------------------------------------------------------
write(res / "layout/card_home_option.xml", PY_HEADER + '''<!-- Kojii option tile: a rounded panel with an accent rail and a tinted icon disc. -->
<com.google.android.material.card.MaterialCardView xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    xmlns:tools="http://schemas.android.com/tools"
    style="@style/Widget.Kojii.Panel"
    android:id="@+id/option_card"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:layout_marginHorizontal="14dp"
    android:layout_marginBottom="14dp"
    android:clickable="true"
    android:focusable="true">

    <LinearLayout
        android:id="@+id/option_layout"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:gravity="center_vertical"
        android:orientation="horizontal"
        android:paddingVertical="16dp"
        android:paddingStart="0dp"
        android:paddingEnd="20dp">

        <View
            android:id="@+id/option_rail"
            android:layout_width="4dp"
            android:layout_height="52dp"
            android:layout_marginEnd="16dp"
            android:background="@drawable/koji_accent_rail" />

        <FrameLayout
            android:id="@+id/option_icon_disc"
            android:layout_width="48dp"
            android:layout_height="48dp"
            android:layout_marginEnd="18dp"
            android:background="@drawable/koji_icon_disc">

            <ImageView
                android:id="@+id/option_icon"
                android:layout_width="24dp"
                android:layout_height="24dp"
                android:layout_gravity="center"
                app:tint="?attr/colorOnPrimaryContainer" />
        </FrameLayout>

        <LinearLayout
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:orientation="vertical">

            <com.google.android.material.textview.MaterialTextView
                android:id="@+id/option_title"
                style="@style/TextAppearance.Material3.TitleMedium"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:textAlignment="viewStart"
                android:textColor="?attr/colorOnSurface"
                android:textStyle="bold"
                tools:text="@string/about" />

            <com.google.android.material.textview.MaterialTextView
                android:id="@+id/option_description"
                style="@style/TextAppearance.Material3.BodySmall"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:layout_marginTop="6dp"
                android:textAlignment="viewStart"
                android:textColor="?attr/colorOnSurfaceVariant"
                tools:text="@string/about_description" />

            <com.google.android.material.textview.MaterialTextView
                android:id="@+id/option_detail"
                style="@style/TextAppearance.Material3.LabelMedium"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:layout_marginTop="6dp"
                android:ellipsize="none"
                android:marqueeRepeatLimit="marquee_forever"
                android:requiresFadingEdge="horizontal"
                android:singleLine="true"
                android:textAlignment="viewStart"
                android:textColor="?attr/colorPrimary"
                android:textStyle="bold"
                android:visibility="gone"
                tools:text="/tree/primary:Games"
                tools:visibility="visible" />

        </LinearLayout>

    </LinearLayout>

</com.google.android.material.card.MaterialCardView>
''')

write(res / "layout/list_item_setting.xml", PY_HEADER + '''<RelativeLayout
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    xmlns:tools="http://schemas.android.com/tools"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:layout_marginHorizontal="12dp"
    android:layout_marginBottom="10dp"
    android:background="@drawable/koji_row_background"
    android:clickable="true"
    android:focusable="true"
    android:gravity="center_vertical"
    android:minHeight="72dp"
    android:paddingHorizontal="16dp"
    android:paddingVertical="14dp">

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal">

        <ImageView
            android:id="@+id/icon"
            android:layout_width="24dp"
            android:layout_height="24dp"
            android:layout_marginStart="0dp"
            android:layout_marginEnd="18dp"
            android:layout_gravity="center_vertical"
            android:visibility="gone"
            app:tint="?attr/colorPrimary" />

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:orientation="vertical">

            <com.google.android.material.textview.MaterialTextView
                android:id="@+id/text_setting_name"
                style="@style/TextAppearance.Material3.TitleMedium"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:textAlignment="viewStart"
                android:textColor="?attr/colorOnSurface"
                android:textSize="17sp"
                app:lineHeight="22dp"
                tools:text="Setting Name" />

            <com.google.android.material.textview.MaterialTextView
                android:id="@+id/text_setting_description"
                style="@style/TextAppearance.Material3.BodySmall"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:layout_marginTop="@dimen/spacing_small"
                android:textAlignment="viewStart"
                android:textColor="?attr/colorOnSurfaceVariant"
                tools:text="@string/app_disclaimer" />

            <com.google.android.material.textview.MaterialTextView
                android:id="@+id/text_setting_value"
                style="@style/TextAppearance.Material3.LabelMedium"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:layout_marginTop="@dimen/spacing_small"
                android:textAlignment="viewStart"
                android:textColor="?attr/colorPrimary"
                android:textSize="13sp"
                android:textStyle="bold"
                tools:text="1x" />

        </LinearLayout>

    </LinearLayout>

</RelativeLayout>
''')

write(res / "layout/list_item_setting_switch.xml", PY_HEADER + '''<RelativeLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:layout_marginHorizontal="12dp"
    android:layout_marginBottom="10dp"
    android:background="@drawable/koji_row_background"
    android:clickable="true"
    android:focusable="true"
    android:minHeight="72dp"
    android:paddingHorizontal="16dp"
    android:paddingVertical="14dp">

    <com.google.android.material.materialswitch.MaterialSwitch
        android:id="@+id/switch_widget"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_alignParentEnd="true"
        android:layout_centerVertical="true" />

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_alignParentTop="true"
        android:layout_centerVertical="true"
        android:layout_marginEnd="24dp"
        android:layout_toStartOf="@+id/switch_widget"
        android:gravity="center_vertical"
        android:orientation="vertical">

        <com.google.android.material.textview.MaterialTextView
            android:id="@+id/text_setting_name"
            style="@style/TextAppearance.Material3.TitleMedium"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:textAlignment="viewStart"
            android:textColor="?attr/colorOnSurface"
            android:textSize="17sp"
            tools:text="@string/frame_limit_enable" />

        <com.google.android.material.textview.MaterialTextView
            android:id="@+id/text_setting_description"
            style="@style/TextAppearance.Material3.BodySmall"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginTop="@dimen/spacing_small"
            android:textAlignment="viewStart"
            android:textColor="?attr/colorOnSurfaceVariant"
            tools:text="@string/frame_limit_enable_description" />

    </LinearLayout>

</RelativeLayout>
''')

write(res / "layout/list_item_settings_header.xml", PY_HEADER + '''<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:clickable="false"
    android:focusable="false"
    android:gravity="center_vertical"
    android:orientation="horizontal"
    android:paddingHorizontal="16dp"
    android:paddingVertical="18dp">

    <View
        android:layout_width="4dp"
        android:layout_height="26dp"
        android:layout_marginEnd="12dp"
        android:background="@drawable/koji_accent_rail" />

    <LinearLayout
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:layout_weight="1"
        android:orientation="vertical">

        <com.google.android.material.textview.MaterialTextView
            android:id="@+id/text_header_name"
            style="@style/TextAppearance.Material3.TitleSmall"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_gravity="start|center_vertical"
            android:textAlignment="viewStart"
            android:textColor="?attr/colorPrimary"
            android:textStyle="bold"
            tools:text="CPU Settings" />

        <com.google.android.material.textview.MaterialTextView
            android:id="@+id/text_header_description"
            style="@style/TextAppearance.Material3.BodySmall"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginTop="@dimen/spacing_small"
            android:textAlignment="viewStart"
            android:textColor="?attr/colorOnSurfaceVariant"
            tools:text="@string/app_disclaimer" />

    </LinearLayout>

</LinearLayout>
''')

# ---------------------------------------------------------------------------
# 6. Kojii screens: home options hero, main navigation bar and settings list
# ---------------------------------------------------------------------------
write(res / "layout/fragment_home_settings.xml", PY_HEADER + '''<androidx.core.widget.NestedScrollView
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:id="@+id/scroll_view_settings"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@drawable/koji_screen_background"
    android:clipToPadding="false"
    android:fadeScrollbars="false"
    android:scrollbars="vertical">

    <androidx.appcompat.widget.LinearLayoutCompat
        android:id="@+id/linear_layout_settings"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical"
        android:paddingBottom="24dp">

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:gravity="center_vertical"
            android:orientation="horizontal"
            android:paddingHorizontal="24dp"
            android:paddingVertical="28dp">

            <ImageView
                android:id="@+id/logo_image"
                android:layout_width="68dp"
                android:layout_height="68dp"
                android:contentDescription="@string/app_name"
                android:src="@drawable/koji_icon" />

            <LinearLayout
                android:layout_width="0dp"
                android:layout_height="wrap_content"
                android:layout_marginStart="18dp"
                android:layout_weight="1"
                android:orientation="vertical">

                <com.google.android.material.textview.MaterialTextView
                    style="@style/TextAppearance.Material3.HeadlineSmall"
                    android:layout_width="match_parent"
                    android:layout_height="wrap_content"
                    android:text="@string/app_name"
                    android:textColor="?attr/colorOnSurface"
                    android:textStyle="bold" />

                <com.google.android.material.textview.MaterialTextView
                    style="@style/TextAppearance.Material3.BodyMedium"
                    android:layout_width="match_parent"
                    android:layout_height="wrap_content"
                    android:layout_marginTop="2dp"
                    android:text="@string/koji_home_tagline"
                    android:textColor="?attr/colorOnSurfaceVariant" />

            </LinearLayout>

        </LinearLayout>

        <androidx.recyclerview.widget.RecyclerView
            android:id="@+id/home_settings_list"
            android:layout_width="match_parent"
            android:layout_height="wrap_content" />

    </androidx.appcompat.widget.LinearLayoutCompat>

</androidx.core.widget.NestedScrollView>
''')

write(res / "layout/fragment_settings.xml", PY_HEADER + '''<FrameLayout
    xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/list_settings_root"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@drawable/koji_screen_background">

    <androidx.recyclerview.widget.RecyclerView
        android:id="@+id/list_settings"
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:clipToPadding="false"
        android:paddingTop="12dp"
        android:paddingBottom="12dp" />

</FrameLayout>
''')

write(res / "layout/header_in_game.xml", PY_HEADER + '''<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:layout_marginTop="24dp"
    android:layout_marginStart="24dp"
    android:layout_marginEnd="24dp"
    android:gravity="center_vertical"
    android:orientation="horizontal">

    <View
        android:layout_width="4dp"
        android:layout_height="40dp"
        android:layout_marginEnd="14dp"
        android:background="@drawable/koji_accent_rail" />

    <ImageView
        android:id="@+id/game_icon"
        android:layout_width="48dp"
        android:layout_height="48dp"
        android:layout_marginEnd="16dp" />

    <com.google.android.material.textview.MaterialTextView
        android:id="@+id/text_game_title"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:textAlignment="viewStart"
        android:textAppearance="?attr/textAppearanceHeadlineSmall"
        android:textColor="?attr/colorOnSurface"
        android:textStyle="bold"
        tools:text="text_game_title" />

</LinearLayout>
''')

# ---------------------------------------------------------------------------
# 7. Activity layouts: rounded Kojii navigation bar and settings background
# ---------------------------------------------------------------------------
main_layout = res / "layout/activity_main.xml"
text = main_layout.read_text()
text, count = re.subn(
    r'(<com\.google\.android\.material\.bottomnavigation\.BottomNavigationView)',
    r'\1',
    text,
    count=1,
)
old_nav = '''        android:visibility="invisible"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintLeft_toLeftOf="parent"
        app:layout_constraintRight_toRightOf="parent"
        app:menu="@menu/menu_navigation"
        app:labelVisibilityMode="selected"'''
new_nav = '''        android:background="@drawable/koji_nav_background"
        android:visibility="invisible"
        app:itemIconTint="@color/koji_navigation_tint"
        app:itemTextColor="@color/koji_navigation_tint"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintLeft_toLeftOf="parent"
        app:layout_constraintRight_toRightOf="parent"
        app:menu="@menu/menu_navigation"
        app:labelVisibilityMode="selected"'''
if old_nav not in text:
    raise SystemExit("Could not locate the Kojii navigation bar attributes.")
text = text.replace(old_nav, new_nav, 1)
main_layout.write_text(text)

rail_layout = res / "layout-w600dp/activity_main.xml"
if rail_layout.exists():
    text = rail_layout.read_text()
    rail_anchor = '''        android:visibility="invisible"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintStart_toStartOf="parent"'''
    if rail_anchor not in text:
        raise SystemExit("Could not locate the Kojii navigation rail attributes.")
    text = text.replace(
        rail_anchor,
        '''        android:background="@drawable/koji_rail_background"
        android:visibility="invisible"
        app:itemIconTint="@color/koji_navigation_tint"
        app:itemTextColor="@color/koji_navigation_tint"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintStart_toStartOf="parent"''',
        1,
    )
    rail_layout.write_text(text)
settings_layout = res / "layout/activity_settings.xml"
text = settings_layout.read_text()
text = text.replace('android:background="?attr/colorSurface"',
                    'android:background="@drawable/koji_screen_background"')
settings_layout.write_text(text)

# ---------------------------------------------------------------------------
# 8. Kojii tagline string used by the options hero
# ---------------------------------------------------------------------------
strings = res / "values/strings.xml"
text = strings.read_text()
if "koji_home_tagline" not in text:
    text = text.replace(
        "</resources>",
        '    <string name="koji_home_tagline">Portable 3DS, re-tuned.</string>\n</resources>',
        1,
    )
    strings.write_text(text)

print("Kojii UI identity applied.")
PY

# The launcher keeps adaptive masking/themed-icon support. All legacy app logos point at the
# same source; game covers and functional menu/controller symbols remain distinct.
python3 - <<'PYICONS'
from pathlib import Path
root = Path("azahar/src/android/app/src/main")
res = root / "res"
for file in list(res.rglob("*.xml")) + [root / "AndroidManifest.xml"]:
    text = file.read_text()
    for old in ("ic_citra_full", "ic_citra", "ic_citra_monochrome"):
        text = text.replace("@drawable/" + old + '"', '@drawable/koji_icon"')
    file.write_text(text)
# Preserve the old dedicated monochrome glyph in fallback mode.
adaptive = res / "mipmap-anydpi-v26/ic_launcher.xml"
text = adaptive.read_text().replace('<monochrome android:drawable="@drawable/koji_icon"',
                                    '<monochrome android:drawable="@drawable/ic_citra_monochrome"')
adaptive.write_text(text)
PYICONS

if [ -f "assets/kojii-icon.svg" ]; then
    python3 tools/render_icons.py assets/kojii-icon.svg "$ROOT/res"
else
    echo "WARNING: assets/kojii-icon.svg is missing; using the previous icon until the artwork is supplied." >&2
fi

# Kotlin setup screens also refer to these legacy resource IDs. Replace their artwork, not the
# IDs, so bindings and navigation remain compatible.
python3 - <<'PYALIASES'
from pathlib import Path
res = Path("azahar/src/android/app/src/main/res")
for name in ("ic_citra_full", "ic_citra"):
    (res / f"drawable/{name}.xml").write_bytes((res / "drawable/koji_icon.xml").read_bytes())
PYALIASES
