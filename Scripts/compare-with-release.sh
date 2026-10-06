#!/bin/zsh
# Runs read-only commands with the released ascelerate (asc-swift) and the debug build (ASCKit)
# and diffs their output, to verify a command migrated to ASCKit behaves the same.
#
#   Scripts/compare-with-release.sh "apps list --json" "apps info qrafter --json" ...
#
# Timestamps are masked and runs of spaces collapsed (a corrected date can change a table's
# column widths): asc-swift drops the UTC offset Apple sends (2026-09-02T12:36:17-07:00
# decodes as 12:36Z), so the released binary prints every date 7-8 hours early; ASCKit is right.
# Only pass read-only commands: both binaries run each command against App Store Connect.
set -u
cd "$(dirname "$0")/.."
OLD=${OLD:-/opt/homebrew/bin/ascelerate}
NEW=${NEW:-.build/debug/ascelerate}
OUT=$(mktemp -d)

mask() {
  sed -E -e 's/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z/<date>/g' \
    -e 's/[0-9]{1,2} [A-Z][a-z]{2} [0-9]{4} at [0-9]{2}:[0-9]{2}/<date>/g' \
    -e 's/ +$//' -e 's/  +/  /g'
}

failed=0
for command in "$@"; do
  args=(${(z)command})
  $OLD $args 2>&1 | mask > $OUT/old; old=${pipestatus[1]}
  $NEW $args 2>&1 | mask > $OUT/new; new=${pipestatus[1]}
  if [[ $old == $new ]] && cmp -s $OUT/old $OUT/new; then
    echo "SAME  $command (exit $old)"
  else
    echo "DIFF  $command (exit $old vs $new)"
    diff $OUT/old $OUT/new | head -20
    failed=1
  fi
done
rm -rf $OUT
exit $failed
