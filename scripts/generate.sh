#!/usr/bin/env bash
# Generate the Xcode project, then disable queue-debugging in the scheme.
#
# Use this instead of a bare `xcodegen generate`: XcodeGen can't express the
# scheme's queueDebuggingEnabled flag, and with it left on (the default) iOS 26+/27
# crashes at launch under the debugger with
#   -[OS_dispatch_mach_msg _setContext:]: unrecognized selector
# (Xcode's queue-backtrace instrumentation vs the reworked libdispatch). Turning
# it off in the shared scheme keeps the demo launchable after every regenerate.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate

SCHEME="ParakeetDemo.xcodeproj/xcshareddata/xcschemes/ParakeetDemo.xcscheme"
if ! grep -q 'queueDebuggingEnabled = "NO"' "$SCHEME"; then
  perl -0pi -e 's/(<LaunchAction\n)/$1      queueDebuggingEnabled = "NO"\n/' "$SCHEME"
fi

# Resolve SwiftPM packages now, so the freshly-generated project opens without a
# "Missing package product 'MoonshineVoice'" error (regenerating wipes the state).
xcodebuild -resolvePackageDependencies -project ParakeetDemo.xcodeproj -scheme ParakeetDemo >/dev/null 2>&1 || \
  echo "note: package resolve skipped/failed — in Xcode use File > Packages > Resolve Package Versions"

echo "OK -> project generated, queue debugging disabled, packages resolved"
