# OB1 Deployment (fork overlay)

This fork tracks a **personal in-place deployment** of Open Brain. It adds a small,
clearly-delimited overlay on top of upstream `NateBJones-Projects/OB1` so the deployed
Supabase edge function can be redeployed and upgraded reproducibly.

> **No secrets or project-specific identifiers live in this repo.** Project ref, access
> keys, and service keys are supplied at runtime from a local, un-committed `.env`
> (`C:\Users\peter\.secrets\ob1.env`, loaded into the process env at point of use) and are
> referenced here only by **placeholder** and by **variable name**.

## Branch layout

| Branch | Purpose | Pushed to fork? |
|---|---|---|
| `main` | Mirrors upstream `main`. Never edited directly. | yes |
| `ob1-deploy` | `main` + this deploy overlay (scaffold, docs, SQL). What gets deployed. | yes |
| `pre-upgrade-snapshot` | Verbatim copy of the **live** deployed function sources, downloaded before the upgrade. One-command rollback source. | **no — local only** (contains live sources) |

**Upstream base pin:** `677910600de98067f61c120d65956b23f360aedb` (upstream `main` @ 2026-07-03).

## What the overlay adds

- `.gitignore` — one edit: upstream ignores `supabase/` wholesale; we track the deploy
  scaffold and ignore only `supabase/.temp/` + `.env.deploy`.
- `supabase/functions/open-brain-mcp/` — the deployed MCP server: a verbatim copy of
  upstream `server/index.ts` **plus** two delimited `LOCAL ADDITION` blocks grafting the
  `update_thought` and `delete_thought` tools (adapted from `integrations/*-thought-mcp/`,
  with a zod-4 `z.record(z.string(), z.unknown())` fix and a required `confirm: true`
  guard on delete), with `deno.json` copied verbatim from `server/deno.json`.
  **This is the only function on this (pushed) branch** — it is built from public upstream
  and contains nothing private.
- `scripts/` — `preflight.sql` (read-only introspection), `migrate.sql` (additive, gated),
  `rollback.sql` (optional teardown; normally unused).

The live sources of the other deployed functions (`household-knowledge`, `ingest-thought`)
are retained ONLY on the local-only `pre-upgrade-snapshot` branch and are never pushed.

## Deployed functions (names only)

- `open-brain-mcp` — core MCP server (8 tools after upgrade). **Redeployed by this upgrade.**
- `household-knowledge` — extension (5 tools; separate in-function auth). **Untouched.**
- `ingest-thought` — Slack capture webhook that inserts into `thoughts`. **Untouched.**
  (Relevant to backups: it is a live write path — pause the Slack capture channel during
  any before/after row-count verification.)

## Function secrets (names only — set in Supabase, project-scoped)

- `MCP_ACCESS_KEY` — shared access secret (header `x-brain-key` or `?key=`).
- `OPENROUTER_API_KEY` — embeddings (`openai/text-embedding-3-small`, 1536-dim) + metadata.
- `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` — platform-injected.

## Deploy

```powershell
# From repo root, on ob1-deploy. NEVER --prune. ALWAYS name the function + --no-verify-jwt.
npx -y supabase@2.109.1 functions deploy open-brain-mcp `
  --project-ref <PROJECT_REF> --no-verify-jwt --use-api
```

Banned: `--prune` (would delete `household-knowledge`); bare `functions deploy` with no slug
(deploys everything in the scaffold).

## Rollback (code — the only rollback normally needed)

```powershell
git switch pre-upgrade-snapshot
npx -y supabase@2.109.1 functions deploy open-brain-mcp `
  --project-ref <PROJECT_REF> --no-verify-jwt --use-api
```

The additive SQL is backward-compatible with the old code, so SQL rollback is not required.
`scripts/rollback.sql` (recreate the pre-upgrade `match_thoughts` from the preflight capture)
is filed for completeness; do not drop the added columns (would discard post-upgrade data).

## Pull upstream updates later

```powershell
git fetch upstream
git switch main;  git merge --ff-only upstream/main;  git push origin main
git switch ob1-deploy;  git merge main
# Re-copy server/index.ts over the scaffold, re-apply the two LOCAL ADDITION blocks
# (delimiters make this mechanical), then:
npx -y deno@2 check supabase/functions/open-brain-mcp/index.ts
# Review the diff, check upstream docs for any NEW migrations (gate before running SQL),
# then deploy (gate).
```
