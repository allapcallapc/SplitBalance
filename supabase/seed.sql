-- Seed data for the staging Supabase project (used by the /main/ and
-- /pr-<n>/ preview deploys) so previews aren't completely blank. Never
-- run this against production.
--
-- Deliberately does NOT create an auth.users row: inserting into
-- Supabase-managed auth tables directly is unsupported and brittle across
-- GoTrue schema versions. Instead this seeds a fixed household with a
-- known invite code - sign up with any test account through the app, then
-- use "Join household" with the code below to land in a pre-populated
-- household instead of an empty one.
insert into households (id, invite_code)
values ('00000000-0000-0000-0000-000000000001', 'demo0001')
on conflict (id) do nothing;

insert into categories (household_id, name)
values
  ('00000000-0000-0000-0000-000000000001', 'Groceries'),
  ('00000000-0000-0000-0000-000000000001', 'Rent'),
  ('00000000-0000-0000-0000-000000000001', 'Utilities'),
  ('00000000-0000-0000-0000-000000000001', 'Entertainment')
on conflict do nothing;

-- Demo household has no real household_members (that requires an actual
-- auth.users row - see above), so "Bobby"/"Jane" below are just free-text
-- names, same as paid_by/person1/person2 always are in this schema.

-- Fixed ids so re-running this file (e.g. after a migration reset) doesn't
-- keep piling up duplicate splits/bills - neither table has a natural
-- unique constraint to key an ON CONFLICT off of otherwise.
insert into payment_splits (id, household_id, category, person1, person1_percentage, person2, person2_percentage, end_date)
values
  ('00000000-0000-0000-0002-000000000001', '00000000-0000-0000-0000-000000000001', 'Groceries', 'Bobby', 50, 'Jane', 50, null),
  ('00000000-0000-0000-0002-000000000002', '00000000-0000-0000-0000-000000000001', 'Rent', 'Bobby', 60, 'Jane', 40, null),
  ('00000000-0000-0000-0002-000000000003', '00000000-0000-0000-0000-000000000001', 'Utilities', 'Bobby', 50, 'Jane', 50, null),
  ('00000000-0000-0000-0002-000000000004', '00000000-0000-0000-0000-000000000001', 'Entertainment', 'Bobby', 50, 'Jane', 50, null)
on conflict (id) do nothing;

insert into bills (id, household_id, date, amount, paid_by, category, details)
values
  ('00000000-0000-0000-0003-000000000001', '00000000-0000-0000-0000-000000000001', '2026-06-05', 42.50, 'Bobby', 'Groceries', 'Weekly grocery run'),
  ('00000000-0000-0000-0003-000000000002', '00000000-0000-0000-0000-000000000001', '2026-06-15', 1200.00, 'Jane', 'Rent', 'June rent'),
  ('00000000-0000-0000-0003-000000000003', '00000000-0000-0000-0000-000000000001', '2026-06-20', 85.30, 'Bobby', 'Utilities', 'Electricity bill'),
  ('00000000-0000-0000-0003-000000000004', '00000000-0000-0000-0000-000000000001', '2026-07-02', 38.90, 'Jane', 'Groceries', 'Grocery run'),
  ('00000000-0000-0000-0003-000000000005', '00000000-0000-0000-0000-000000000001', '2026-07-15', 1200.00, 'Jane', 'Rent', 'July rent'),
  ('00000000-0000-0000-0003-000000000006', '00000000-0000-0000-0000-000000000001', '2026-07-18', 60.00, 'Bobby', 'Entertainment', 'Movie night'),
  ('00000000-0000-0000-0003-000000000007', '00000000-0000-0000-0000-000000000001', '2026-07-22', 92.10, 'Bobby', 'Utilities', 'Internet + water'),
  ('00000000-0000-0000-0003-000000000008', '00000000-0000-0000-0000-000000000001', '2026-08-01', 45.75, 'Jane', 'Groceries', 'Grocery run'),
  ('00000000-0000-0000-0003-000000000009', '00000000-0000-0000-0000-000000000001', '2026-08-05', 1200.00, 'Bobby', 'Rent', 'August rent')
on conflict (id) do nothing;
