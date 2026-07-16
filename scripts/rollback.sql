-- OB1 upgrade — OPTIONAL SQL teardown. NORMALLY NOT RUN.
--
-- The migration (scripts/migrate.sql) is purely additive and backward-compatible:
-- the pre-upgrade function code never referenced upsert_thought or content_fingerprint,
-- so redeploying the pre-upgrade code (git switch pre-upgrade-snapshot; functions deploy)
-- ALONE fully restores prior behavior. No SQL rollback is required for a code rollback.
--
-- match_thoughts was NOT modified by the migration, so there is nothing to restore there.
-- (For the record, its pre-upgrade definition is preserved in the Phase B preflight capture.)
--
-- Run the block below ONLY to fully remove the additions (e.g. abandoning the upgrade).
-- Safe only if no post-upgrade capture wrote fingerprinted rows you wish to keep.

begin;
drop function if exists public.upsert_thought(text, jsonb);
drop index if exists public.idx_thoughts_fingerprint;
-- Intentionally NOT dropped: content_fingerprint column. Leaving it is harmless; dropping
-- it would discard fingerprints on any rows captured after the upgrade. Uncomment only if
-- you are certain you want it gone:
-- alter table public.thoughts drop column if exists content_fingerprint;
commit;
