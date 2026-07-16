-- OB1 upgrade — preflight introspection (READ-ONLY, single statement).
-- Resolves install-vintage unknowns before any migration is written.
-- Run via Supabase Management API POST /v1/projects/<ref>/database/query
-- (Bearer = SUPABASE_ACCESS_TOKEN) or paste into the dashboard SQL editor.
-- Contains no writes. The captured pg_get_functiondef(match_thoughts) IS the SQL rollback text.
select jsonb_pretty(jsonb_build_object(
  'server_version', current_setting('server_version'),
  'row_count', (select count(*) from public.thoughts),
  'created_range', (select jsonb_build_object('min', min(created_at), 'max', max(created_at)) from public.thoughts),
  'columns', (select jsonb_agg(jsonb_build_object('name', column_name, 'type', data_type,
        'default', column_default, 'nullable', is_nullable) order by ordinal_position)
      from information_schema.columns where table_schema='public' and table_name='thoughts'),
  'embedding_type', (select format_type(a.atttypid, a.atttypmod) from pg_attribute a
      where a.attrelid='public.thoughts'::regclass and a.attname='embedding'),
  'updated_at_nonnull', (select count(*) from public.thoughts t where (to_jsonb(t)->>'updated_at') is not null),
  'fingerprint_nonnull', (select count(*) from public.thoughts t where (to_jsonb(t)->>'content_fingerprint') is not null),
  'indexes', (select jsonb_agg(jsonb_build_object('name', indexname, 'def', indexdef))
      from pg_indexes where schemaname='public' and tablename='thoughts'),
  'functions', (select jsonb_agg(jsonb_build_object('name', p.proname,
        'identity_args', pg_get_function_identity_arguments(p.oid), 'def', pg_get_functiondef(p.oid)))
      from pg_proc p where p.pronamespace='public'::regnamespace
        and p.proname in ('match_thoughts','upsert_thought','update_updated_at')),
  'triggers', (select jsonb_agg(pg_get_triggerdef(t.oid)) from pg_trigger t
      where t.tgrelid='public.thoughts'::regclass and not t.tgisinternal),
  'rls_enabled', (select relrowsecurity from pg_class where oid='public.thoughts'::regclass),
  'policies', (select jsonb_agg(polname::text) from pg_policy where polrelid='public.thoughts'::regclass),
  'table_grants', (select jsonb_agg(jsonb_build_object('grantee', grantee, 'priv', privilege_type))
      from information_schema.role_table_grants where table_schema='public' and table_name='thoughts'),
  'extensions', (select jsonb_agg(jsonb_build_object('name', extname, 'version', extversion))
      from pg_extension where extname in ('vector','pgcrypto'))
));
