-- Server-side SUM()/COUNT() aggregates for AggregatedCalculationService,
-- replacing the fetch functions that previously pulled every matching bill
-- row into Dart and summed with a fold. See
-- https://github.com/allapcallapc/SplitBalance/issues/57: PostgREST's
-- max_rows (1000, set in supabase/config.toml) silently truncates an
-- unpaginated .select() result instead of erroring, so a household where
-- one person had paid more than ~1000 bills got a silently wrong
-- person1Paid/person2Paid/totalAmount/totalBills on the summary screen.
--
-- These are `stable` SQL functions, not `security definer` - they run as
-- the calling role (SECURITY INVOKER is the default), so the existing
-- bills_select RLS policy (is_household_member) still gates what a caller
-- can see, exactly like the .select() calls they replace.

create function person_paid_total(p_household_id uuid, p_paid_by text)
returns numeric
language sql stable as $$
  select coalesce(sum(amount), 0)
  from bills
  where household_id = p_household_id and paid_by = p_paid_by;
$$;

create function household_totals(p_household_id uuid)
returns table(bill_count bigint, total_amount numeric)
language sql stable as $$
  select count(*), coalesce(sum(amount), 0)
  from bills
  where household_id = p_household_id;
$$;

-- p_period_start is exclusive, p_period_end is inclusive - either may be
-- null for -/+infinity, matching FetchCategoryPeriodPersonPaid's contract
-- in aggregated_calculation_service.dart.
create function category_period_person_paid(
  p_household_id uuid,
  p_category text,
  p_period_start date,
  p_period_end date,
  p_paid_by text
) returns numeric
language sql stable as $$
  select coalesce(sum(amount), 0)
  from bills
  where household_id = p_household_id
    and category = p_category
    and paid_by = p_paid_by
    and (p_period_start is null or date > p_period_start)
    and (p_period_end is null or date <= p_period_end);
$$;

-- Explicit EXECUTE grants, mirroring the previous table-grants migration
-- (20260808004247): don't rely on default PUBLIC execute privileges, which
-- behave inconsistently between a hosted Supabase project (execute on new
-- public-schema functions is revoked from anon/authenticated by default
-- there, as a platform security hardening measure) and a bare local
-- Postgres (grants execute to PUBLIC by default). Grant explicitly so
-- behavior is identical in both environments.
grant execute on function person_paid_total(uuid, text)
  to anon, authenticated, service_role;
grant execute on function household_totals(uuid)
  to anon, authenticated, service_role;
grant execute on function category_period_person_paid(uuid, text, date, date, text)
  to anon, authenticated, service_role;

alter default privileges in schema public
  grant execute on functions to anon, authenticated, service_role;
