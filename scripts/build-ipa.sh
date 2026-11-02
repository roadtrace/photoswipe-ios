#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "An iPhone device build requires macOS and Xcode 16 or newer. Use the GitHub Actions workflow from Windows." >&2
  exit 1
fi
command -v xcodebuild >/dev/null || { echo "Select a full Xcode installation using xcode-select." >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Each run gets its own directory: no stale app can be packaged after a failed build.
mkdir -p "$ROOT/build"
WORK="$(mktemp -d "$ROOT/build/ipa.XXXXXX")"
APP="$WORK/DerivedData/Build/Products/Release-iphoneos/PhotoSwipe.app"
OUT="$WORK/artifacts"
mkdir -p "$OUT" "$WORK/package/Payload"

xcodebuild -version | tee "$OUT/xcode-version.txt"
xcodebuild \
  -project "$ROOT/PhotoSwipe/PhotoSwipe.xcodeproj" \
  -scheme PhotoSwipe \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$WORK/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  DEVELOPMENT_TEAM= \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  build 2>&1 | tee "$OUT/build.log"

python3 "$ROOT/scripts/verify-app.py" "$APP"
ditto "$APP" "$WORK/package/Payload/PhotoSwipe.app"
ditto -c -k --keepParent "$WORK/package/Payload" "$OUT/PhotoSwipe-unsigned.ipa"
unzip -t "$OUT/PhotoSwipe-unsigned.ipa"
(
  cd "$OUT"
  shasum -a 256 PhotoSwipe-unsigned.ipa > PhotoSwipe-unsigned.ipa.sha256
)
git -C "$ROOT" rev-parse HEAD > "$OUT/source-commit.txt"
git -C "$ROOT" diff --binary HEAD > "$OUT/source-changes.patch"
echo "IPA and verification records: $OUT"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "artifact_path=$OUT" >> "$GITHUB_OUTPUT"
fi
