---
name: build-windows-cpu-only
description: >
  Reproducibly build the CPU-only / driver-free Windows ollama distribution from
  this fork on this machine. Covers the dual-toolchain setup required to build
  both the CMake/llama-server native backend (MSVC 2022 BuildTools + Ninja) and
  the Go CLI with cgo (llvm-mingw ucrt gcc/g++, because Go's cgo cannot use MSVC).
  Use when you need to produce dist\windows-amd64\ollama.exe and the CPU
  llama-server payloads without any CUDA/ROCm/Vulkan/MLX driver backends.
keywords: [ollama, windows, build, cpu-only, llvm-mingw, cgo, msvc, ninja, cmake, driver-free, gcc, cross-compile, windows-amd64]
when: >
  when asked to build ollama for Windows on this machine's CPU-only / driver-free
  profile, or when the Go CLI cgo build fails with MSVC (cl D8021 / /Werror), or
  when reproducing the CPU llama-server backend with llvm-mingw.
---

# Build Windows CPU-only ollama (driver-free)

CPU-only, driver-free Windows build of ollama from `C:\Proj\ollama`.
Produces `dist\windows-amd64\ollama.exe` plus CPU `llama-server` payloads under
`dist\windows-amd64\lib\ollama\`.

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
4. **Auto-discovery gap.** `findWindowsCPUCompiler` searches only
   `$env:ProgramFiles\llvm-mingw-*-x86_64*\bin`,
   `$env:LOCALAPPDATA\...\MartinStorsjo.LLVM-MinGW\...\bin`, and
   `C:\msys64\{clang64,ucrt64}\bin`. It does **NOT** find
   `C:\Users\student\llvm-mingw`, so set `CC`/`CXX` explicitly (or patch the search
   list) — otherwise the cpu step warns "compiler not found" and skips the variants
   unsupported by MSVC.
