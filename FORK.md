# Fork notes: where this repo diverges from upstream

This repository (**`pkubangbang/ollama`**) tracks upstream
[`ollama/ollama`](https://github.com/ollama/ollama) closely. Everything that is
not listed on this page is expected to behave exactly like upstream — see the
[upstream README](https://github.com/ollama/ollama#readme) and
[docs.ollama.com](https://docs.ollama.com) for all shared behavior.

This page records **why** the fork deliberately diverges on three points, **what**
changed, and **where** to look. It is a decision record, not a usage guide.

| #   | Divergence                              | Main reason                                                                     | Status                                                                                        |
| --- | --------------------------------------- | ------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| 1   | Concurrency control on the request path | Cap in-flight **cloud proxy** requests, which bypass the local runner semaphore | Branch `server/cloud-concurrency-cap` (`7d89174a`); not in `main`, not in `v0.40.8-cpu-win64` |
| 2   | CPU-only / driver-free Windows bundle   | Run on machines with no CUDA/ROCm/Vulkan drivers; reproducible artifact         | Built + released by the fork's skills (through `v0.40.8-cpu-win64`)                           |
| 3   | Remove the "Apps" tab and app detection | The app picker is not part of the CLI-first product this fork ships             | Done in the working tree (not yet committed)                                                  |

**Syncing with upstream.** `upstream` is a read-only remote; `origin` is the fork.

```shell
git remote -v          # origin -> pkubangbang/ollama, upstream -> ollama/ollama
git fetch upstream --tags
git log --oneline upstream/main..HEAD   # fork-only commits (docs/skills, etc.)
```

Divergence #3 rewrites `app/ui/app/src`, and the build/release flow for #2 lives
outside upstream files (`.mycc/skills/`), so upstream merges normally only conflict
in the UI tree — resolve in favour of this document's decisions. Divergence #1 is
an isolated branch that merges cleanly; if upstream adds its own cloud concurrency
control, prefer upstream's knob name and retire ours.

---

## 1. Concurrency control

### Decision

Upstream's scheduler semaphore (`server/sched.go`, `OLLAMA_NUM_PARALLEL`) only
gates requests that go through `scheduleRunner`. **Cloud requests early-return
before that point**, so on a busy or shared box an agent could fan out an
unbounded number of in-flight cloud proxy calls. The fork adds an explicit,
configurable cap on concurrent cloud proxy requests, independent of the local
runner limits.

### What changed

Commit **`7d89174a`** — _server(cloud): cap concurrent cloud proxy requests via
OLLAMA_MAX_CLOUD_CONCURRENCY_ — on branch **`origin/server/cloud-concurrency-cap`**.
Two files:

| File                    | Change                                                                                                                                                                                              |
| ----------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `envconfig/config.go`   | new `MaxCloudConcurrency()` reading `OLLAMA_MAX_CLOUD_CONCURRENCY` (default `0` = unlimited), registered in the env var table                                                                       |
| `server/cloud_proxy.go` | package-level `cloudProxySem` (`golang.org/x/sync/semaphore.Weighted`) acquired around `proxyCloudRequestWithPath`, the funnel for chat / embeddings / model details / balance / usage / web-search |

```go
// server/cloud_proxy.go
var cloudProxySem = newCloudProxySemaphore(envconfig.MaxCloudConcurrency())

func newCloudProxySemaphore(limit int) *semaphore.Weighted {
	if limit <= 0 {
		return nil            // nil == unlimited == upstream behavior
	}
	return semaphore.NewWeighted(int64(limit))
}
...
if cloudProxySem != nil {
	if err := cloudProxySem.Acquire(c.Request.Context(), 1); err != nil {
		return // client went away while waiting for a slot
	}
	defer cloudProxySem.Release(1)
}
```

### Rationale

- **The gap is real, not hypothetical.** Any workload that leans on cloud models
  (agent loops, batch embedding, web search) bypasses the local runner limits
  entirely; the scheduler cannot throttle what it never sees.
- **A separate limit, not a second use of `NUM_PARALLEL`.** Cloud and local traffic
  have different costs and different failure modes, so they get different knobs.
- **Default preserves upstream.** `0` disables the cap and the nil semaphore makes
  the code path a no-op, so a user who never sets the variable sees upstream
  behavior exactly. There is no silent throughput regression.
- **Backpressure over buffering.** Waiting requests block on the request context,
  so a disconnected client releases its place instead of occupying a slot.

### Tuning

```shell
# cap cloud traffic at 4 in-flight requests; 0 (default) is unlimited
OLLAMA_MAX_CLOUD_CONCURRENCY=4 ollama serve
```

On startup, with a non-zero cap, the server logs
`cloud proxy concurrency limit enabled env=OLLAMA_MAX_CLOUD_CONCURRENCY limit=4`.
The semaphore wait is per request and context-aware: a slow request holds one
slot only for its own duration, and requests waiting behind it abort when their
client disconnects rather than queueing indefinitely.

### Status

This change is **on its own branch and not merged into `main`** in this tree
(`git branch -r --contains 7d89174a` → `origin/server/cloud-concurrency-cap`), and
it is **not** in the shipped CPU-only release either — `v0.40.8-cpu-win64` targets
`7fdd2417`, which does not contain the commit. Until it lands, a `main` or
`-cpu-win64` build behaves exactly like upstream here; the local limits in the
table below are upstream's and always apply.

| Variable                       | Default         | Bounds                               | Where                                                            |
| ------------------------------ | --------------- | ------------------------------------ | ---------------------------------------------------------------- |
| `OLLAMA_NUM_PARALLEL`          | `1`             | parallel local runner requests       | `envconfig/config.go:277`                                        |
| `OLLAMA_MAX_QUEUE`             | `512`           | queued requests before `ErrMaxQueue` | `envconfig/config.go:281`, `server/sched.go:126`                 |
| `OLLAMA_MAX_LOADED_MODELS`     | `0` (auto)      | resident models                      | `envconfig/config.go:279`, `server/sched.go:269-333`             |
| `OLLAMA_MAX_CLOUD_CONCURRENCY` | `0` (unlimited) | in-flight cloud proxy requests       | `envconfig/config.go` (branch), `server/cloud_proxy.go` (branch) |

---

## 2. CPU-only / driver-free Windows bundle

### Decision

Ship a Windows **`windows-amd64`** distribution that contains **only** the CPU
`llama-server` backend. No CUDA, ROCm, Vulkan, or MLX payloads. The fork does not
produce the upstream multi-backend installer matrix; it produces one artifact
that runs on any x86-64 Windows box with no GPU driver requirements.

### What the bundle contains

Built into `dist\windows-amd64\`:

| Path                                    | Contents                                                                                                                                                                            |
| --------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ollama.exe`                            | Go CLI, cgo build (llvm-mingw)                                                                                                                                                      |
| `lib\ollama\llama-server.exe`           | the CPU backend                                                                                                                                                                     |
| `lib\ollama\ggml*.dll`, `libllama*.dll` | ggml micro-architecture variants (x64, sse42, sandybridge, ivybridge, haswell, piledriver, cannonlake, cascadelake, cooperlake, icelake, skylakex, alderlake, sapphirerapids, zen4) |
| `lib\ollama\*LICENSE*`                  | third-party licenses (`LLAMA_CPP_LICENSE`, `LLAMA_CPP_VENDORS_LICENSE`, `CPP_HTTPLIB_LICENSE`)                                                                                      |

The released zip places `ollama.exe` at the archive root and the backend under
`lib/ollama/`.

### How it is built

The native backend comes from the **`cpu_windows`** CMake preset
(`llama/server/CMakePresets.json:26`); the CLI needs cgo, so two toolchains are
involved — this is the part that bites.

```powershell
# 1. CPU llama-server backend -> dist\windows-amd64
cmake -S llama\server --preset cpu_windows --install-prefix $PWD\dist\windows-amd64
cmake --build build\llama-server-cpu --config Release --parallel <jobs>
cmake --install build\llama-server-cpu --component llama-server --strip

# 2. Go CLI, cgo via llvm-mingw
$env:CC='...\llvm-mingw-20240619-ucrt-x86_64\bin\gcc.exe'
$env:CXX='...\llvm-mingw-20240619-ucrt-x86_64\bin\g++.exe'
$env:CGO_ENABLED='1'
go build -trimpath -ldflags "-s -w -X=github.com/ollama/ollama/version.Version=<ver>" `
  -o dist\windows-amd64\ollama.exe .
```

The full, verified procedure (tool versions, the app/installer steps, and six
known pitfalls) lives in **`.mycc/skills/build-windows-cpu-only/SKILL.md`**, and
packaging/publishing lives in
**`.mycc/skills/release-windows-cpu-build/SKILL.md`**. Both are tracked
(`.gitignore` has `!/.mycc/skills/`) precisely so the procedure survives upstream
merges.

### Rationale

- **No driver installs.** Users on locked-down or driver-free Windows machines can
  still run models; nothing in the bundle links against a GPU runtime.
- **Reproducible.** One preset (`cpu_windows`), one artifact, one checksum — easier
  to verify than a matrix of CUDA 11/12/13 + ROCm + Vulkan payloads.
- **Explicit trade-off.** You lose GPU acceleration. A machine with a working
  CUDA/ROCm setup should use an upstream release instead.

### Release scheme

Tags are `v<upstream-version>-cpu-win64` and the base is always a **release tag**,
never an untagged `main` tip. Published so far:

- `v0.0.0-cpu-win64` — initial, pre-release-tagged base
- `v0.40.3-cpu-win64`
- `v0.40.8-cpu-win64` — on upstream `v0.40.8`

The version is baked into both `version.Version` and `app/version.Version` with
`-ldflags -X`; the source default is the `0.0.0` placeholder, so it is **not**
automatic.

---

## 3. The "Apps" tab is removed

### Decision

The fork's desktop UI has **two** sections — **Chat** and **Settings** — plus the
first-run onboarding flow. The upstream **Apps** tab, and the app-detection
machinery that fed it, are removed.

### What changed

| BEFORE (upstream)                                                                                                               | AFTER (this fork)                                     |
| ------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------- |
| Sidebar: Chat · **Apps** · Settings (`components/AppSidebar.tsx`)                                                               | Sidebar: Chat · Settings                              |
| Route `/connect` → `ConnectAppsScreen` (`routes/connect.tsx`)                                                                   | route deleted (`routeTree.gen.ts` no longer lists it) |
| `ConnectAppsScreen`: Claude/ChatGPT connect rows, `ollama launch …` cards, "command copied" toast (`components/Onboarding.tsx`) | removed                                               |
| `GET /api/v1/integrations` + `Server.getIntegrationStatuses` app detection (`app/ui/ui.go`)                                     | endpoint and handler removed                          |
| `getIntegrationStatuses()` client (`app/ui/app/src/api.ts`)                                                                     | removed                                               |
| `.apps-copy-*` toast styles (`index.css`)                                                                                       | removed                                               |
| Onboarding finishes by opening the Apps page                                                                                    | Onboarding finishes into **Settings** (`onFinish`)    |

`IntegrationStatus` survives as a plain type in `api.ts` because the ChatGPT
(Codex) row still uses it; only the _detection registry_ is gone.

### Rationale

- The tab existed to detect and connect third-party desktop apps. In this fork the
  primary entry point is `ollama launch <integration>` from the CLI, which already
  lists the same integrations — maintaining a second, UI-only detection path that
  shells out to the same registry (`cmd/launch`) duplicated logic and produced
  macOS-only branches the rest of the UI had to special-case.
- Fewer native bindings on the UI surface means fewer things to re-verify on every
  upstream merge of `app/ui`.

### What remains

- **Not removed (deliberately):**
  - The **Settings → Apps** section (Claude / Codex **model mappings**). It shares
    the word "Apps" but is a different feature — it assigns which model each app
    uses, and does not detect or connect anything.
  - The macOS tray **"Show apps in menu"** toggle and its native plumbing
    (`app_darwin.m`, `getShowAppsInMenu`/`setShowAppsInMenu`). It controls the macOS
    menu-bar list, not the UI tab.
- **Unchanged:** `ollama launch` in the CLI, `/api/v1/integrations/<integration>/models`
  (model mapping data), and the onboarding screens themselves.

### Reverting this

The removal is a small, self-contained commit set: restore `routes/connect.tsx`,
re-add the Apps entry in `components/AppSidebar.tsx` and the `ConnectAppsScreen`
export in `components/Onboarding.tsx`, and re-add `getIntegrationStatuses` in
`app/ui/app/src/api.ts` plus the `/api/v1/integrations` handler in `app/ui/ui.go`.
An upstream sync that re-introduces these files will conflict — resolve in favour
of the fork if the removal should stand.

---

## Verification

The fork's own checks for these areas:

```shell
# frontend (Apps tab removal, type surface)
cd app/ui/app && npx tsc --noEmit -p tsconfig.app.json && npx vitest run

# Go server (integrations endpoint removal, scheduler)
go vet ./app/ui/
```

`go test ./app/ui` requires cgo for `go-sqlite3`; on a machine without a C
compiler the tests cannot run (`CGO_ENABLED=0` → stub error, `CGO_ENABLED=1` →
`gcc` not found). Use the llvm-mingw `CC`/`CXX` from the build skill to run them.

## Keeping this page honest

When a divergence is added, changed, or dropped, update the table at the top and
the matching section in the same commit. If a change turns out to be temporary
(something expected to return to upstream), say so in its section instead of
deleting the record.
