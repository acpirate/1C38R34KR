#!/usr/bin/env bash
# Signed release APK.
#
# The keystore path, alias and password are supplied through the environment
# rather than through `export_presets.cfg` — that file is TRACKED, and a
# password committed to a repo with a remote is permanent. `export_credentials.cfg`
# is the file Godot's editor uses for this and is gitignored, but Godot 4.7.2's
# headless CLI export does NOT read it; the environment variables are what
# actually work.
#
# Secrets live under ~/.keystores, outside the repo. See the note there.
set -euo pipefail

KEYS="${HOME}/.keystores"
[ -n "${USERPROFILE:-}" ] && KEYS="${USERPROFILE}/.keystores"

KS="${KEYS}/1c38r34kr-beta.p12"
PW_FILE="${KEYS}/1c38r34kr-beta.password.txt"

if [ ! -f "$KS" ]; then
  echo "No keystore at $KS" >&2
  echo "See staging/release-signing-brief.md — this is the TEMPORARY beta key." >&2
  exit 1
fi

export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$KS"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="beta"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$(cat "$PW_FILE")"

exec "${USERPROFILE}/bin/godot.cmd" --headless --export-release "Android" \
  "${1:-build/1c38r34kr-release.apk}"
