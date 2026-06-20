#!/usr/bin/env bash
# Probe how the focused-input helper behaves against the currently-focused control.
#
# Usage:
#   test_scripts/outlook-input-probe.sh diagnose
#   test_scripts/outlook-input-probe.sh ax-value
#   test_scripts/outlook-input-probe.sh unicode-events
#   test_scripts/outlook-input-probe.sh paste-keycode
#
# After you launch it you have COUNTDOWN seconds to click into the target
# (e.g. the body of an open Outlook email) so it becomes the focused element.
set -euo pipefail

HELPER="/Applications/untype.app/Contents/MacOS/untype-input-helper"
COUNTDOWN="${COUNTDOWN:-5}"
PROBE_TEXT="${PROBE_TEXT:-PROBE_INSERT_123}"

mode="${1:-diagnose}"

[[ -x "$HELPER" ]] || { echo "helper not found at $HELPER" >&2; exit 1; }

echo ">>> mode: $mode"
echo ">>> click into the target control now; probing in $COUNTDOWN s..."
for ((i=COUNTDOWN; i>0; i--)); do printf '%d ' "$i"; sleep 1; done
echo

case "$mode" in
  diagnose)
    "$HELPER" diagnose
    ;;
  auto|ax-value|unicode-events|paste-keycode)
    printf '%s' "$PROBE_TEXT" | "$HELPER" send --method "$mode"
    ;;
  *)
    echo "unknown mode: $mode (use diagnose|ax-value|unicode-events|paste-keycode)" >&2
    exit 2
    ;;
esac
echo
