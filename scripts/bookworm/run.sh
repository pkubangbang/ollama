#!/bin/bash
# Self-contained acceptance run on a Debian 12 (bookworm) container.
#   docker run -d debian:12-slim sleep infinity      (one-time, keeps a container alive)
#   docker exec -d <ctr> bash /opt/run/run.sh        (detached — immune to client death)
#   docker exec <ctr> cat /opt/run/report.log
set -u
DEST=/opt/ollama
mkdir -p "$DEST" /opt/run
if [ ! -x "$DEST/bin/ollama" ]; then
  cp -a /opt/run/payload/bin /opt/run/payload/lib "$DEST"/
fi
sed -i 's/^ROOT=.*/ROOT=${PAYLOAD_ROOT:-/opt\/ollama}/' /opt/run/verify.sh 2>/dev/null || true
{
  echo "run started: $(date -u +%FT%TZ)"
  echo "target glibc: $(/lib/x86_64-linux-gnu/libc.so.6 | head -1)"
  bash /opt/run/verify.sh
  echo "exit=$?"
  echo "run finished: $(date -u +%FT%TZ)"
} > /opt/run/report.log 2>&1
