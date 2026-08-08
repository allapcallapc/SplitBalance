-- Server-side COUNT() for AggregatedCalculationService.fetchPersonBillCount
-- (the "Expenses Added" stat on the summary screen), replacing an
-- unpaginated .select('id') that reintroduced the exact truncation bug
-- 20260808130000_add_bill_aggregation_rpcs.sql fixed for the other three
-- fetchers in the same file: PostgREST's max_rows (1000, supabase/
-- config.toml) silently caps an unpaginated .select() result instead of
-- erroring, so a person with more than ~1000 bills would get a silently
-- wrong count here.
--
-- Same conventions as the sibling RPCs: `stable` (not `security definer`,
-- so the existing bills_select RLS policy still gates what a caller can
-- see), `search_path` pinned per Supabase's function_search_path_mutable
-- lint, explicit EXECUTE grants for parity between hosted and local
-- Postgres.

create function person_bill_count(p_household_id uuid, p_paid_by text)
returns bigint
language sql stable
set search_path = public
as $$
  select count(*)
  from bills
  where household_id = p_household_id and paid_by = p_paid_by;
$$;

grant execute on function person_bill_count(uuid, text)
  to anon, authenticated, service_role;
