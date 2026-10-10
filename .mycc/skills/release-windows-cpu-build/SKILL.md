---
name: release-windows-cpu-build
description: >
  Package and publish a GitHub release of the CPU-only Windows ollama build
  produced by the build-windows-cpu-only skill. Covers zipping the runner
  payload from dist\windows-amd64, computing SHA256 checksums, writing release
  notes, tagging, and creating/uploading the release with the gh CLI against the
  fork (pkubangbang/ollama) — including the gh default-remote pitfall and the
  proxy workaround for slow asset uploads. Use the build-windows-cpu-only skill
  FIRST to produce dist\windows-amd64, then this skill to ship it.
keywords: [ollama, release, github, gh, tag, zip, checksum, sha256, asset, upload, proxy, fork, windows-amd64, cpu-only, package, publish, notes, pkubangbang]
when: >
  when asked to prepare, create, or publish a GitHub release of the CPU-only
  Windows ollama build (the dist\windows-amd64 payload), or when a gh release
  command hits HTTP 404 pointing at ollama/ollama instead of the fork, or when a
  gh asset upload times out on a slow network and needs the local proxy.
---

# Release the Windows CPU-only ollama build on GitHub

Second half of the pipeline. Assumes `build-windows-cpu-only` has already run and
`dist\windows-amd64\ollama.exe` plus the CPU `llama-server` payloads exist under
`dist\windows-amd64\lib\ollama\`.

Fork remote: **`pkubangbang/ollama`** (origin). Upstream (`ollama/ollama`) exists
only as a read-only `upstream` remote — do NOT target it.

## Verified facts (this machine)

| Fact | Value |
|------|-------|
| gh CLI | 2.101.0, authenticated as `pkubangbang` (scopes: gist, read:org, repo, workflow) |
| Proxy for slow uploads | `http://127.0.0.1:7777` |
| Runner payload | `dist\windows-amd64\` (ollama.exe + `lib\ollama\` DLLs) |
| Installer | `dist\OllamaSetup.exe` (produced by the app step) |
| Version var | `version.Version` = `0.0.0` placeholder (no `-X` override needed for a CPU build) |

## Steps

### 1. Package the runner payload

```powershell
New-Item -ItemType Directory -Force -Path dist/release | Out-Null
Compress-Archive -Path dist/windows-amd64/* `
  -DestinationPath dist/release/ollama-windows-amd64-cpu.zip -Force
Copy-Item dist/OllamaSetup.exe dist/release/ -Force
```

The zip must contain `ollama.exe` at the root and the backend under `lib/ollama/`
(14 CPU ggml micro-arch DLLs: x64, sse42, sandybridge, ivybridge, haswell,
piledriver, cannonlake, cascadelake, cooperlake, icelake, skylakex, alderlake,
sapphirerapids, zen4, plus libllama*, ggml*.dll, llama-server.exe, licenses).

### 2. Compute checksums (quote these in the notes)

```powershell
Get-FileHash dist/release/* -Algorithm SHA256 | Select-Object Hash
```

### 3. Write release notes (dist/release/RELEASE_NOTES.md)

Must include: driver-free/CPU-only scope, asset table, install steps, build
provenance (commit, llama.cpp version from `LLAMA_CPP_VERSION`, toolchains),
SHA256 checksums, and the third-party license paths
(`lib\ollama\LLAMA_CPP_LICENSE`, `LLAMA_CPP_VENDORS_LICENSE`, `CPP_HTTPLIB_LICENSE`).
Start with a disclaimer that it is an unofficial community CPU-only build.

### 4. Tag and publish

```powershell
$env:HTTPS_PROXY="http://127.0.0.1:7777"; $env:HTTP_PROXY="http://127.0.0.1:7777"

git tag -a v<VER>-cpu-win64 <commit> -m "CPU-only Windows build (windows-amd64, driver-free)"
git push origin v<VER>-cpu-win64

# ALWAYS pass --repo: gh otherwise resolves to ollama/ollama and 404s.
gh release create v<VER>-cpu-win64 `
  dist/release/ollama-windows-amd64-cpu.zip dist/release/OllamaSetup.exe `
  --repo pkubangbang/ollama --verify-tag `
  --title "Ollama v<VER>-cpu-win64 - CPU-only Windows build (driver-free)" `
  --notes-file dist/release/RELEASE_NOTES.md
```

### 5. Verify

```powershell
gh release view v<VER>-cpu-win64 --repo pkubangbang/ollama `
  --json tagName,isDraft,isPrerelease,publishedAt,url,assets
```

Confirm `isDraft=false` and that each asset's `digest` (`sha256:...`) matches step 2.

## Pitfalls

1. **`gh` targets the wrong remote → HTTP 404.**
   `gh release create ...` without `--repo` resolves the default repo, which here
   is `ollama/ollama`, giving
   `HTTP 404: Not Found (https://api.github.com/repos/ollama/ollama/releases)`.
   **Fix:** always add `--repo pkubangbang/ollama`.
2. **Asset upload times out on a slow link.** `gh release create` creates the
   release first, then uploads; a 60 s timeout leaves a **Draft with zero assets**.
   **Fix:** set `HTTP(S)_PROXY=http://127.0.0.1:7777` and upload separately in the
   background (`bg_create`), then `gh release upload <tag> <files> --repo ... --clobber`.
3. **Partial-upload recovery.** If a release was created but assets are missing,
   do NOT re-run `gh release create` (tag already exists) — use
   `gh release upload --clobber`, then publish the draft.
4. **Publishing a draft.** `gh release edit <tag> --repo pkubangbang/ollama --draft=false --latest`.
   Note `--json` has NO `isLatest` field (valid: tagName,isDraft,isPrerelease,url,assets,body,...).
5. **No prior tags exist** in this fork, so use the `v0.0.0-cpu-win64` scheme
   (`version.Version` is the `0.0.0` placeholder).
