# AGENTS.md

## Building

For a full build from the repository root:

```sh
cmake -B build .
cmake --build build --parallel 8
./ollama serve
```

For quick Go-only iteration against an existing native payload:

```sh
go build .
go run . serve
```

See `docs/development.md` for prerequisites, platform notes, GPU backends, and
the full development workflow.

## Fork notes

### The App tab is removed — the initial route must not target it

This fork dropped the Apps tab (`app: remove the Apps tab and app detection`).
Only the Chat and Settings tabs remain, and the `/connect` and `/apps` screens
no longer exist. Whenever navigation, deep links, or startup defaults change,
check the initial route too:

- The native app opens `/` on startup; the root route redirects first-run users
  to `/onboarding` (which finishes into `/settings`) and everyone else to a chat.
- `ollama://apps` is still accepted as a URL scheme, but it resolves to the same
  default route as a bare `ollama://`, so old shortcuts and links do not land on
  a "Not Found" page.
- Do not add navigation that points at a removed tab — no route, deep link, or
  startup default may reference the Apps page.

If a tab is removed again in the future, update the initial route and the URL
scheme dispatch in the same change, and record it here.
