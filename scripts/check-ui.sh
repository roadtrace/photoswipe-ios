#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
DEVICE="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for runtime, devices in d["devices"].items() if "iOS-18" in runtime for x in devices if "iPhone" in x["name"]))')"
xcrun simctl boot "$DEVICE" || true
xcrun simctl bootstatus "$DEVICE" -b
mkdir -p build/ui-fixtures build/ui-artifacts
cp PhotoSwipe/docs/screenshots/01-picker.png build/ui-fixtures/copy-one.png
cp PhotoSwipe/docs/screenshots/01-picker.png build/ui-fixtures/copy-two.png
cp PhotoSwipe/docs/screenshots/01-picker.png build/ui-fixtures/copy-three.png
xcrun simctl addmedia "$DEVICE" build/ui-fixtures/*.png
ARGS=(-project PhotoSwipe/PhotoSwipe.xcodeproj -scheme PhotoSwipe -configuration Debug
      -destination "platform=iOS Simulator,id=$DEVICE" -derivedDataPath build/UITests
      CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=)
xcodebuild "${ARGS[@]}" build-for-testing > build/ui-artifacts/build.log 2>&1
xcrun simctl install "$DEVICE" build/UITests/Build/Products/Debug-iphonesimulator/PhotoSwipe.app
xcrun simctl privacy "$DEVICE" grant photos com.alperen.PhotoSwipe
set +e
xcodebuild "${ARGS[@]}" test-without-building -parallel-testing-enabled NO \
  -resultBundlePath build/ui-artifacts/FlowTests.xcresult > build/ui-artifacts/test.log 2>&1
RESULT=$?
set -e
xcrun xcresulttool export attachments --path build/ui-artifacts/FlowTests.xcresult \
  --output-path build/ui-artifacts/screenshots || true
exit "$RESULT"
