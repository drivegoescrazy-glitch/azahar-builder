#!/usr/bin/env bash
# Provision a release signing identity for builds that have no repository secrets yet.
#
# The key is created inside the workspace signing directory so the workflow can cache it and
# reuse the exact same identity on later runs (a rotating identity breaks in-place updates).
# The passphrase is generated here, never printed, and registered with ::add-mask:: so it
# cannot leak into logs. Nothing is written back into the repository: .signing/ is ignored.
set -euo pipefail

SIGNING_DIR="${KOJII_SIGNING_DIR:?KOJII_SIGNING_DIR must point at the workspace signing directory}"
SIGNING_ENV="${KOJII_SIGNING_ENV:?KOJII_SIGNING_ENV must point at the private signing env file}"
ALIAS="${KOJII_SIGNING_ALIAS:-kojii}"
KEYSTORE="$SIGNING_DIR/provisioned.p12"

keytool -help > /dev/null 2>&1 || {
    echo "::error title=Missing keytool::A JDK is required to provision a release signing key."
    exit 1
}

umask 077
mkdir -p "$SIGNING_DIR"
chmod 700 "$SIGNING_DIR"

# Guard against silently rotating a live identity: prepare_signing.sh removes a key it has
# proved unusable, so an existing key here means the workflow asked for a replacement by mistake.
if [ -e "$KEYSTORE" ]; then
    echo "::error title=Refusing to replace signing key::A provisioned release signing key already exists. Refusing to rotate the identity; reuse or remove it deliberately."
    exit 1
fi

# 40 characters from the system CSPRNG; base64 alphabet so it survives every shell and IDE.
passphrase="$(head -c 48 /dev/urandom | base64 | tr -d '\n=+/' | cut -c1-40)"
[ "${#passphrase}" -ge 32 ] || {
    echo "::error title=Entropy failure::Could not generate a signing passphrase."
    exit 1
}
printf '::add-mask::%s\n' "$passphrase"

KOJII_GENERATED_PASS="$passphrase" keytool -genkeypair \
    -keystore "$KEYSTORE" \
    -storetype PKCS12 \
    -storepass:env KOJII_GENERATED_PASS \
    -keypass:env KOJII_GENERATED_PASS \
    -alias "$ALIAS" \
    -keyalg RSA \
    -keysize 4096 \
    -sigalg SHA256withRSA \
    -validity 10950 \
    -dname "CN=Kojii Release, OU=Kojii, O=Kojii, C=US"
chmod 600 "$KEYSTORE"

# Prove the identity works before the build spends time on compilation.
KOJII_VALIDATE_PASS="$passphrase" keytool -list -keystore "$KEYSTORE" \
    -storepass:env KOJII_VALIDATE_PASS -alias "$ALIAS" > /dev/null

printf '%s' "$passphrase" > "$SIGNING_DIR/provisioned.pass"
chmod 600 "$SIGNING_DIR/provisioned.pass"
printf '%s' "$ALIAS" > "$SIGNING_DIR/alias"
chmod 600 "$SIGNING_DIR/alias"
base64 -w0 "$KEYSTORE" > "$SIGNING_DIR/keystore.b64"
chmod 600 "$SIGNING_DIR/keystore.b64"

{
    printf 'ANDROID_KEYSTORE_FILE=%q\n' "$KEYSTORE"
    printf 'ANDROID_KEYSTORE_PASS=%q\n' "$passphrase"
    printf 'ANDROID_KEY_ALIAS=%q\n' "$ALIAS"
} > "$SIGNING_ENV"
chmod 600 "$SIGNING_ENV"

cat > "$SIGNING_DIR/PROMOTE-TO-SECRETS.txt" <<'PROMOTE_EOF'
Provisioned Kojii release signing identity
=========================================

This build had no signing secrets configured, so CI created a release key and signed the
APK with it. That APK is installable, and later builds reuse this same key while the Actions
cache entry `koji-provisioned-signing-v1` survives (GitHub deletes caches that go unused for
about a week, and caches are scoped to the branch that created them).

To make the identity permanent, store it as repository secrets (Settings -> Secrets and
variables -> Actions). Nothing here belongs in chat logs or in a committed file:

  ANDROID_KEYSTORE_BASE64  <- contents of keystore.b64
  ANDROID_KEYSTORE_PASS    <- contents of provisioned.pass
  ANDROID_KEY_ALIAS        <- contents of alias

Keep an encrypted offline copy of provisioned.p12 and its passphrase. Losing them means
future builds get a different identity, and Android will then refuse in-place updates.

Security note: anyone with read access to this repository can download this artifact, so a
repository secret (or a private key you generate yourself) is the stronger choice.
PROMOTE_EOF
chmod 600 "$SIGNING_DIR/PROMOTE-TO-SECRETS.txt"

fingerprint=$(KOJII_VALIDATE_PASS="$passphrase" keytool -list -v -keystore "$KEYSTORE" \
    -storepass:env KOJII_VALIDATE_PASS -alias "$ALIAS" | grep -m1 -E 'SHA256:' | sed 's/^[^:]*: *//')

echo "Provisioned a new release signing identity (alias '$ALIAS')."
echo "Signer certificate SHA-256: $fingerprint"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
        echo "### Provisioned release signing identity"
        echo
        echo "- Alias: \`$ALIAS\`"
        echo "- Certificate SHA-256: \`$fingerprint\`"
        echo "- This run's APK is signed and installable. Promote the uploaded \`kojii-signing-key\`"
        echo "  artifact to repository secrets so future builds keep the same identity."
    } >> "$GITHUB_STEP_SUMMARY"
fi
