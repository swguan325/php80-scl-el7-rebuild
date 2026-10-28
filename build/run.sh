#!/bin/bash
# Launch the EL7 build in a throwaway centos:7 container and collect the RPMs.
#
#   ./build/run.sh [output-dir]      # default: ./rpms
#
# On a non-x86_64 host (Apple Silicon, for instance) Docker will emulate amd64;
# the build then takes roughly half an hour instead of a few minutes.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$REPO_ROOT/rpms}"
NAME="php80-el7-build"

mkdir -p "$OUT"
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" --platform linux/amd64 \
  -v "$REPO_ROOT":/work:ro centos:7 sleep infinity >/dev/null

trap 'docker rm -f "$NAME" >/dev/null 2>&1 || true' EXIT

docker exec "$NAME" bash /work/build/build.sh

docker cp "$NAME:/root/rpmbuild/RPMS/x86_64/." "$OUT/"
( cd "$OUT" && sha256sum ./*.rpm > SHA256SUMS )

echo
echo "RPMs written to $OUT"
ls -1 "$OUT"/*.rpm | wc -l | xargs echo "package count:"
