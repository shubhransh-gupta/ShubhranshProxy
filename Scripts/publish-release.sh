#!/usr/bin/env bash
# Build a Release DMG and publish it to GitHub Releases.
# Usage: ./Scripts/publish-release.sh [tag] [release notes]
# Example: ./Scripts/publish-release.sh v1.0.0 "First public release"

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAG="${1:-}"
NOTES="${2:-Release ${TAG}}"

if [[ -z "$TAG" ]]; then
  echo "Usage: $0 <tag> [release notes]" >&2
  echo "Example: $0 v1.0.0 \"First public release\"" >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: GitHub CLI (gh) is required. Install from https://cli.github.com/" >&2
  exit 1
fi

echo "==> Building DMG"
"$ROOT/Scripts/build-dmg.sh"

DMG="$ROOT/build/release/ShubhranshProxy.dmg"
VERSIONED_DMG="$(find "$ROOT/build/release" -maxdepth 1 -name 'ShubhranshProxy-*.dmg' -print -quit)"

if [[ ! -f "$DMG" ]]; then
  echo "ERROR: DMG not found at $DMG" >&2
  exit 1
fi

VERSION="$(basename "$VERSIONED_DMG" .dmg | sed 's/^ShubhranshProxy-//')"
TITLE="ShubhranshProxy ${VERSION}"

echo "==> Creating GitHub Release ${TAG}"
if [[ -n "$VERSIONED_DMG" && -f "$VERSIONED_DMG" && "$VERSIONED_DMG" != "$DMG" ]]; then
  gh release create "$TAG" \
    "$DMG" \
    "$VERSIONED_DMG" \
    --title "$TITLE" \
    --notes "$NOTES"
else
  gh release create "$TAG" \
    "$DMG" \
    --title "$TITLE" \
    --notes "$NOTES"
fi

echo
echo "Done."
echo "  Release: https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/releases/tag/${TAG}"
echo "  Download: https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/releases/latest/download/ShubhranshProxy.dmg"
echo
echo "Next steps:"
echo "  1. Push web/ to your public ShubhranshProxy-downloads repo for GitHub Pages"
echo "  2. Push to main — GitHub Pages will deploy web/ automatically"
echo "  3. Verify the download button on your Pages site"
