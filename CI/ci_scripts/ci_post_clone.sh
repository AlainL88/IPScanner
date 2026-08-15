#!/bin/sh
#
# Xcode Cloud post-clone script.
#
# Writes GoogleService-Info.plist from a base64 secret so Crashlytics is enabled
# for official builds. When the secret is absent (fresh clone / fork without
# credentials) the build proceeds with Crashlytics simply disabled.
#
# Secret to configure in the Xcode Cloud workflow:
#   Name: GOOGLE_SERVICE_INFO_B64
#   Value: base64 of your GoogleService-Info.plist
#
# Local way to produce the value:
#   base64 -i IPScanner/GoogleService-Info.plist | tr -d '\n'
set -e

PLIST="${CI_PRIMARY_REPOSITORY_PATH}/IPScanner/GoogleService-Info.plist"

if [ -n "${GOOGLE_SERVICE_INFO_B64}" ]; then
  echo "$GOOGLE_SERVICE_INFO_B64" | base64 --decode > "$PLIST"
  echo "Crashlytics: GoogleService-Info.plist written from secret."
else
  echo "Crashlytics: GOOGLE_SERVICE_INFO_B64 not set; Crashlytics disabled for this build."
fi
