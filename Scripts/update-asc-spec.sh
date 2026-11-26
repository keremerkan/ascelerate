#!/bin/zsh
# Keeps ASCKit's generated client (Sources/ASCKit/Generated) in step with Apple's App Store Connect
# OpenAPI spec and the paths listed in Sources/ASCKit/openapi-generator-config.yaml.
#
#   Scripts/update-asc-spec.sh --check       # Is Apple's spec newer than ours? (exit 1 when it is, 2 when it couldn't be read)
#   Scripts/update-asc-spec.sh               # Download Apple's spec; if newer, prepare it and regenerate
#   Scripts/update-asc-spec.sh --force       # The same, also when the version is unchanged
#   Scripts/update-asc-spec.sh --regenerate  # Regenerate from the current openapi.json (after editing filter.paths)
#   Scripts/update-asc-spec.sh <file>        # Prepare a downloaded openapi.oas.json and regenerate
#
# The generator is a pinned swift-openapi-generator release, built once into .build. Its output is
# split into files of about 3,000 lines by Scripts/split-generated.swift (see there for why).
set -euo pipefail
cd "${0:A:h}/.."

GENERATOR_VERSION=1.14.0
SPEC_URL=https://developer.apple.com/sample-code/app-store-connect/app-store-connect-openapi-specification.zip
KIT=Sources/ASCKit

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Downloads Apple's spec to $work/openapi.oas.json and prints its version next to ours.
# Returns 0 when Apple's is newer, 1 when ours is current, 2 when Apple's couldn't be read. Every
# step is checked by hand: a function called in a condition (`download && …`) runs without set -e,
# so a failed curl used to read as "Up to date (Apple's: )".
download() {
  curl -fsSL -o "$work/spec.zip" "$SPEC_URL" || { print -u2 "Couldn't download Apple's spec ($SPEC_URL)."; return 2 }
  unzip -p "$work/spec.zip" openapi.oas.json > "$work/openapi.oas.json" || { print -u2 "Apple's download holds no openapi.oas.json."; return 2 }
  local ours apples
  ours=$(plutil -extract info.version raw "$KIT/openapi.json") || { print -u2 "Couldn't read our spec's version."; return 2 }
  apples=$(plutil -extract info.version raw "$work/openapi.oas.json") || { print -u2 "Couldn't read Apple's spec's version."; return 2 }
  [[ -n $apples ]] || { print -u2 "Apple's spec names no version."; return 2 }
  if [[ $ours != "$apples" && $(printf '%s\n%s\n' "$ours" "$apples" | sort -V | tail -1) == "$apples" ]]; then
    print "Apple's spec is newer: $ours → $apples"
    return 0
  fi
  print "Up to date: $ours (Apple's: $apples)"
  return 1
}

regenerate() {
  local package=.build/openapi-generator-$GENERATOR_VERSION
  if [[ ! -d $package ]]; then
    git clone --quiet --depth 1 --branch $GENERATOR_VERSION https://github.com/apple/swift-openapi-generator "$package"
  fi
  swift build -c release --package-path "$package" --product swift-openapi-generator
  local generator=$(swift build -c release --package-path "$package" --show-bin-path)/swift-openapi-generator
  "$generator" generate --config "$KIT/openapi-generator-config.yaml" --output-directory "$work/generated" "$KIT/openapi.json"
  swift Scripts/split-generated.swift "$work/generated" "$KIT/Generated"
}

case "${1:-}" in
  --check)
    download && result=0 || result=$?
    case $result in
      0) exit 1 ;;
      1) exit 0 ;;
      *) exit 2 ;;
    esac
    ;;
  --regenerate)
    regenerate
    ;;
  ""|--force)
    download && result=0 || result=$?
    (( result == 2 )) && exit 2
    if (( result == 0 )) || [[ ${1:-} == --force ]]; then
      swift Scripts/prepare-asc-spec.swift "$work/openapi.oas.json"
      regenerate
    fi
    ;;
  -*)
    print -u2 "Unknown option: $1"
    exit 2
    ;;
  *)
    swift Scripts/prepare-asc-spec.swift "$1"
    regenerate
    ;;
esac
