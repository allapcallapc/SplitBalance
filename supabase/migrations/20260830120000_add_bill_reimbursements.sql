-- Adds bill_reimbursements: records of money that came back against part of
-- a bill (an insurance payout, a store refund, a friend paying back their
-- share directly, etc). A bill's "real" cost for balance purposes is
-- amount minus the sum of its reimbursements - computed live everywhere a
-- bill's amount is summed (see AggregatedCalculationService/Bill.netAmount)
-- rather than cached on the bill row, so there's no denormalized total to
-- keep in sync or race on concurrent inserts.
--
-- Needs a manual `supabase db push` to staging/prod before this feature
-- will work there (see CLAUDE.md).
create table bill_reimbursements (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households(id) on delete cascade,
  bill_id uuid not null references bills(id) on delete cascade,
  date date not null,
  amount numeric(10,2) not null check (amount > 0),
  received_by text not null,   -- free text, matches bills.paid_by's convention
  note text not null default '',
  created_at timestamptz not null default now()
);
create index bill_reimbursements_bill_idx on bill_reimbursements (bill_id);
create index bill_reimbursements_household_date_idx
  on bill_reimbursements (household_id, date desc);

alter table bill_reimbursements enable row level security;

create policy "bill_reimbursements_select" on bill_reimbursements
  for select using (is_household_member(household_id));
create policy "bill_reimbursements_insert" on bill_reimbursements
  for insert with check (is_household_member(household_id));
create policy "bill_reimbursements_update" on bill_reimbursements
  for update using (is_household_member(household_id));
create policy "bill_reimbursements_delete" on bill_reimbursements
  for delete using (is_household_member(household_id));
