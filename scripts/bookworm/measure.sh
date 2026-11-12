#!/bin/bash
# Measure the GLIBC / GLIBCXX symbol ceilings of a payload directory.
#   measure.sh <payload-root>   (payload-root contains bin/ and lib/ollama/)
# Run inside a Debian 12 container:
#   docker run --rm -v "$PWD:/src" -w /src debian:12-slim \
#       bash -c 'apt-get update -qq && apt-get install -y -qq binutils >/dev/null && bash /src/dist/bookworm/measure.sh /src/dist/ollama-cpu-linux-amd64'
set -u
ROOT="${1:-/opt/ollama}"
cd "$ROOT" || { echo "no such dir: $ROOT"; exit 1; }

echo "== files =="
find bin lib -type f \( -perm -u+x -o -name '*.so*' \) | sort | sed 's/^/  /'

echo
echo "== per-file ceilings =="
printf '  %-40s %-12s %-14s\n' FILE GLIBC GLIBCXX
for f in $(find bin lib -type f \( -perm -u+x -o -name '*.so*' \) | sort); do
  [ "$(head -c4 "$f" | tail -c3)" = "ELF" ] || continue
  g=$(readelf --dyn-syms -W "$f" 2>/dev/null | awk '$8 ~ /@/ {print $8}' \
        | grep -oE 'GLIBC_[0-9.]+' | sort -uV | tail -1)
  x=$(readelf --dyn-syms -W "$f" 2>/dev/null | awk '$8 ~ /@/ {print $8}' \
        | grep -oE 'GLIBCXX_[0-9.]+' | sort -uV | tail -1)
  printf '  %-40s %-12s %-14s\n' "$f" "${g:--}" "${x:--}"
done

echo
echo "== worst case over the whole payload =="
G=$(for f in $(find bin lib -type f); do head -c4 "$f" 2>/dev/null | grep -q ELF && \
      readelf --dyn-syms -W "$f" 2>/dev/null | awk '$8 ~ /@/ {print $8}' | grep -oE 'GLIBC_[0-9.]+'; done \
    | sort -uV | tail -1)
X=$(for f in $(find bin lib -type f); do head -c4 "$f" 2>/dev/null | grep -q ELF && \
      readelf --dyn-syms -W "$f" 2>/dev/null | awk '$8 ~ /@/ {print $8}' | grep -oE 'GLIBCXX_[0-9.]+'; done \
    | sort -uV | tail -1)
echo "  highest GLIBC   = ${G:-none}   (limit 2.36)"
echo "  highest GLIBCXX = ${X:-none}   (limit 3.4.31)"
echo "  container glibc = $(/lib/x86_64-linux-gnu/libc.so.6 | head -1)"
echo "  container libstdc++ max = $(strings -a /lib/x86_64-linux-gnu/libstdc++.so.6 \
      | grep -oE 'GLIBCXX_3\.[0-9]+(\.[0-9]+)?' | sort -uV | tail -1)"
