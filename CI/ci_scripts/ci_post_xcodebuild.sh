#!/bin/sh
#
# Xcode Cloud post-xcodebuild script — dedicated dSYM upload to Crashlytics.
#
# The Crashlytics run-script build phase handles dSYM uploads for local builds.
# On Xcode Cloud the archive's dSYMs are not reliably picked up by that phase,
# so we upload them explicitly here whenever an archive exists and the plist
# was provided by ci_post_clone.sh. Runs on every build; no-ops safely otherwise.
set -e

PLIST="${CI_PRIMARY_REPOSITORY_PATH}/IPScanner/GoogleService-Info.plist"

if [ ! -f "$PLIST" ]; then
  echo "Crashlytics: plist not found, skipping dSYM upload."
  exit 0
fi

if [ -z "${CI_ARCHIVE_PATH}" ]; then
  echo "Crashlytics: no archive in this build, skipping dSYM upload."
  exit 0
fi

DSYMS="${CI_ARCHIVE_PATH}/dSYMs"
if [ ! -d "$DSYMS" ]; then
  echo "Crashlytics: no dSYMs folder found, skipping dSYM upload."
  exit 0
fi

UPLOAD_SYMBOLS="${CI_DERIVED_DATA_PATH}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/upload-symbols"
if [ ! -f "$UPLOAD_SYMBOLS" ]; then
  UPLOAD_SYMBOLS=$(find "${CI_DERIVED_DATA_PATH}/SourcePackages/checkouts" -path '*Crashlytics/upload-symbols' 2>/dev/null | head -1 || true)
fi
if [ -z "$UPLOAD_SYMBOLS" ] || [ ! -f "$UPLOAD_SYMBOLS" ]; then
  echo "Crashlytics: upload-symbols script not found, skipping dSYM upload."
  exit 0
fi

# Detect the platform from the first dSYM's Info.plist so we pass the right -p flag.
PLATFORM=ios
FIRST_DSYM=$(find "$DSYMS" -name '*.dSYM' 2>/dev/null | head -1)
if [ -n "$FIRST_DSYM" ]; then
  SUPPORTED=$(/usr/libexec/PlistBuddy -c "Print :CFBundleSupportedPlatforms" "$FIRST_DSYM/Contents/Info.plist" 2>/dev/null || true)
  case "$SUPPORTED" in
    *MacOSX*) PLATFORM=macos ;;
  esac
fi

"$UPLOAD_SYMBOLS" -gsp "$PLIST" -p "$PLATFORM" "$DSYMS"
echo "Crashlytics: dSYMs uploaded for platform ${PLATFORM}."
