#!/usr/bin/env bash
# Regenerate HAWKER.xcodeproj from project.yml.
#
# The .xcodeproj is derived and gitignored, so it must be regenerated before an
# archive: archiving a stale one is a quiet way to ship yesterday's configuration.
#
# APPLE_TEAM_ID is expanded into project.yml and is never committed, because this
# repository is public.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -z "${APPLE_TEAM_ID:-}" ]; then
    CREDS="$HOME/.claude/skills/marcs-vibe-coding/credentials.env"
    if [ -f "$CREDS" ]; then
        set -a; . "$CREDS"; set +a
    fi
fi
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is not set and no credentials file was found}"

xcodegen generate --spec project.yml
