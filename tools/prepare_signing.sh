#!/usr/bin/env bash
# Select an explicit unsigned build, or validate an EXISTING signing identity.
# Never generate a new identity in CI or silently discard partial signing configuration.
set -euo pipefail
if [ -z "${ANDROID_KEYSTORE_BASE64:-}${ANDROID_KEYSTORE_PASS:-}${ANDROID_KEY_ALIAS:-}" ]; then
    echo "::warning title=Unsigned APK::No signing secrets configured. Building an unsigned APK; it cannot be installed or update an existing app until signed with the original key."
    if [ -n "${GITHUB_OUTPUT:-}" ]; then
        printf 'mode=unsigned\nkeystore_file=\n' >> "$GITHUB_OUTPUT"
    fi
    exit 0
fi
: "${ANDROID_KEYSTORE_BASE64:?Set the existing signing keystore as the ANDROID_KEYSTORE_BASE64 repository secret}"
: "${ANDROID_KEYSTORE_PASS:?Set ANDROID_KEYSTORE_PASS}"
: "${ANDROID_KEY_ALIAS:?Set ANDROID_KEY_ALIAS}"
: "${ANDROID_KEYSTORE_FILE:?Set a private temporary output path}"
umask 077
printf '%s' "$ANDROID_KEYSTORE_BASE64" | base64 --decode > "$ANDROID_KEYSTORE_FILE"
# Validate alias/password before spending time on native compilation. Never print key contents.
keytool -list -keystore "$ANDROID_KEYSTORE_FILE" -storepass:env ANDROID_KEYSTORE_PASS \
  -alias "$ANDROID_KEY_ALIAS" > /dev/null
printf 'Existing release signing identity validated.\n'
if [ -n "${GITHUB_OUTPUT:-}" ]; then
    printf 'mode=signed\nkeystore_file=%s\n' "$ANDROID_KEYSTORE_FILE" >> "$GITHUB_OUTPUT"
fi
