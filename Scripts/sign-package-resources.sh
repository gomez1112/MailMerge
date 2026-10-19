#!/bin/sh
set -eu

# SwiftPM copies these codeless bundles without signatures. Sign them before
# Xcode seals the app; export does not reliably re-sign bundles in Resources.
# Only distribution archives need this certificate, never local previews.
if [ "${ACTION:-}" != "install" ] || [ "${PLATFORM_NAME:-}" != "macosx" ]; then
    exit 0
fi

: "${RESOURCE_BUNDLE_SIGNING_IDENTITY:?Missing distribution signing identity}"
: "${TARGET_BUILD_DIR:?Missing target build directory}"
: "${UNLOCALIZED_RESOURCES_FOLDER_PATH:?Missing resources directory}"

for name in KickstartSDK_KickstartExchange KickstartSDK_KickstartSignal; do
    bundle="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/${name}.bundle"
    if [ ! -f "${bundle}/Contents/Info.plist" ]; then
        echo "error: Missing package resource bundle: ${name}.bundle" >&2
        exit 1
    fi
    /usr/bin/codesign --force --sign "${RESOURCE_BUNDLE_SIGNING_IDENTITY}" --timestamp --generate-entitlement-der "${bundle}"
    /usr/bin/codesign --verify --strict "${bundle}"
done
