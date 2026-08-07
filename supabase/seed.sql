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
