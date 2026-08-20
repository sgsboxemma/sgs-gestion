-- SGS Gestion V9.6 - Synchronisation automatique et protection des modifications concurrentes.
-- À exécuter une seule fois dans Supabase > SQL Editor > New query.

alter table public.members
  add column if not exists version bigint not null default 1;

create table if not exists public.member_updates (
  id integer primary key check (id = 1),
  changed_at timestamptz not null default now()
);

insert into public.member_updates(id,changed_at)
values (1,now())
on conflict (id) do nothing;

alter table public.member_updates enable row level security;
grant select on public.member_updates to authenticated;

drop policy if exists "utilisateurs suivent modifications" on public.member_updates;
create policy "utilisateurs suivent modifications"
on public.member_updates for select to authenticated
using (true);

create or replace function public.signal_member_update()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  update public.member_updates set changed_at=clock_timestamp() where id=1;
  return null;
end $$;

drop trigger if exists members_signal_update on public.members;
create trigger members_signal_update
after insert or update or delete on public.members
for each statement execute function public.signal_member_update();

create or replace function public.save_member(p_member jsonb,p_expected_version bigint default 0)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare
  v_id uuid := (p_member->>'id')::uuid;
  v_saved public.members%rowtype;
begin
  if public.current_role() not in ('owner','admin') then
    raise exception 'Accès refusé';
  end if;

  if coalesce(p_expected_version,0)=0 then
    insert into public.members(
      id,last_name,first_name,sex,birth,phone,email,address,zip,city,
      cat_override,acts,due,payments,comments,photo_path,medical_path,medical_name,version
    ) values (
      v_id,p_member->>'last_name',p_member->>'first_name',nullif(p_member->>'sex',''),
      nullif(p_member->>'birth','')::date,nullif(p_member->>'phone',''),nullif(p_member->>'email',''),
      nullif(p_member->>'address',''),nullif(p_member->>'zip',''),nullif(p_member->>'city',''),
      nullif(p_member->>'cat_override',''),coalesce(p_member->'acts','[]'::jsonb),
      coalesce((p_member->>'due')::numeric,0),coalesce(p_member->'payments','[]'::jsonb),
      nullif(p_member->>'comments',''),nullif(p_member->>'photo_path',''),
      nullif(p_member->>'medical_path',''),nullif(p_member->>'medical_name',''),1
    ) returning * into v_saved;
  else
    update public.members set
      last_name=p_member->>'last_name',first_name=p_member->>'first_name',
      sex=nullif(p_member->>'sex',''),birth=nullif(p_member->>'birth','')::date,
      phone=nullif(p_member->>'phone',''),email=nullif(p_member->>'email',''),
      address=nullif(p_member->>'address',''),zip=nullif(p_member->>'zip',''),city=nullif(p_member->>'city',''),
      cat_override=nullif(p_member->>'cat_override',''),acts=coalesce(p_member->'acts','[]'::jsonb),
      due=coalesce((p_member->>'due')::numeric,0),payments=coalesce(p_member->'payments','[]'::jsonb),
      comments=nullif(p_member->>'comments',''),photo_path=nullif(p_member->>'photo_path',''),
      medical_path=nullif(p_member->>'medical_path',''),medical_name=nullif(p_member->>'medical_name',''),
      version=version+1,updated_at=clock_timestamp()
    where id=v_id and version=p_expected_version
    returning * into v_saved;

    if not found then
      raise exception 'FICHE_MODIFIEE: cette fiche a été modifiée par un autre utilisateur. Rechargez-la avant de réessayer.';
    end if;
  end if;

  return to_jsonb(v_saved);
exception
  when unique_violation then
    raise exception 'FICHE_MODIFIEE: cette fiche existe déjà ou vient d’être créée ailleurs.';
end $$;

revoke all on function public.save_member(jsonb,bigint) from public;
grant execute on function public.save_member(jsonb,bigint) to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='member_updates'
  ) then
    alter publication supabase_realtime add table public.member_updates;
  end if;
end $$;
