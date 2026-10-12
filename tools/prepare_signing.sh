#!/usr/bin/env bash
# Decode an EXISTING, backed-up release key. Never generate a new identity in CI.
set -euo pipefail
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
