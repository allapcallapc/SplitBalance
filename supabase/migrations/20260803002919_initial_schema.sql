-- Initial schema for SplitBalance's Supabase backend.
-- Replaces the Google Drive folder + CSV files with a shared "household"
-- that both people's accounts belong to, enforced via RLS.

-- ---------------------------------------------------------------------
-- households: replaces "the shared Drive folder"
-- ---------------------------------------------------------------------
create table households (
  id uuid primary key default gen_random_uuid(),
  invite_code text unique not null default substr(md5(random()::text), 1, 8),
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- household_members: replaces person_names.csv (one row per person per household)
-- ---------------------------------------------------------------------
create table household_members (
  household_id uuid not null references households(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  person_name text not null,
  joined_at timestamptz not null default now(),
  primary key (household_id, user_id)
);

-- ---------------------------------------------------------------------
-- bills: replaces bills.csv
-- ---------------------------------------------------------------------
create table bills (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households(id) on delete cascade,
  date date not null,
  amount numeric(10,2) not null,
  paid_by text not null,       -- free text, not FK: current model allows third-party payers
  category text not null,
  details text not null default '',
  created_at timestamptz not null default now()
);
create index bills_household_date_idx on bills (household_id, date desc);

-- ---------------------------------------------------------------------
-- categories: replaces categories.csv
-- ---------------------------------------------------------------------
create table categories (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now()
);
-- Table-level UNIQUE constraints can't reference expressions like lower(name),
-- so case-insensitive uniqueness is enforced via a unique index instead.
create unique index categories_household_lower_name_idx
  on categories (household_id, lower(name));

-- ---------------------------------------------------------------------
-- payment_splits: replaces payment_splits.csv
-- ---------------------------------------------------------------------
create table payment_splits (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households(id) on delete cascade,
  end_date date,                -- null = open-ended (applies after the last endDate)
  category text not null,       -- "all"-category splits are UI-only, never persisted (matches current CsvService behavior)
  person1 text not null,
  person1_percentage numeric(5,2) not null,
  person2 text not null,
  person2_percentage numeric(5,2) not null,
  created_at timestamptz not null default now(),
  check (category <> 'all'),
  check (person1_percentage between 0 and 100),
  check (person2_percentage between 0 and 100),
  check (abs(person1_percentage + person2_percentage - 100) <= 0.01)
);

-- ---------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------
-- household_members can't reference itself in its own RLS policy without
-- causing infinite recursion, so membership checks go through this
-- security-definer helper instead.
create function is_household_member(target_household uuid) returns boolean
language sql security definer stable as $$
  select exists (
    select 1 from household_members
    where household_id = target_household and user_id = auth.uid()
  );
$$;

alter table households enable row level security;
alter table household_members enable row level security;
alter table bills enable row level security;
alter table categories enable row level security;
alter table payment_splits enable row level security;

-- households: any authenticated user can create one (they become a member
-- via join_household/create flow below); membership governs read access.
create policy "households_select" on households
  for select using (is_household_member(id));
create policy "households_insert" on households
  for insert with check (auth.uid() is not null);

create policy "household_members_select" on household_members
  for select using (is_household_member(household_id));
create policy "household_members_insert" on household_members
  for insert with check (is_household_member(household_id));
create policy "household_members_update" on household_members
  for update using (is_household_member(household_id));
create policy "household_members_delete" on household_members
  for delete using (is_household_member(household_id));

create policy "bills_select" on bills
  for select using (is_household_member(household_id));
create policy "bills_insert" on bills
  for insert with check (is_household_member(household_id));
create policy "bills_update" on bills
  for update using (is_household_member(household_id));
create policy "bills_delete" on bills
  for delete using (is_household_member(household_id));

create policy "categories_select" on categories
  for select using (is_household_member(household_id));
create policy "categories_insert" on categories
  for insert with check (is_household_member(household_id));
create policy "categories_update" on categories
  for update using (is_household_member(household_id));
create policy "categories_delete" on categories
  for delete using (is_household_member(household_id));

create policy "payment_splits_select" on payment_splits
  for select using (is_household_member(household_id));
create policy "payment_splits_insert" on payment_splits
  for insert with check (is_household_member(household_id));
create policy "payment_splits_update" on payment_splits
  for update using (is_household_member(household_id));
create policy "payment_splits_delete" on payment_splits
  for delete using (is_household_member(household_id));

-- ---------------------------------------------------------------------
-- create_household: creates a household and adds the caller as its first
-- member in one step (bypasses the chicken-and-egg problem where the
-- caller isn't a member yet when the households_select policy runs).
-- ---------------------------------------------------------------------
create function create_household(name text) returns uuid
language plpgsql security definer as $$
declare hh_id uuid;
begin
  insert into households default values returning id into hh_id;
  insert into household_members (household_id, user_id, person_name)
  values (hh_id, auth.uid(), name);
  return hh_id;
end;
$$;

-- ---------------------------------------------------------------------
-- join_household: looks up a household by invite code and adds the
-- caller as a member. security definer because the caller can't satisfy
-- is_household_member on the target household until after this runs.
-- ---------------------------------------------------------------------
create function join_household(code text, name text) returns uuid
language plpgsql security definer as $$
declare hh_id uuid;
begin
  select id into hh_id from households where invite_code = code;
  if hh_id is null then
    raise exception 'Invalid invite code';
  end if;
  insert into household_members (household_id, user_id, person_name)
  values (hh_id, auth.uid(), name)
  on conflict (household_id, user_id) do update set person_name = excluded.person_name;
  return hh_id;
end;
$$;
