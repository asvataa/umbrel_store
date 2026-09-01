#!/usr/bin/env bash
# Обновляет версию образа Lampac в магазине: тег + digest в docker-compose.yml
# и version в umbrel-app.yml.
#
#   ./scripts/update-lampac.sh            # последний релиз с GitHub
#   ./scripts/update-lampac.sh 1.53.0     # конкретная версия
set -euo pipefail

REPO="lampac-nextgen/lampac"
IMAGE="ghcr.io/${REPO}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$(find "$ROOT" -maxdepth 1 -type d -name '*-lampac' | head -n1)"

[ -n "$APP_DIR" ] || { echo "не найдена папка приложения *-lampac" >&2; exit 1; }

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  VERSION="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
    | sed -nE 's/.*"tag_name": *"v?([^"]+)".*/\1/p' | head -n1)"
fi
[ -n "$VERSION" ] || { echo "не удалось определить версию" >&2; exit 1; }

TOKEN="$(curl -fsSL "https://ghcr.io/token?scope=repository:${REPO}:pull&service=ghcr.io" \
  | sed -nE 's/.*"token": *"([^"]+)".*/\1/p')"
DIGEST="$(curl -fsSL -o /dev/null -D - -H "Authorization: Bearer ${TOKEN}" \
  -H 'Accept: application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json' \
  "https://ghcr.io/v2/${REPO}/manifests/${VERSION}" \
  | tr -d '\r' | sed -nE 's/^[Dd]ocker-[Cc]ontent-[Dd]igest: *(sha256:[0-9a-f]+)$/\1/p' | head -n1)"
[ -n "$DIGEST" ] || { echo "нет образа ${IMAGE}:${VERSION} в GHCR" >&2; exit 1; }

perl -0pi -e "s|\Q${IMAGE}\E:[^\@\s]+\@sha256:[0-9a-f]+|${IMAGE}:${VERSION}\@${DIGEST}|g" \
  "$APP_DIR/docker-compose.yml"
perl -0pi -e "s|^version: .*\$|version: \"${VERSION}\"|m" "$APP_DIR/umbrel-app.yml"

echo "обновлено до ${VERSION}"
echo "  ${IMAGE}:${VERSION}@${DIGEST}"
echo "не забудьте поправить releaseNotes в $(basename "$APP_DIR")/umbrel-app.yml"
