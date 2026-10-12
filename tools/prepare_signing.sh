#!/usr/bin/env bash
# Choose the release signing identity for this build.
#
# Preference order:
#   1. secrets  - all three repository secrets are set (durable, operator-controlled)
#   2. cached   - a key provisioned by an earlier CI run and restored from the Actions cache
#   3. generate - no usable key exists yet; tools/generate_signing_key.sh creates one now
#
# Every build is signed: Android refuses to install an unsigned APK, and a rotating identity
# is what previously made updates impossible. No new key is ever generated here; the
# generate mode only reports that provisioning is required.
set -euo pipefail

SIGNING_DIR="${KOJII_SIGNING_DIR:?KOJII_SIGNING_DIR must point at the workspace signing directory}"
SIGNING_ENV="${KOJII_SIGNING_ENV:?KOJII_SIGNING_ENV must point at the private signing env file}"
PROVISIONED_KEYSTORE="$SIGNING_DIR/provisioned.p12"
PROVISIONED_PASS_FILE="$SIGNING_DIR/provisioned.pass"
PROVISIONED_ALIAS_FILE="$SIGNING_DIR/alias"

umask 077
mkdir -p "$SIGNING_DIR"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
    signing_output="$GITHUB_OUTPUT"
else
    signing_output=/dev/null
fi

emit_mode() {
    printf 'mode=%s\n' "$1" >> "$signing_output"
}

write_env() {
    {
        printf 'ANDROID_KEYSTORE_FILE=%q\n' "$1"
        printf 'ANDROID_KEYSTORE_PASS=%q\n' "$2"
        printf 'ANDROID_KEY_ALIAS=%q\n' "$3"
    } > "$SIGNING_ENV"
    chmod 600 "$SIGNING_ENV"
}

# Validate alias and password before spending time on native compilation. Never print secrets.
validate_identity() {
    KOJII_VALIDATE_PASS="$2" keytool -list -keystore "$1" \
        -storepass:env KOJII_VALIDATE_PASS -alias "$3" > /dev/null
}

count_set() {
    local count=0
    local value
    for value in "$@"; do
        if [ -n "$value" ]; then
            count=$((count + 1))
        fi
    done
    printf '%s' "$count"
}

secrets_set=$(count_set "${ANDROID_KEYSTORE_BASE64:-}" "${ANDROID_KEYSTORE_PASS:-}" "${ANDROID_KEY_ALIAS:-}")

if [ "$secrets_set" -eq 3 ]; then
    : "${ANDROID_KEYSTORE_FILE:?ANDROID_KEYSTORE_FILE must point at a private temporary path}"
    printf '%s' "$ANDROID_KEYSTORE_BASE64" | base64 --decode > "$ANDROID_KEYSTORE_FILE"
    chmod 600 "$ANDROID_KEYSTORE_FILE"
    if ! validate_identity "$ANDROID_KEYSTORE_FILE" "$ANDROID_KEYSTORE_PASS" "$ANDROID_KEY_ALIAS"; then
        echo "::error title=Invalid release signing key::ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASS and ANDROID_KEY_ALIAS do not describe the same usable key."
        exit 1
    fi
    write_env "$ANDROID_KEYSTORE_FILE" "$ANDROID_KEYSTORE_PASS" "$ANDROID_KEY_ALIAS"
    emit_mode secrets
    echo "Release signing identity validated from repository secrets."
    exit 0
fi

if [ "$secrets_set" -ne 0 ]; then
    echo "::error title=Incomplete signing configuration::Set all three of ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASS and ANDROID_KEY_ALIAS, or none of them."
    exit 1
fi

if [ -f "$PROVISIONED_KEYSTORE" ] && [ -f "$PROVISIONED_PASS_FILE" ] && [ -f "$PROVISIONED_ALIAS_FILE" ]; then
    provisioned_pass=$(cat "$PROVISIONED_PASS_FILE")
    provisioned_alias=$(cat "$PROVISIONED_ALIAS_FILE")
    printf '::add-mask::%s\n' "$provisioned_pass"
    if [ -n "$provisioned_pass" ] && [ -n "$provisioned_alias" ] &&
        validate_identity "$PROVISIONED_KEYSTORE" "$provisioned_pass" "$provisioned_alias"; then
        write_env "$PROVISIONED_KEYSTORE" "$provisioned_pass" "$provisioned_alias"
        emit_mode cached
        echo "Release signing identity reused from the provisioned CI key."
        exit 0
    fi
fi

if [ -e "$PROVISIONED_KEYSTORE" ] || [ -f "$PROVISIONED_PASS_FILE" ] || [ -f "$PROVISIONED_ALIAS_FILE" ]; then
    echo "::warning title=Signing identity replaced::The provisioned CI signing key is unusable, so this run provisions a new identity. APKs signed with the previous key need a one-time uninstall/reinstall, so restore that key from the kojii-signing-key artifact or an offline backup if it matters."
    # Clear the dead key so the provisioning step is allowed to write a fresh one.
    rm -f "$PROVISIONED_KEYSTORE" "$PROVISIONED_PASS_FILE" "$PROVISIONED_ALIAS_FILE"
fi

emit_mode generate
echo "No release signing key is configured yet; this run will provision one."
