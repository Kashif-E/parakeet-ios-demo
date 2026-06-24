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
echo "OK -> project generated, queue debugging disabled in scheme"
