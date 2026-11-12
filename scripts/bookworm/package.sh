#!/bin/bash
# Package the built payload into the shippable layout and write MANIFEST.sha256.
#   package.sh <llama lib/ollama dir> <bin/ollama file> <out dir>
set -eu
LLAMA="${1:?lib/ollama dir}"
BIN="${2:?bin/ollama}"
OUT="${3:?out dir}"

rm -rf "$OUT"
mkdir -p "$OUT/bin" "$OUT/lib"
cp -a "$BIN" "$OUT/bin/ollama"
chmod 755 "$OUT/bin/ollama"
cp -a "$LLAMA" "$OUT/lib/ollama"

# GGML_OPENMP=OFF: nothing links libgomp/libomp, and the old payload carried
# glibc-2.38 copies of them. Keep the tree free of both.
rm -f "$OUT"/lib/ollama/libgomp.so* "$OUT"/lib/ollama/libomp.so*

# MANIFEST.sha256: "<sha256>  <size>  <path>" for every file, symlinks as links.
cd "$OUT"
: > MANIFEST.sha256
while IFS= read -r f; do
  rel="${f#./}"
  if [ -L "$f" ]; then
    printf '%s  %10s  %s -> %s\n' "-" "link" "$rel" "$(readlink "$f")" >> MANIFEST.sha256
  else
    printf '%s  %10s  %s\n' "$(sha256sum "$f" | awk '{print $1}')" "$(stat -c %s "$f")" "$rel" >> MANIFEST.sha256
  fi
done < <(find . \( -type f -o -type l \) ! -name MANIFEST.sha256 | sort)

echo "== tree =="
du -sh bin lib
echo "  bin/ollama: $(stat -c %s bin/ollama) bytes"
echo "  total files: $(find . -type f | wc -l)"
echo
echo "== MANIFEST.sha256 (head) =="
head -6 MANIFEST.sha256
echo "..."
echo "== verify against manifest (re-hash) =="
fail=0
while read -r sum size path; do
  [ "$size" = "link" ] && continue
  got=$(sha256sum "$path" | awk '{print $1}')
  [ "$got" = "$sum" ] || { echo "  MISMATCH $path"; fail=1; }
done < <(grep -v ' -> ' MANIFEST.sha256)
[ $fail -eq 0 ] && echo "  all $(grep -vc ' -> ' MANIFEST.sha256) file hashes verified"
exit $fail
