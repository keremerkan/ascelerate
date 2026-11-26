#!/bin/zsh
# Runs read-only commands with the released ascelerate (OLD, default the Homebrew one) and the
# debug build (NEW) and diffs their output, to check a change left a command's output as it was
# (a refactor, a move into AscelerateCore).
#
#   Scripts/compare-with-release.sh "apps list --json" "apps info myapp --json" ...
#
# Timestamps are masked and runs of spaces collapsed (a date can change a table's column widths;
# releases before 0.22.0, on asc-swift, also printed dates without their UTC offset).
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
