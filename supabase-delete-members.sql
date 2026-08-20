-- SGS Gestion V9.9 - Suppression sécurisée des adhérents.
-- À exécuter une seule fois dans Supabase > SQL Editor > New query.

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

  select coalesce(jsonb_agg(path),'[]'::jsonb)
  into v_paths
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

  select coalesce(jsonb_agg(path),'[]'::jsonb)
  into v_paths
  from (
    select photo_path as path from public.members where photo_path is not null
    union all
    select medical_path as path from public.members where medical_path is not null
  ) files;

  -- La clause WHERE explicite est requise par la protection Safe Update de Supabase.
  delete from public.members where id is not null;
  get diagnostics v_count = row_count;

  return jsonb_build_object('count',v_count,'paths',v_paths);
end $$;

revoke all on function public.delete_member(uuid) from public;
revoke all on function public.delete_all_members() from public;
grant execute on function public.delete_member(uuid) to authenticated;
grant execute on function public.delete_all_members() to authenticated;
