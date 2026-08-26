-- SGS Gestion V13 - Cours d'essai
-- A exécuter UNE SEULE FOIS dans Supabase > SQL Editor.

create table if not exists public.trial_members (
  id uuid primary key default gen_random_uuid(),
  last_name text not null,
  first_name text not null,
  trial_start date not null default current_date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.trial_members enable row level security;

drop policy if exists "essais lecture tous profils" on public.trial_members;
create policy "essais lecture tous profils" on public.trial_members
for select to authenticated
using (public.current_role() in ('owner','admin','coach'));

drop policy if exists "essais ajout tous profils" on public.trial_members;
create policy "essais ajout tous profils" on public.trial_members
for insert to authenticated
with check (public.current_role() in ('owner','admin','coach'));

drop policy if exists "essais modification tous profils" on public.trial_members;
create policy "essais modification tous profils" on public.trial_members
for update to authenticated
using (public.current_role() in ('owner','admin','coach'))
with check (public.current_role() in ('owner','admin','coach'));

drop policy if exists "essais suppression tous profils" on public.trial_members;
create policy "essais suppression tous profils" on public.trial_members
for delete to authenticated
using (public.current_role() in ('owner','admin','coach'));

grant select,insert,update,delete on public.trial_members to authenticated;

-- Active le temps réel pour que les changements faits par un autre utilisateur
-- apparaissent rapidement dans l'application. La commande ignore proprement
-- le cas où la table est déjà ajoutée à la publication.
do $$
begin
  alter publication supabase_realtime add table public.trial_members;
exception
  when duplicate_object then null;
end $$;
