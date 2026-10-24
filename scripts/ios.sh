#!/usr/bin/env bash
set -euo pipefail

if [[ $(uname -s) != Darwin ]]; then
  echo 'The iPhone app requires macOS and Xcode. Swift core tests can run on Linux.' >&2
  exit 1
fi

action=${1:-open}
shift || true
xcodegen generate --spec apps/ios/project.yml --project apps/ios

case "$action" in
  project) ;;
  open) open apps/ios/Face2Face.xcodeproj ;;
  build)
    exec /usr/bin/xcodebuild \
      -project apps/ios/Face2Face.xcodeproj \
      -scheme Face2Face \
      -configuration Debug \
      -sdk iphonesimulator \
      -destination 'generic/platform=iOS Simulator' \
      CODE_SIGNING_ALLOWED=NO build "$@"
    ;;
  *) echo "Unknown iOS action: $action" >&2; exit 1 ;;
esac
