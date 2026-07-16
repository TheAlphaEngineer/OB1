-- OB1 upgrade — additive migration (requires explicit approval before running).
-- Project <PROJECT_REF> · PostgreSQL 17.6 · 397 rows · embedding vector(1536).
--
-- Scope: fill the ONLY gap the new grafted open-brain-mcp needs — dedup capture
-- (the new capture_thought calls the upsert_thought RPC, which needs the
-- content_fingerprint column + a partial unique index).
--
-- Preflight (2026-07-16) confirmed ALREADY PRESENT and therefore NOT touched here:
--   • updated_at column (default now(), non-null on all 397 rows)
--   • thoughts_updated_at BEFORE UPDATE trigger + update_updated_at()
--   • match_thoughts(vector, float, int, jsonb)  -- already the 4-arg signature
--   • service_role DELETE grant on public.thoughts
--   • RLS enabled + "Service role full access" policy
--
-- ZERO writes to existing rows (constraint compliance):
--   • ADD COLUMN has NO DEFAULT  -> catalog-only on PG17, no table rewrite; the 397
--     existing rows read NULL. (A constant DEFAULT would make them *read* a new value;
--     a volatile DEFAULT would physically rewrite. Both are deliberately avoided.)
--   • The partial unique index covers only content_fingerprint IS NOT NULL, so all 397
--     legacy (NULL-fingerprint) rows are excluded and can never be an ON CONFLICT / dedup
--     target — structurally immune to modification by upsert_thought.
--   • CREATE FUNCTION / GRANT are catalog-only.
--   • Nothing re-embeds; the embedding column and its 1536 dimension are untouched.

begin;

-- 1) Dedup fingerprint column (nullable, no default => catalog-only; existing rows NULL).
alter table public.thoughts add column if not exists content_fingerprint text;

-- 2) Partial unique index enabling upsert_thought's ON CONFLICT. Empty at creation
--    (all fingerprints NULL), so the build reads rows but writes only the index.
create unique index if not exists idx_thoughts_fingerprint
  on public.thoughts (content_fingerprint)
  where content_fingerprint is not null;

-- 3) upsert_thought — verbatim upstream (docs/01-getting-started.md). sha256() is a
--    built-in (PG>=11). Only ever updates a row it just conflicted with on a non-null
--    fingerprint, i.e. a row created post-migration; legacy rows are never touched.
create or replace function public.upsert_thought(p_content text, p_payload jsonb default '{}')
returns jsonb as $$
declare
  v_fingerprint text;
  v_result jsonb;
  v_id uuid;
begin
  v_fingerprint := encode(sha256(convert_to(
    lower(trim(regexp_replace(p_content, '\s+', ' ', 'g'))),
    'UTF8'
  )), 'hex');

  insert into thoughts (content, content_fingerprint, metadata)
  values (p_content, v_fingerprint, coalesce(p_payload->'metadata', '{}'::jsonb))
  on conflict (content_fingerprint) where content_fingerprint is not null do update
  set updated_at = now(),
      metadata = thoughts.metadata || coalesce(excluded.metadata, '{}'::jsonb)
  returning id into v_id;

  v_result := jsonb_build_object('id', v_id, 'fingerprint', v_fingerprint);
  return v_result;
end;
$$ language plpgsql;

-- 4) Execute grant for the new RPC (service_role already holds table DML per preflight).
grant execute on function public.upsert_thought(text, jsonb) to service_role;

commit;
