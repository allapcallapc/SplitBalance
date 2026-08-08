# CLAUDE.md

Guidance for Claude Code when working in this repository.

## PR titles must follow Conventional Commits

Releases are automated by [release-please](https://github.com/googleapis/release-please-action) (`.github/workflows/release-please.yml`), which decides the next version and writes the changelog by parsing commit messages - specifically the PR title, since PRs are squash-merged into a single commit.

Every PR title must start with one of:

- `fix: ...` - bug fix, bumps the patch version (2.0.9 -> 2.0.10)
- `feat: ...` - new feature, bumps the minor version (2.0.9 -> 2.1.0)
- `feat!: ...` or `fix!: ...` - breaking change, bumps the major version (2.0.9 -> 3.0.0)
- `chore: ...`, `refactor: ...`, `docs: ...`, `test: ...`, `ci: ...` - no version bump, but still recorded

A PR title without one of these prefixes won't be picked up by release-please at all - the change merges normally but is invisible to the changelog/version bump.

## Release flow

1. Merging a correctly-titled PR updates release-please's running "Release PR" (changelog + next version).
2. Merging that Release PR is the only manual release step: it creates the release as a draft, `release-apk.yml` builds the APK and attaches it, then publishes the release, which triggers `deploy.yml` to deploy the web build to GitHub Pages.
3. Do not create GitHub Releases manually via the UI, and do not push tags directly - either bypasses release-please's version tracking and can conflict with GitHub's immutable-releases restriction (once a tag name has been used by a published release, it can never have a release re-attached to it, even if that release is deleted).

## Avoid Postgres RPCs/schema migrations when a client-side query can do the job

There's no CI step or automation that applies `supabase/migrations/*.sql` to the staging or production Supabase projects - it's a manual `supabase db push` someone has to run. Code that depends on a new migration (e.g. a new RPC function) will work locally/in tests but break against staging/prod (`PGRST202: Could not find the function ...`) until someone remembers to push it, which can lag the code merge by an unpredictable amount.

Prefer plain PostgREST queries (`.select()`, `.eq()`, `.count(CountOption.exact)`, `.range()`, etc.) over a new RPC whenever one can do the job, even if it takes a few more lines - for example, `.count(CountOption.exact)` gets an exact row count via a `HEAD` request/`Content-Range` header without a schema change, and paginating with `.range()` in chunks and summing client-side avoids PostgREST's `max_rows` (`supabase/config.toml`) truncation without a server-side `SUM()`. See `lib/services/aggregated_calculation_service.dart` for this pattern in practice.

Only reach for an RPC/migration when there's genuinely no client-side way to get the right answer (e.g. an operation that must be atomic, or a query too expensive to express as paginated client-side aggregation) - and flag explicitly that it needs a manual `supabase db push` to staging/prod before the change will work there.
