#!/bin/bash
# CPU ollama payload acceptance checks — runs INSIDE a Debian 12 bookworm
# container (glibc 2.36, libstdc++ GLIBCXX_3.4.30), which is the target floor.
#
#   /opt/ollama/bin/ollama  +  /opt/ollama/lib/ollama/  (siblings, as shipped)
#
# 1. every ELF loads (ldd: no "not found")
# 2. highest GLIBC symbol version over the payload  <= 2.36
# 3. highest GLIBCXX symbol version over the payload <= 3.4.30 (bookworm's max)
# 4. `ollama serve` + a real POST /api/chat returns an assistant message
set -u
ROOT=/opt/ollama
FAIL=0
ok()   { echo "  PASS  $*"; }
bad()  { echo "  FAIL  $*"; FAIL=$((FAIL + 1)); }
hdr()  { echo; echo "== $* =="; }

cd "$ROOT" || exit 1

# ---------------------------------------------------------------------------
hdr "0. layout (bin/ and lib/ must be siblings)"
ls -l bin lib/ollama | sed 's/^/  /'
[ -x bin/ollama ] || bad "bin/ollama missing or not executable"
[ -d lib/ollama ] || bad "lib/ollama missing"

# ---------------------------------------------------------------------------
hdr "1. ldd: every ELF member must resolve"
while IFS= read -r f; do
  if file -b "$f" | grep -q '^ELF'; then
    out=$(ldd "$f" 2>&1)
    if echo "$out" | grep -q 'not found'; then
      bad "unresolved deps: $f"
      echo "$out" | grep 'not found' | sed 's/^/        /'
    else
      ok "$f"
    fi
  fi
done < <(find bin lib -type f)

# ---------------------------------------------------------------------------
# Compare dotted numeric versions numerically (sort -V, not sort).
le() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$2" ]; }

ver_max() {  # $1 = symbol family (GLIBC / GLIBCXX)
  local best=""
  while IFS= read -r f; do
    file -b "$f" | grep -q '^ELF' || continue
    while IFS= read -r v; do
      [ -z "$v" ] && continue
      if [ -z "$best" ] || [ "$(printf '%s\n%s\n' "$best" "$v" | sort -V | tail -1)" = "$v" ]; then
        best="$v"
      fi
    done < <(readelf --dyn-syms -W "$f" 2>/dev/null \
               | awk '$8 ~ /@/ {print $8}' \
               | grep -oE "${1}_[0-9]+(\.[0-9]+)*" | sort -uV)
  done < <(find bin lib -type f)
  echo "${best#${1}_}"
}

IMG_GLIBC=$(/lib/x86_64-linux-gnu/libc.so.6 | head -1 | grep -oE 'version [0-9.]+' | awk '{print $2}')
IMG_CXX=$(strings -a /lib/x86_64-linux-gnu/libstdc++.so.6 \
            | grep -oE 'GLIBCXX_[0-9]+(\.[0-9]+)*' | sed 's/GLIBCXX_//' | sort -uV | tail -1)
echo "  image provides: GLIBC ${IMG_GLIBC:-?} / GLIBCXX ${IMG_CXX:-?}"

hdr "2. GLIBC symbol ceiling (<= ${IMG_GLIBC:-2.36})"
G=$(ver_max GLIBC)
echo "  highest GLIBC = ${G:-none}"
if [ -z "$G" ]; then ok "no glibc symbol versions referenced"
elif le "$G" "${IMG_GLIBC:-2.36}"; then ok "GLIBC $G <= ${IMG_GLIBC:-2.36}"
else bad "GLIBC $G > ${IMG_GLIBC:-2.36}"; fi

hdr "3. GLIBCXX symbol ceiling (<= ${IMG_CXX:-3.4.30})"
X=$(ver_max GLIBCXX)
echo "  highest GLIBCXX = ${X:-none}"
if [ -z "$X" ]; then ok "no GLIBCXX symbol versions referenced"
elif le "$X" "${IMG_CXX:-3.4.30}"; then ok "GLIBCXX $X <= ${IMG_CXX:-3.4.30}"
else bad "GLIBCXX $X > ${IMG_CXX:-3.4.30}"; fi

# ---------------------------------------------------------------------------
hdr "4. inference: ollama serve + POST /api/chat"
export OLLAMA_HOST=127.0.0.1:11434
export OLLAMA_MODELS=/tmp/ollama-models
MODEL="${OLLAMA_TEST_MODEL:-qwen2.5:1.5b}"

bin/ollama serve >/tmp/serve.log 2>&1 &
SRV=$!
UP=0
for _ in $(seq 1 60); do
  if curl -fsS http://127.0.0.1:11434/api/version >/dev/null 2>&1; then UP=1; break; fi
  sleep 1
done

echo "  ollama version: $(bin/ollama --version 2>&1 | head -1)"
if [ $UP -ne 1 ]; then
  bad "server did not come up"; tail -20 /tmp/serve.log | sed 's/^/        /'
  kill $SRV 2>/dev/null; exit 1
fi
ok "server listening"

# Device discovery must have found the CPU backend in lib/ollama.
for _ in $(seq 1 30); do grep -q 'inference compute' /tmp/serve.log && break; sleep 1; done
if grep -q 'inference compute' /tmp/serve.log; then
  ok "CPU backend discovered"
else
  bad "no CPU inference device discovered"
  grep -iE 'llama-server|error' /tmp/serve.log | tail -10 | sed 's/^/        /'
fi

if bin/ollama pull "$MODEL" >/tmp/pull.log 2>&1; then
  ok "pulled $MODEL"
  RESP=$(curl -sS -m 300 -X POST http://127.0.0.1:11434/api/chat \
    -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"reply with exactly: pong\"}],\"stream\":false,\"options\":{\"num_predict\":16}}")
  echo "  response: $(echo "$RESP" | head -c 400)"
  if echo "$RESP" | grep -q '"message"'; then
    ok "inference returned a message"
  else
    bad "inference failed"
    grep -iE 'llama-server|terminated|error' /tmp/serve.log | tail -15 | sed 's/^/        /'
  fi
  echo "$RESP" > /tmp/chat-response.json
else
  echo "  SKIP  could not pull $MODEL (offline?)"; tail -5 /tmp/pull.log | sed 's/^/        /'
fi

kill $SRV 2>/dev/null; wait $SRV 2>/dev/null

# ---------------------------------------------------------------------------
hdr "5. payload inventory"
find bin lib -type f -printf '  %10s  %p\n' | sort -k2

echo
if [ $FAIL -eq 0 ]; then echo "RESULT: PASS (all checks)"; else echo "RESULT: FAIL ($FAIL check(s))"; fi
exit $((FAIL > 0))
