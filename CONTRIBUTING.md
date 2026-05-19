# Contributing to AerialWall

## Branch model

| Branch | Purpose |
|---|---|
| `develop` | Active development — default branch |
| `beta/vX.Y.Z` | Beta stabilisation cut from `develop` |
| `release/vX.Y.Z` | Release candidate; merges to `main` on publish |
| `main` | Always-stable; only merged from `release/*` |

Open PRs against **`develop`** unless explicitly told otherwise.

## Spec-driven development

AerialWall uses a lightweight SDD (spec-driven development) loop:

1. Check `SPEC.md` for the relevant `§V` invariant before changing anything
2. If behaviour changes, update or add a `§V` invariant
3. If a bug is fixed, add a `§B` entry and the invariant that would have
   caught it earlier
4. Run `swift test` — all 62 tests must pass

## Running locally

```bash
git clone https://github.com/CatKinKitKat/AerialWall
cd AerialWall
swift run AerialWall     # builds and launches the app
swift test               # runs the test suite
```

**Requirements**: macOS 26 (Tahoe) ≥ 26.4, Xcode 16+, Swift 6.

## Code style

- Swift 6 strict concurrency — no `@preconcurrency` unless justified
- No hardcoded hex colours — use `Color(.windowBackgroundColor)` etc. (V32)
- All paths through `Constants.*` (V5, V22)
- Atomic writes for `entries.json` via `Data.write(.atomic)` (V14)
- No ffmpeg in the production runtime path (V47/V48 — native VT only)

## PR checklist

See `.github/PULL_REQUEST_TEMPLATE.md`.

## Commit messages

Conventional Commits format: `fix(scope): description` / `feat(scope): ...`
When backpropping a bug use `fix(BN):` matching the `§B` entry id.
