#!/bin/bash
# Assemble the shippable payload tree from the freshly built stages and measure
# its ABI ceilings. Runs inside debian:12-slim (glibc 2.36 / libstdc++ 3.4.30).
#   $1 = dir with llama-server stage root (contains lib/ollama)
#   $2 = dir with go stage root (contains bin/ollama)
#   $3 = output payload dir
set -u
LLAMA="${1:?llama root}"
GO="${2:?go root}"
OUT="${3:?out dir}"

rm -rf "$OUT"
mkdir -p "$OUT/bin" "$OUT/lib"
cp -a "$LLAMA/lib/ollama" "$OUT/lib/ollama"
cp -a "$GO/bin/ollama" "$OUT/bin/ollama"
cp -a "$GO/lib/ollama/GO_LICENSE" "$OUT/lib/ollama/GO_LICENSE"

# GGML_OPENMP=OFF: nothing links libgomp, and the old payload's copies are
# glibc-2.38. Keep the tree free of them.
rm -f "$OUT"/lib/ollama/libgomp.so* "$OUT"/lib/ollama/libomp.so*

echo "== layout =="
find "$OUT" -maxdepth 3 -mindepth 1 -printf '%y %10s  %P\n' | sort -k3

echo
echo "== glibc/glibcxx ceilings (per ELF) =="
fail=0
for f in $(find "$OUT/bin" "$OUT/lib" -type f); do
  head -c4 "$f" | grep -q ELF || continue
  g=$(readelf --dyn-syms -W "$f" 2>/dev/null | awk '$8 ~ /@/ {print $8}' | grep -oE 'GLIBC_[0-9.]+' | sort -uV | tail -1)
  x=$(readelf --dyn-syms -W "$f" 2>/dev/null | awk '$8 ~ /@/ {print $8}' | grep -oE 'GLIBCXX_[0-9.]+' | sort -uV | tail -1)
  printf '  %-42s %-11s %-14s\n' "${f#$OUT/}" "${g:--}" "${x:--}"
  for v in ${g:+$g} ${x:+$x}; do
    case "$v" in
      GLIBC_*) [ "$(printf '%s\n2.36\n' "${v#GLIBC_}" | sort -V | tail -1)" = "${v#GLIBC_}" ] && fail=1 ;;
      GLIBCXX_*) [ "$(printf '%s\n3.4.30\n' "${v#GLIBCXX_}" | sort -V | tail -1)" = "${v#GLIBCXX_}" ] && fail=1 ;;
    esac
  done
done
echo
echo "  image: $(/lib/x86_64-linux-gnu/libc.so.6 | head -1)"
echo "  image libstdc++ max: $(strings -a /lib/x86_64-linux-gnu/libstdc++.so.6 | grep -oE 'GLIBCXX_3\.[0-9]+(\.[0-9]+)?' | sort -uV | tail -1)"
if [ $fail -eq 0 ]; then echo "  RESULT: within GLIBC 2.36 / GLIBCXX 3.4.30"; else echo "  RESULT: OVER THE CEILING"; fi
exit $fail
