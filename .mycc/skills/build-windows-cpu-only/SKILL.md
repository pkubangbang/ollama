---
name: build-windows-cpu-only
description: >
  Reproducibly build the CPU-only / driver-free Windows ollama distribution from
  this fork on this machine. Covers the dual-toolchain setup required to build
  both the CMake/llama-server native backend (MSVC 2022 BuildTools + Ninja) and
  the Go CLI with cgo (llvm-mingw ucrt gcc/g++, because Go's cgo cannot use MSVC),
  plus the optional tray app (npm/React UI + Go GUI exe) and the Inno Setup
  installer. Use when you need to produce dist\windows-amd64\ollama.exe, the CPU
  llama-server payloads, dist\windows-ollama-app-amd64.exe, and/or
  dist\OllamaSetup.exe without any CUDA/ROCm/Vulkan/MLX driver backends.
keywords: [ollama, windows, build, cpu-only, llvm-mingw, cgo, msvc, ninja, cmake, driver-free, gcc, cross-compile, windows-amd64, app, installer, inno-setup, iscc, npm, react, ollama-setup, windowsgui, tagged, release-tag, stable, nightly, canary]
when: >
  when asked to build ollama for Windows on this machine's CPU-only / driver-free
  profile, or when the Go CLI cgo build fails with MSVC (cl D8021 / /Werror), or
  when reproducing the CPU llama-server backend with llvm-mingw, or when asked to
  build/publish the Windows installer (OllamaSetup.exe) or the tray app.
---

# Build Windows CPU-only ollama (driver-free)

CPU-only, driver-free Windows build of ollama from `C:\Proj\ollama`.
Produces `dist\windows-amd64\ollama.exe` plus CPU `llama-server` payloads under
`dist\windows-amd64\lib\ollama\`.

## Build from a TAGGED commit, not nightly/canary (stability)

**Always base a shipped build on a release tag, never on the tip of `main`
(a nightly / canary commit).** Untagged `main` tips are moving targets that may
contain unreleased or later-reverted changes, so the artifact is not reproducible
and its "what changed" story is unstable.

```powershell
# pick the newest STABLE release tag (exclude -rc/-ci/canary tags)
git fetch upstream --tags
$ver = git tag --sort=-v:refname | Where-Object { $_ -match '^v\d+\.\d+\.\d+$' } | Select-Object -First 1
# resolve that tag's commit
$commit = git rev-list -n1 $ver
git describe --tags $commit          # confirm it is exactly the tag, no "-N-g<hash>" suffix
```

- A commit that `git describe --tags` reports as `vX.Y.Z` is a release commit;
  one reported as `vX.Y.Z-N-g<hash>` (N > 0) or with no tag at all is a nightly /
  canary commit — **do not ship it**.
- Prefer the tag's own commit over a later `main` tip that merely *contains* the
  tag (`git tag --contains`): the tag commit is the frozen release point.
- Bake the tag version into the binaries (see "Commands"): `version.Version` /
  `app/version.Version` via `-ldflags -X`, and use the matching release-tag scheme
  `v<tag-version>-cpu-win64` for the fork tag.
- Caveat observed in this repo: the fork's earlier shipped base (`v0.0.0-cpu-win64`)
  was an untagged `main` commit that later became part of `v0.40.2` — a nightly base,
  exactly what this rule avoids.

## Toolchain facts (verified on this machine)

| Tool | Location / version | Used for |
|------|--------------------|----------|
| llvm-mingw ucrt 20240619 x86_64 | `C:\Users\student\llvm-mingw\llvm-mingw-20240619-ucrt-x86_64\bin` (gcc/g++ == Clang 18.1.8) | **cgo only** (Go CLI) |
| MSVC 2022 BuildTools | `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools` (cl 14.44) | CMake / llama-server |
| Ninja | scoop shim (`C:\Users\student\scoop\shims\ninja.exe`) | CMake generator |
| cmake | 4.4.4 (scoop) | configure/build |
| go | `C:\Program Files\Go\bin\go.exe` | Go CLI |

### WHY two compilers
- Go's cgo **cannot** use MSVC: `CC=cl` injects `/Werror` and fails with
  `cl : Command line error D8021 : invalid numeric argument '/Werror'`.
  `mlxrunner/xgrammar/xgrammar.go` carries a cgo directive, so the CLI always
  needs a gcc-compatible C compiler.
- CMake is driven by **MSVC + Ninja** (`ensureMsvcForNinja` enters the VS DevShell
  when `cl.exe` is not on PATH).
- Upstream CI installs llvm-mingw ucrt for the CPU preset alongside MSVC+Ninja for
  exactly this reason.

## Environment that works

```powershell
$bin = Join-Path $env:USERPROFILE 'llvm-mingw\llvm-mingw-20240619-ucrt-x86_64\bin'
$env:CC  = Join-Path $bin 'gcc.exe'
$env:CXX = Join-Path $bin 'g++.exe'
$env:CGO_ENABLED = '1'
# CMAKE_GENERATOR=Ninja (auto-detected when ninja.exe is on PATH)
```

- `CC` / `CXX` point at the llvm-mingw gcc/g++ for **both** the cpu step and the
  Go CLI step.
- `PATH` needs the ninja + cmake shims; the llvm-mingw `bin` dir does **not**
  need to be on PATH (the scripts reference the compiler by absolute path).
- `CMAKE_GENERATOR=Ninja` (auto-set by `build_windows.ps1` checkEnv when ninja is present).

## Commands

```powershell
# 1. CPU llama-server backend (installs into dist\windows-amd64)
cmake -S llama\server --preset cpu_windows --install-prefix C:\Proj\ollama\dist\windows-amd64
cmake --build build\llama-server-cpu --config Release --parallel <jobs>
cmake --install build\llama-server-cpu --component llama-server --strip

# 2. Go CLI (cgo via llvm-mingw)
go build -trimpath `
  -ldflags "-s -w -X=github.com/ollama/ollama/version.Version=$VERSION -X=github.com/ollama/ollama/server.mode=release" `
  -o dist\windows-amd64\ollama.exe .
```

Or run the pipeline with explicit named steps (skips cuda*/rocm*/vulkan/mlx):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build_windows.ps1 cpu ollama
```

`scripts/build_windows.ps1` dispatch is `$args`-driven: with no arguments it runs
the full pipeline; with arguments (e.g. `cpu ollama`) it runs only those named
functions via `& $($args[$i])`. There is no separate CPU-only wrapper script —
select the CPU steps by name on the command line.

## App + installer (optional — produces OllamaSetup.exe)

The tray app and the Inno Setup installer are SEPARATE steps (`app`, `installer`)
that the CPU-only pipeline above does **not** run. Both need npm/Node for the
React UI, and `installer` needs Inno Setup's `ISCC.exe`.

Verified facts on this machine:

| Tool | Location / version | Used for |
|------|--------------------|----------|
| node / npm | `C:\Program Files\nodejs` (node 24.16, npm 11.13) | React UI build |
| Inno Setup 6 | `C:\Users\student\AppData\Local\Programs\Inno Setup 6\ISCC.exe` (**user-scope** — see pitfall 6) | installer compile |

### Steps

```powershell
# env for cgo (both the CLI and the app are cgo builds)
$bin = Join-Path $env:USERPROFILE 'llvm-mingw\llvm-mingw-20240619-ucrt-x86_64\bin'
$env:CC  = Join-Path $bin 'gcc.exe'; $env:CXX = Join-Path $bin 'g++.exe'; $env:CGO_ENABLED = '1'
$env:VERSION = '0.40.3'      # baked into version.Version AND app/version.Version

# 1. React UI  (prepareApp does: npm install + npm run build + go generate ./...)
Push-Location app/ui/app; npm install; npm run build; Pop-Location
go generate ./...                              # embeds the UI into the Go app

# 2. Tray app exe  (buildApp)
go build -trimpath -ldflags "-s -w -H windowsgui -X=github.com/ollama/ollama/app/version.Version=$env:VERSION" `
  -o .\dist\windows-ollama-app-amd64.exe ./app/cmd/app/

# 3. Inno Setup installer  (installer step, run from the app\ dir)
$env:PKG_VERSION = $env:VERSION
Push-Location app
& 'C:\Users\student\AppData\Local\Programs\Inno Setup 6\ISCC.exe' /DARCH=amd64 .\ollama.iss
Pop-Location
```

`app/ollama.iss` reads `PKG_VERSION` for the product version and packs (relative to
`app\`): `..\dist\windows-ollama-app-amd64.exe` → `ollama app.exe`,
`..\dist\windows-amd64\ollama.exe`, `..\dist\windows-amd64\lib\ollama\*`, and
`.\assets\app.ico`. `OutputDir` is `..\dist\`, so the result is `dist\OllamaSetup.exe`.

The full scripted form is `powershell -File .\scripts\build_windows.ps1 cpu ollama app installer`,
but it will fail on this machine unless pitfalls 4 and 6 are addressed — prefer the
explicit commands above.

## Pitfalls

1. **Stale CMakeCache / generator mismatch.** If `build\llama-server-cpu` was ever
   configured with a different generator (e.g. `MinGW Makefiles`), reconfiguring
   with Ninja fails deep inside FetchContent:
   `CMake Error: generator Ninja does not match the generator used previously:
   MinGW Makefiles` at `_deps\llama_cpp-subbuild`. **Fix:** delete
   `build\llama-server-cpu` (the whole tree, including `_deps\llama_cpp-subbuild`)
   before reconfiguring.
2. **`C:\Program Files` is NOT user-writable.** Extracting llvm-mingw there fails
   with `Access to the path ... is denied` (needs UAC). Install to a user path
   (`%USERPROFILE%\llvm-mingw`) and wire it via `CC`/`CXX` instead.
3. **cgo vs MSVC.** See "WHY two compilers" above — never set `CC=cl` for the CLI.
4. **Auto-discovery gap (llvm-mingw).** `findWindowsCPUCompiler` searches only
   `$env:ProgramFiles\llvm-mingw-*-x86_64*\bin`,
   `$env:LOCALAPPDATA\...\MartinStorsjo.LLVM-MinGW\...\bin`, and
   `C:\msys64\{clang64,ucrt64}\bin`. It does **NOT** find
   `C:\Users\student\llvm-mingw`, so set `CC`/`CXX` explicitly (or patch the search
   list) — otherwise the cpu step warns "compiler not found" and skips the variants
   unsupported by MSVC.
5. **The script exits on the first failing step, so later steps never run.**
   `build_windows.ps1 cpu ollama app installer` stops at the `ollama` step with
   `cgo: C compiler "gcc" not found` (pitfall 4) and exits **1** — `app` and
   `installer` are never reached, and neither the app exe nor the installer is
   produced. The `cpu` step has usually already succeeded and installed the backend
   by then. **Fix:** run the `cpu` step via the script (or it may already be done),
   then build the CLI/app/installer with the explicit commands above.
6. **Auto-discovery gap (Inno Setup, user-scope).** `checkEnv` resolves the
   compiler with `get-item "C:\Program Files*\Inno Setup*\"` and then
   **unconditionally** assigns `$script:INNO_SETUP_DIR`, ignoring any pre-set
   `$env:INNO_SETUP_DIR`. Inno Setup 6 installed per-user lives at
   `%LOCALAPPDATA%\Programs\Inno Setup 6\` (here
   `C:\Users\student\AppData\Local\Programs\Inno Setup 6\`), which the glob does
   **not** match, so `$script:INNO_SETUP_DIR` stays `$null` and the `installer` step
   aborts with "missing Inno Setup installation directory". **Fix:** invoke
   `ISCC.exe` from the user-scope path directly (see the App + installer section),
   or patch `checkEnv` to also glob `$env:LOCALAPPDATA\Programs\Inno Setup*` and to
   only overwrite `$script:INNO_SETUP_DIR` when the glob actually matches.
