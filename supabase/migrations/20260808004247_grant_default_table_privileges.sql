-- Grants the baseline table privileges Supabase's hosted platform sets up
-- automatically at project creation, which a bare local Postgres (via
-- `supabase start` + replaying this repo's migrations from scratch) does
-- not get on its own. Discovered running the integration test suite
-- (test/integration/) against a genuinely fresh local stack: every write
-- failed with "42501 permission denied for table X" despite RLS policies
-- being otherwise correct - anon/authenticated/service_role had no
-- SELECT/INSERT/UPDATE/DELETE grants on any table at all, so Postgres
-- rejected the request before RLS was ever evaluated.
--
-- Safe to apply anywhere, including a hosted project that may already have
-- these grants from its original dashboard-driven setup - GRANT is
-- idempotent.
--
-- These grants alone don't bypass RLS: anon/authenticated remain fully
-- gated by the `is_household_member` policies defined in the initial
-- schema migration. Only service_role (rolbypassrls = true) actually
-- bypasses RLS, same as it does today for the tables that happened to
-- already have grants.
grant usage on schema public to anon, authenticated, service_role;

grant select, insert, update, delete on all tables in schema public
  to anon, authenticated, service_role;
grant usage, select on all sequences in schema public
  to anon, authenticated, service_role;

-- So tables created by *future* migrations get the same treatment
-- automatically, without needing a matching grant statement each time.
alter default privileges in schema public
  grant select, insert, update, delete on tables to anon, authenticated, service_role;
alter default privileges in schema public
  grant usage, select on sequences to anon, authenticated, service_role;
