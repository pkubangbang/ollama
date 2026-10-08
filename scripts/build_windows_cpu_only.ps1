#!powershell
#
# CPU-only Windows build.
#
# Builds a driver-free, CPU-only Ollama distribution: the CPU (and, where the
# cross toolchain is available, ARM64) llama-server backends plus the Go CLI
# and app. The GPU/driver backends are intentionally excluded so the resulting
# package carries no CUDA / ROCm / Vulkan / MLX payloads.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\scripts\build_windows_cpu_only.ps1
#   powershell -ExecutionPolicy Bypass -File .\scripts\build_windows_cpu_only.ps1 cpu ollama
#   powershell -ExecutionPolicy Bypass -File .\scripts\build_windows_cpu_only.ps1 zip
#
# Pass one or more step names as arguments to run only those steps. With no
# arguments the default CPU-only pipeline runs (see the dispatch at the bottom).
#
# Steps that are ALWAYS excluded here (driver/GPU backends):
#   cuda11, cuda12, cuda13, cuda13Arm64*, rocm6, rocm7, vulkan, mlxCuda13
#
# This script mirrors scripts/build_windows.ps1 so the two stay easy to compare:
# it sources the same helper functions and only changes which steps run by
# default.

$ErrorActionPreference = "Continue"

# Reuse the canonical Windows build implementation. Dot-sourcing defines all the
# build steps (cpu, ollama, zip, ...) and runs its top-level checkEnv, but the
# MYCC_BUILD_NO_DISPATCH guard prevents build_windows.ps1's own full-build
# dispatch from firing.
$env:MYCC_BUILD_NO_DISPATCH = "1"
. (Join-Path $PSScriptRoot "build_windows.ps1")
Remove-Item Env:MYCC_BUILD_NO_DISPATCH -ErrorAction SilentlyContinue

# Steps that constitute the CPU-only build. Order matters: build the native
# backends first, then the Go binaries, then package.
$script:CPU_ONLY_STEPS = @(
    "cpu",
    "cpuArm64",
    "ollama",
    "ollamaArm64",
    "app",
    "appArm64",
    "deps",
    "sign",
    "installer",
    "zip"
)

try {
    if ($($args.count) -eq 0) {
        Write-Output "Running CPU-only Windows build (GPU/driver backends excluded)"
        foreach ($step in $script:CPU_ONLY_STEPS) {
            if (Get-Command -Name $step -CommandType Function -ErrorAction SilentlyContinue) {
                Write-Output "running build step $step"
                & $step
            }
        }
    } else {
        for ($i = 0; $i -lt $args.count; $i++) {
            Write-Output "running build step $($args[$i])"
            & $($args[$i])
        }
    }
} catch {
    Write-Error "Build Failed: $($_.Exception.Message)"
    Write-Error "$($_.ScriptStackTrace)"
} finally {
    set-location $script:SRC_DIR
    $env:PKG_VERSION = ""
}
