-- SGS Gestion V15.4.15
-- Familles explicites : une correspondance de nom ou d'adresse ne donne plus automatiquement droit a la reduction.
-- La relation familiale est stockee separement de public.members.
-- Ce script ne modifie aucune colonne ni aucune valeur d'un adherent existant.

begin;

create table if not exists public.member_family_links (
  member_id uuid primary key references public.members(id) on delete cascade,
  family_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists member_family_links_family_id_idx
  on public.member_family_links(family_id);

alter table public.member_family_links enable row level security;

revoke all on table public.member_family_links from anon, authenticated;
grant select, insert, update, delete on table public.member_family_links to authenticated;
grant all on table public.member_family_links to service_role;

drop policy if exists "familles lecture profils" on public.member_family_links;
create policy "familles lecture profils"
on public.member_family_links for select
to authenticated
using (public.current_role() = any (array['owner'::text,'admin'::text,'coach'::text]));

drop policy if exists "familles ajout owner admin" on public.member_family_links;
create policy "familles ajout owner admin"
on public.member_family_links for insert
to authenticated
with check (public.current_role() = any (array['owner'::text,'admin'::text]));

drop policy if exists "familles modif owner admin" on public.member_family_links;
create policy "familles modif owner admin"
on public.member_family_links for update
to authenticated
using (public.current_role() = any (array['owner'::text,'admin'::text]))
with check (public.current_role() = any (array['owner'::text,'admin'::text]));

drop policy if exists "familles suppression owner admin" on public.member_family_links;
create policy "familles suppression owner admin"
on public.member_family_links for delete
to authenticated
using (public.current_role() = any (array['owner'::text,'admin'::text]));

with eligible as (
  select
    id,
    lower(trim(coalesce(last_name,''))) as lname,
    lower(trim(coalesce(address,''))) as addr,
    trim(coalesce(zip,'')) as zip,
    lower(trim(coalesce(city,''))) as city
  from public.members
  where trim(coalesce(last_name,'')) <> ''
    and trim(coalesce(address,'')) <> ''
    and trim(coalesce(zip,'')) <> ''
    and trim(coalesce(city,'')) <> ''
),
family_keys as materialized (
  select lname, addr, zip, city, gen_random_uuid() as family_id
  from eligible
  group by lname, addr, zip, city
  having count(*) > 1
)
insert into public.member_family_links(member_id, family_id)
select e.id, f.family_id
from eligible e
join family_keys f using (lname, addr, zip, city)
on conflict (member_id) do nothing;

create or replace function public.save_member_v15415(
  p_member jsonb,
  p_expected_version bigint default 0,
  p_family_anchor_id uuid default null
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $function$
declare
  v_id uuid := (p_member->>'id')::uuid;
  v_saved public.members%rowtype;
  v_family_id uuid;
begin
  if public.current_role() not in ('owner','admin') then
    raise exception 'Acces refuse';
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
      raise exception 'FICHE_MODIFIEE: cette fiche a ete modifiee par un autre utilisateur. Rechargez-la avant de reessayer.';
    end if;
  end if;

  if p_family_anchor_id is not null then
    if p_family_anchor_id = v_id then
      raise exception 'Lien famille invalide';
    end if;

    if not exists (select 1 from public.members where id=p_family_anchor_id) then
      raise exception 'Membre famille introuvable';
    end if;

    select family_id into v_family_id
    from public.member_family_links
    where member_id=p_family_anchor_id;

    if v_family_id is null then
      v_family_id := gen_random_uuid();
      insert into public.member_family_links(member_id,family_id)
      values (p_family_anchor_id,v_family_id)
      on conflict (member_id) do update
        set family_id=excluded.family_id, updated_at=clock_timestamp();
    end if;

    insert into public.member_family_links(member_id,family_id)
    values (v_id,v_family_id)
    on conflict (member_id) do update
      set family_id=excluded.family_id, updated_at=clock_timestamp();
  end if;

  return to_jsonb(v_saved);
exception
  when unique_violation then
    raise exception 'FICHE_MODIFIEE: cette fiche existe deja ou vient d etre creee ailleurs.';
end
$function$;

revoke all on function public.save_member_v15415(jsonb,bigint,uuid) from public, anon;
grant execute on function public.save_member_v15415(jsonb,bigint,uuid) to authenticated, service_role;

commit;

select count(*) as family_links_count from public.member_family_links;
