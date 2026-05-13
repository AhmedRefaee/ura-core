create table if not exists order_templates (
  id           uuid primary key default gen_random_uuid(),
  entity_id    uuid not null references entities(id) on delete cascade,
  direction    text not null check (direction in ('outbound','inbound_rep','inbound_external')),
  rep_id       uuid references profiles(id) on delete set null,
  notes        text,
  is_manual    boolean not null default false,
  usage_count  int not null default 1,
  fingerprint  text not null,
  created_by   uuid references auth.users(id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique(entity_id, fingerprint)
);

create table if not exists order_template_items (
  id                  uuid primary key default gen_random_uuid(),
  template_id         uuid not null references order_templates(id) on delete cascade,
  inventory_id        uuid references inventory(id) on delete set null,
  inventory_name      text,
  quantity            int not null,
  is_custom           boolean not null default false,
  custom_description  text,
  source_inventory_id uuid references inventory(id) on delete set null
);

-- RLS: authenticated users can read and write all templates
alter table order_templates enable row level security;
alter table order_template_items enable row level security;

drop policy if exists "authenticated_all" on order_templates;
create policy "authenticated_all" on order_templates
  for all to authenticated using (true) with check (true);

drop policy if exists "authenticated_all" on order_template_items;
create policy "authenticated_all" on order_template_items
  for all to authenticated using (true) with check (true);

create or replace function increment_template_usage(p_id uuid)
returns void language sql security definer as $$
  update order_templates
  set usage_count = usage_count + 1,
      updated_at  = now()
  where id = p_id;
$$;
