-- SGS Gestion V9 - À exécuter une seule fois dans Supabase > SQL Editor.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','admin','coach')),
  created_at timestamptz not null default now()
);

create table if not exists public.members (
  id uuid primary key default gen_random_uuid(),
  last_name text not null,
  first_name text not null,
  sex text,
  birth date,
  phone text,
  email text,
  address text,
  zip text,
  city text,
  cat_override text,
  acts jsonb not null default '[]'::jsonb,
  due numeric(10,2) not null default 0 check (due >= 0),
  payments jsonb not null default '[]'::jsonb,
  comments text,
  photo_path text,
  medical_path text,
  medical_name text,
  version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.members enable row level security;

create or replace function public.current_role()
returns text language sql stable security definer set search_path = public
as $$ select role from public.profiles where user_id = auth.uid() $$;

revoke all on function public.current_role() from public;
grant execute on function public.current_role() to authenticated;

drop policy if exists "profile personnel" on public.profiles;
create policy "profile personnel" on public.profiles for select to authenticated
using (user_id = auth.uid());

drop policy if exists "owner admin lisent membres" on public.members;
create policy "owner admin lisent membres" on public.members for select to authenticated
using (public.current_role() in ('owner','admin'));

drop policy if exists "owner admin ajoutent membres" on public.members;
create policy "owner admin ajoutent membres" on public.members for insert to authenticated
with check (public.current_role() in ('owner','admin'));

drop policy if exists "owner admin modifient membres" on public.members;
create policy "owner admin modifient membres" on public.members for update to authenticated
using (public.current_role() in ('owner','admin')) with check (public.current_role() in ('owner','admin'));

drop policy if exists "owner admin suppriment membres" on public.members;
create policy "owner admin suppriment membres" on public.members for delete to authenticated
using (public.current_role() in ('owner','admin'));

create or replace function public.get_members()
returns jsonb language plpgsql stable security definer set search_path = public
as $$
declare r text := public.current_role();
begin
  if r = 'coach' then
    return coalesce((select jsonb_agg(jsonb_build_object(
      'id',id,'last_name',last_name,'first_name',first_name,'sex',sex,
      'birth',birth,'phone',phone,'acts',acts,'photo_path',photo_path,
      'created_at',created_at,'updated_at',updated_at
    ) order by last_name,first_name) from public.members),'[]'::jsonb);
  elsif r in ('owner','admin') then
    return coalesce((select jsonb_agg(to_jsonb(m) order by last_name,first_name) from public.members m),'[]'::jsonb);
  end if;
  raise exception 'Accès refusé';
end $$;

revoke all on function public.get_members() from public;
grant execute on function public.get_members() to authenticated;

create or replace function public.delete_member(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare
  v_paths jsonb;
  v_count integer;
begin
  if public.current_role() not in ('owner','admin') then
    raise exception 'Accès refusé';
  end if;
  select coalesce(jsonb_agg(path),'[]'::jsonb) into v_paths
  from (
    select photo_path as path from public.members where id=p_id and photo_path is not null
    union all
    select medical_path as path from public.members where id=p_id and medical_path is not null
  ) files;
  delete from public.members where id=p_id;
  get diagnostics v_count = row_count;
  if v_count=0 then
    raise exception 'FICHE_INTROUVABLE: cet adhérent a déjà été supprimé.';
  end if;
  return jsonb_build_object('count',v_count,'paths',v_paths);
end $$;

create or replace function public.delete_all_members()
returns jsonb language plpgsql security definer set search_path = public
as $$
declare
  v_paths jsonb;
  v_count integer;
begin
  if public.current_role() not in ('owner','admin') then
    raise exception 'Accès refusé';
  end if;
  select coalesce(jsonb_agg(path),'[]'::jsonb) into v_paths
  from (
    select photo_path as path from public.members where photo_path is not null
    union all
    select medical_path as path from public.members where medical_path is not null
  ) files;
  delete from public.members where id is not null;
  get diagnostics v_count = row_count;
  return jsonb_build_object('count',v_count,'paths',v_paths);
end $$;

revoke all on function public.delete_member(uuid) from public;
revoke all on function public.delete_all_members() from public;
grant execute on function public.delete_member(uuid) to authenticated;
grant execute on function public.delete_all_members() to authenticated;

grant select,insert,update,delete on public.members to authenticated;
grant select on public.profiles to authenticated;

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('member-files','member-files',false,12582912,array['image/jpeg','image/png','image/webp','image/heic','application/pdf'])
on conflict (id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists "documents owner admin lecture" on storage.objects;
create policy "documents owner admin lecture" on storage.objects for select to authenticated
using (bucket_id='member-files' and public.current_role() in ('owner','admin'));

drop policy if exists "photos coach lecture" on storage.objects;
create policy "photos coach lecture" on storage.objects for select to authenticated
using (bucket_id='member-files' and public.current_role()='coach' and name like '%/photo.%');

drop policy if exists "documents owner admin ajout" on storage.objects;
create policy "documents owner admin ajout" on storage.objects for insert to authenticated
with check (bucket_id='member-files' and public.current_role() in ('owner','admin'));

drop policy if exists "documents owner admin modification" on storage.objects;
create policy "documents owner admin modification" on storage.objects for update to authenticated
using (bucket_id='member-files' and public.current_role() in ('owner','admin'))
with check (bucket_id='member-files' and public.current_role() in ('owner','admin'));

drop policy if exists "documents owner admin suppression" on storage.objects;
create policy "documents owner admin suppression" on storage.objects for delete to authenticated
using (bucket_id='member-files' and public.current_role() in ('owner','admin'));

-- Après avoir créé les 3 utilisateurs dans Authentication > Users,
-- remplacer les e-mails ci-dessous puis exécuter séparément :
-- insert into public.profiles(user_id,role)
-- select id, case email
--   when 'proprietaire@exemple.fr' then 'owner'
--   when 'administrateur@exemple.fr' then 'admin'
--   when 'coach@exemple.fr' then 'coach'
-- end
-- from auth.users
-- where email in ('proprietaire@exemple.fr','administrateur@exemple.fr','coach@exemple.fr')
-- on conflict (user_id) do update set role=excluded.role;
