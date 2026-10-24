#!/usr/bin/env bash
# mod from https://github.com/SagerNet/sing-box/blob/stable/.github/build_openwrt_apk.sh

set -e -o pipefail

prepare_apk_root() {
  # apk mkpkg resolves owner/group names through --root/etc/{passwd,group}.
  APK_ROOT_DIR=$(mktemp -d)
  mkdir -p "$APK_ROOT_DIR/etc"
  cat > "$APK_ROOT_DIR/etc/passwd" <<EOF
root:x:$(id -u):$(id -g):root:/root:/sbin/nologin
EOF
  cat > "$APK_ROOT_DIR/etc/group" <<EOF
root:x:$(id -g):root
EOF
}

ARCHITECTURE="$1"
VERSION="$2"
BINARY_PATH="$3"
OUTPUT_PATH="$4"
SIGN_KEY="${5:-}"

if [ -z "$ARCHITECTURE" ] || [ -z "$VERSION" ] || [ -z "$BINARY_PATH" ] || [ -z "$OUTPUT_PATH" ]; then
  echo "Usage: $0 <architecture> <version> <binary_path> <output_path> [sign_key]"
  exit 1
fi

PROJECT=$(cd "$(dirname "$0")/.."; pwd)
BINARY_NAME=$(basename "$BINARY_PATH")

# Convert version to APK format:
#   9.99.9-DEV-20261024123456 -> 9.99.9_p20261024123456-r0
#   1.75.0-20261024123456    -> 1.75.0_p20261024123456-r0
#   1.13.0-beta.8            -> 1.13.0_beta8-r0
#   1.13.0-rc.3              -> 1.13.0_rc3-r0
#   1.13.0                   -> 1.13.0-r0
# A '-' is only legal in apk versions as the '-r<rev>' suffix, and a '_'
# must start a known suffix word (alpha/beta/pre/rc/cvs/svn/git/hg/p),
# so dash-separated pre-release parts are rewritten to '_p<digits>'.
APK_VERSION=$(echo "$VERSION" | sed -E 's/-([a-z]+)\.([0-9]+)/_\1\2/g')
APK_VERSION=$(echo "$APK_VERSION" | sed -E 's/-[A-Za-z][A-Za-z0-9.]*-([0-9]+)/_p\1/g')
APK_VERSION=$(echo "$APK_VERSION" | sed -E 's/-([0-9]+)/_p\1/g')
APK_VERSION="${APK_VERSION}-r0"

ROOT_DIR=$(mktemp -d)
prepare_apk_root
trap 'rm -rf "$ROOT_DIR" "$APK_ROOT_DIR"' EXIT

# Binary
install -Dm755 "$BINARY_PATH" "$ROOT_DIR/usr/bin/$BINARY_NAME"

# License
if [ -f "$PROJECT/LICENSE" ]; then
  install -Dm644 "$PROJECT/LICENSE" "$ROOT_DIR/usr/share/licenses/$BINARY_NAME/LICENSE"
fi

# APK metadata
PACKAGES_DIR="$ROOT_DIR/lib/apk/packages"
mkdir -p "$PACKAGES_DIR"

# .list (all files, excluding lib/apk/packages/ metadata)
(cd "$ROOT_DIR" && find . -type f -o -type l) \
  | sed 's|^\./|/|' \
  | grep -v '^/lib/apk/packages/' \
  | sort > "$PACKAGES_DIR/.list"

# Build APK
SIGN_ARGS=()
if [ -n "$SIGN_KEY" ]; then
  SIGN_ARGS+=(--sign-key "$SIGN_KEY")
fi
apk --root "$APK_ROOT_DIR" mkpkg \
  "${SIGN_ARGS[@]}" \
  --info "name:$BINARY_NAME" \
  --info "version:${APK_VERSION}" \
  --info "description:$BINARY_NAME" \
  --info "arch:${ARCHITECTURE}" \
  --info "origin:$BINARY_NAME" \
  --info "maintainer:linigit51 <linigit51@users.noreply.github.com>" \
  --info "depends:ca-bundle" \
  --files "$ROOT_DIR" \
  --output "$OUTPUT_PATH"

# Verify the signature when a signing key was used
if [ -n "$SIGN_KEY" ]; then
  PUBKEY_DIR="$(dirname "$SIGN_KEY")"
  apk verify --keys-dir "$PUBKEY_DIR" "$OUTPUT_PATH"
fi
