# Kojii Android builder

Builds the Android 3DS emulator with Kojii branding and per-game controls.

## Gameplay and configuration

- The **Smooth gameplay preset** selects 1× resolution, no texture filter, normal
  speed/clock, and the performance preset. Save and restart the game. This trades
  image sharpness for lower GPU load; it does not guarantee a particular FPS.
- A compatible, title-specific patch is still required for 60 FPS. Raising the
  speed limit is not a substitute and may speed up game logic/audio.
- Per-game changes stay in `config/custom/<TITLEID>.ini`. Unchanged menu controls
  leave existing values alone. **Use global settings** explicitly clears that
  title's overrides after confirmation.
- Performance boost backs up its owned values and restores them when disabled.
  Advanced edits made while it is active are preserved.
- Library icons share one application-scoped 8 MiB memory cache instead of creating
  an image loader/cache per recycled tile. Missing/malformed icons use the fallback.

## Branding and artwork

`assets/kojii-icon.svg` contains a clean vector recreation of the supplied orange-slice
reference. It is not byte/pixel-identical to the original attachment. The build converts it
into launcher, themed, notification, splash, About and home artwork. Replace this SVG with
the original self-contained SVG if exact artwork is required.

`koji-branding.sh` preserves accessible theme colours, replaces the oversized horizontal
carousel with a responsive vertical game grid in library/search, and disables tile change
animations to avoid flashing during list updates.

Kojii is the visible name across locales. The source directory, workflow branch,
resource IDs, package/JNI identifiers, data paths, upstream URLs and copyright
credits intentionally retain compatibility with the existing project. Renaming
those mechanically can break updates, links, saves or native bindings.

## Verification

The workflow builds `assembleVanillaRelease`. Default output is arm64-v8a;
`abis=arm64-v8a,x86_64` also supports emulator builds. The workflow remains on
`koji-features-v2`; APK artifacts are named `kojii-<version>`.

Local checks (after applying `azahar-custom.patch` to a compatible source checkout):

```sh
# Install icon-test dependencies; Linux also requires libcairo2.
# JDK keytool and g++ are required by signing/native patch regression tests.
python3 -m pip install -r tools/icon-requirements.txt
python3 -m unittest discover -s tests -p 'test_*.py' -v

# JDK 17 + Kotlin compiler + the project's ini4j 0.5.4 jar required.
python3 tests/run_configuration_tests.py path/to/patched/source \
  --kotlinc path/to/kotlinc --ini4j path/to/ini4j-0.5.4.jar
```

Tests expect the patched checkout at `.work/source` (ignored by Git). Native INI-selector
tests also use its matching upstream inih source at `.work/inih` (or the initial clone at
`/tmp/pristine/externals/inih/inih`). Signing tests create only disposable fixture keys.
Configuration tests compile the actual parser/models/store using a filesystem SAF
adapter; they are not a substitute for a complete Android build or device testing.
Benchmark results for configuration lookups are not gameplay/FPS measurements.

Configuration microbenchmark (after running the configuration tests):

```sh
kotlinc -classpath .work/config-tests/tests.jar tests/ConfigurationBenchmark.kt \
  -include-runtime -d .work/config-benchmark.jar
java -cp .work/config-benchmark.jar:.work/config-tests/tests.jar ConfigurationBenchmarkKt
```

## Important: updating an existing installation

Android requires the **same package ID and signing identity**. The package ID remains
`org.azahar_emu.azahar`, intentionally unchanged by the Kojii rename. The timestamp-based
versionCode continues increasing; versionName now identifies Kojii explicitly.

Old CI jobs fell back to a fresh runner-generated **debug key**, so APKs from different
runs could not update each other. Release tasks now refuse that fallback. Configure these
repository **Actions secrets** (never paste them into chat or commit a keystore):

- `ANDROID_KEYSTORE_BASE64`: base64 of the **original** installed APK's signing keystore
- `ANDROID_KEYSTORE_PASS`: keystore/key password (the current project uses one password)
- `ANDROID_KEY_ALIAS`: that key's alias

Keep encrypted offline backups. CI decodes into `$RUNNER_TEMP/kojii-release.jks`, validates
it before compilation, and removes it afterward. The artifact includes the public signer
fingerprint; compare it with `apksigner verify --print-certs previous.apk` before updating.

**If the original private key is lost, code cannot make Android accept an in-place update.**
A newly created key only establishes a stable identity for future builds after migration.
Back up and verify user-folder saves/config/installed data before any reinstall; do not
uninstall merely because an update fails.

With **none** of the three signing secrets configured, CI builds a clearly labeled
`kojii-<version>-unsigned` artifact rather than failing before compilation. This APK is
**not installable or update-ready** until signed with the original key. Gradle requires
explicit `KOJII_UNSIGNED_RELEASE=true` for this mode; it never uses a fresh debug key.
With all three secrets configured, CI builds `kojii-<version>-signed` and verifies its signer.
Partial credentials, an invalid keystore, a wrong alias, or a bad password still fail:
those are configuration errors, not a reason to silently produce unsigned output.

## 60 FPS is not turbo

Kojii detects executable patches under `load/60fps/<TITLEID>/exefs/code.ips` or `code.bps`
(and the direct title-folder variants). Enabling uses **100% emulation speed**, never 200%.
The patch must implement timing-correct 60 FPS for the exact game, region and update revision.
No game-specific patch payload is bundled: a universal toggle cannot unlock every 30 FPS title.
Gateshark cheat text belongs in the Cheats menu, not in executable patch folders.

Normal code mods load first and a dedicated FPS patch loads last. BPS source checksums are
still enforced; incompatible combinations must fail rather than silently corrupt game code.
A valid header means a patch was found, **not** that the game reaches 60 FPS or runs correctly.

## Per-game graphics and performance

Long-press a game → **Kojii menu**. Settings are keyed by title ID, so one title can use 4×
resolution and another 1×. The renderer now reads title overrides before creating its graphics
window/backend. Integer scaling and custom/HD texture packs, preloading, and asynchronous pack
loading are additional per-game visual controls. Packs must already be installed.

Performance boost is an opt-in bundle (async shaders/presentation, hardware shaders, CPU JIT,
disk shader cache, duplicate-frame skipping, async pack loading, texture dumping off, VSync off).
It backs up/reverses its changes, does not overwrite a title's resolution, and may have visual
tradeoffs. No claim of being faster than upstream on every device/game is made without device
benchmarks. Higher-resolution packs and 4× rendering are inherently more GPU/memory intensive.

The inherited update checker now queries this builder repository rather than Azahar. It only
notifies for repository releases/tags; Actions artifacts alone do not create automatic update
notifications. The download links lead to this repository's Actions, never an upstream-signed APK.
