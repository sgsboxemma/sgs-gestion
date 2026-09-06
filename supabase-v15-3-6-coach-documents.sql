-- SGS Gestion V15.3.6 - Vue Coach : statut paiement, lecture et gestion photo/certificat.
-- IMPORTANT : l'execution de ce script ne modifie et ne supprime AUCUN adherent existant.
-- Il ne cree ni table ni colonne et n'ecrit aucune ligne dans public.members.
-- Il met uniquement a jour des fonctions de lecture/ecriture ciblees et des policies Storage.

create or replace function public.coach_member_payment_ok(p_id uuid)
returns boolean language plpgsql stable security definer set search_path = public
as $$
declare
  m public.members%rowtype;
  v_ado_count integer := 0;
  v_adult_count integer := 0;
  v_has_baby boolean := false;
  v_has_child boolean := false;
  v_theory numeric := 0;
  v_position integer := 1;
  v_discount numeric := 0;
  v_suggested numeric := 0;
  v_effective_due numeric := 0;
  v_paid numeric := 0;
begin
  select * into m from public.members where id = p_id;
  if not found then return false; end if;

  select
    count(*) filter (where a.value in ('Boxe ados','MMA Ado','Striking ados')),
    count(*) filter (where a.value in ('Boxe adultes','Grappling','Striking adultes')),
    bool_or(a.value = 'Baby boxe'),
    bool_or(a.value = 'Boxe enfants')
  into v_ado_count,v_adult_count,v_has_baby,v_has_child
  from jsonb_array_elements_text(coalesce(m.acts,'[]'::jsonb)) as a(value);

  v_has_baby := coalesce(v_has_baby,false);
  v_has_child := coalesce(v_has_child,false);

  if v_has_baby and jsonb_array_length(coalesce(m.acts,'[]'::jsonb)) = 1 then
    v_theory := 130;
  elsif v_has_child and jsonb_array_length(coalesce(m.acts,'[]'::jsonb)) = 1 then
    v_theory := 220;
  elsif v_ado_count > 0 and v_adult_count = 0 and not v_has_baby and not v_has_child then
    v_theory := case v_ado_count when 1 then 220 when 2 then 340 else 380 end;
  elsif v_adult_count > 0 and v_ado_count = 0 and not v_has_baby and not v_has_child then
    v_theory := case v_adult_count when 1 then 270 when 2 then 350 else 400 end;
  else
    v_theory := 0;
  end if;

  if nullif(btrim(coalesce(m.address,'')),'') is not null
     and nullif(btrim(coalesce(m.zip,'')),'') is not null
     and nullif(btrim(coalesce(m.city,'')),'') is not null then
    select 1 + count(*) into v_position
    from public.members x
    where x.id <> m.id
      and lower(btrim(coalesce(x.address,''))) = lower(btrim(m.address))
      and btrim(coalesce(x.zip,'')) = btrim(m.zip)
      and lower(btrim(coalesce(x.city,''))) = lower(btrim(m.city))
      and (
        x.created_at < m.created_at
        or (x.created_at = m.created_at and x.id::text < m.id::text)
      );
  end if;

  if v_position between 2 and 4 then v_discount := 20; end if;
  v_suggested := greatest(0,v_theory-v_discount);

  if v_discount = 0 and v_theory >= 20 and abs(m.due-(v_theory-20)) < 0.001 then
    v_effective_due := v_theory;
  else
    v_effective_due := least(m.due,v_suggested);
  end if;

  select coalesce(sum(
    case
      when coalesce(p->>'amount','') ~ '^[0-9]+([.][0-9]+)?$' then (p->>'amount')::numeric
      else 0
    end
  ),0)
  into v_paid
  from jsonb_array_elements(coalesce(m.payments,'[]'::jsonb)) p;

  return v_paid >= v_effective_due;
end $$;

revoke all on function public.coach_member_payment_ok(uuid) from public;

create or replace function public.get_members()
returns jsonb language plpgsql stable security definer set search_path = public
as $$
declare r text := public.current_role();
begin
  if r = 'coach' then
    return coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id',m.id,
          'last_name',m.last_name,
          'first_name',m.first_name,
          'sex',m.sex,
          'birth',m.birth,
          'phone',m.phone,
          'acts',m.acts,
          'photo_path',m.photo_path,
          'medical_path',m.medical_path,
          'medical_name',m.medical_name,
          'has_medical',(m.medical_path is not null and btrim(m.medical_path) <> ''),
          'payment_ok',public.coach_member_payment_ok(m.id),
          'created_at',m.created_at,
          'updated_at',m.updated_at,
          'version',m.version
        )
        order by m.last_name,m.first_name
      )
      from public.members m
    ),'[]'::jsonb);
  elsif r in ('owner','admin') then
    return coalesce((select jsonb_agg(to_jsonb(m) order by last_name,first_name) from public.members m),'[]'::jsonb);
  end if;
  raise exception 'Acces refuse';
end $$;

revoke all on function public.get_members() from public;
grant execute on function public.get_members() to authenticated;

-- Le Coach ne peut modifier que le chemin de photo OU de certificat de l'adherent vise.
-- Aucun autre champ metier n'est modifiable par cette fonction.
create or replace function public.coach_set_member_document(
  p_id uuid,
  p_kind text,
  p_path text,
  p_name text default null
)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare
  v_saved public.members%rowtype;
  v_old_path text;
begin
  if public.current_role() <> 'coach' then
    raise exception 'Acces refuse';
  end if;

  if p_kind not in ('photo','medical') then
    raise exception 'Type de document invalide';
  end if;

  if p_path is null or p_path not like p_id::text || '/' || p_kind || '-%' then
    raise exception 'Chemin de document invalide';
  end if;

  if p_kind = 'photo' and p_path !~* '^[0-9a-f-]{36}/photo-[0-9a-f-]+\.(jpg|jpeg|png|webp|heic)$' then
    raise exception 'Format de photo invalide';
  end if;

  if p_kind = 'medical' and p_path !~* '^[0-9a-f-]{36}/medical-[0-9a-f-]+\.(jpg|jpeg|png|webp|heic|pdf)$' then
    raise exception 'Format de certificat invalide';
  end if;

  if not exists (
    select 1 from storage.objects
    where bucket_id = 'member-files' and name = p_path
  ) then
    raise exception 'Le document envoye est introuvable';
  end if;

  select case when p_kind = 'photo' then photo_path else medical_path end
    into v_old_path
    from public.members
   where id = p_id
   for update;

  if not found then
    raise exception 'Adherent introuvable';
  end if;

  if p_kind = 'photo' then
    update public.members
       set photo_path = p_path,
           version = version + 1,
           updated_at = clock_timestamp()
     where id = p_id
     returning * into v_saved;
  else
    update public.members
       set medical_path = p_path,
           medical_name = nullif(btrim(coalesce(p_name,'')) ,''),
           version = version + 1,
           updated_at = clock_timestamp()
     where id = p_id
     returning * into v_saved;
  end if;

  return jsonb_build_object(
    'id', v_saved.id,
    'version', v_saved.version,
    'has_medical', (v_saved.medical_path is not null and btrim(v_saved.medical_path) <> ''),
    'old_path', coalesce(v_old_path,'')
  );
end $$;

revoke all on function public.coach_set_member_document(uuid,text,text,text) from public;
grant execute on function public.coach_set_member_document(uuid,text,text,text) to authenticated;

-- Lecture Coach : uniquement les fichiers actuellement references par une fiche adherent.
create or replace function public.coach_can_read_member_document(p_name text)
returns boolean language sql stable security definer set search_path = public
as $$
  select
    public.current_role() = 'coach'
    and exists (
      select 1
      from public.members m
      where m.photo_path = p_name or m.medical_path = p_name
    );
$$;

revoke all on function public.coach_can_read_member_document(text) from public;
grant execute on function public.coach_can_read_member_document(text) to authenticated;

-- Ajout Coach : uniquement photo/certificat dans le dossier UUID d'un adherent existant.
create or replace function public.coach_can_upload_member_document(p_name text)
returns boolean language sql stable security definer set search_path = public
as $$
  select
    public.current_role() = 'coach'
    and (
      p_name ~* '^[0-9a-f-]{36}/photo-[0-9a-f-]+\.(jpg|jpeg|png|webp|heic)$'
      or p_name ~* '^[0-9a-f-]{36}/medical-[0-9a-f-]+\.(jpg|jpeg|png|webp|heic|pdf)$'
    )
    and exists (
      select 1
      from public.members m
      where m.id::text = split_part(p_name,'/',1)
    );
$$;

revoke all on function public.coach_can_upload_member_document(text) from public;
grant execute on function public.coach_can_upload_member_document(text) to authenticated;

-- Suppression Coach : uniquement un ancien document devenu orphelin.
-- Un fichier encore reference par un adherent ne peut jamais etre supprime via cette policy.
create or replace function public.coach_can_delete_orphan_document(p_name text)
returns boolean language sql stable security definer set search_path = public
as $$
  select
    public.current_role() = 'coach'
    and (
      p_name ~* '^[0-9a-f-]{36}/photo-[0-9a-f-]+\.(jpg|jpeg|png|webp|heic)$'
      or p_name ~* '^[0-9a-f-]{36}/medical-[0-9a-f-]+\.(jpg|jpeg|png|webp|heic|pdf)$'
    )
    and not exists (
      select 1
      from public.members m
      where m.photo_path = p_name or m.medical_path = p_name
    );
$$;

revoke all on function public.coach_can_delete_orphan_document(text) from public;
grant execute on function public.coach_can_delete_orphan_document(text) to authenticated;

-- Nettoyage des anciennes policies Coach, si une version precedente a ete testee.
drop policy if exists "photos coach lecture" on storage.objects;
drop policy if exists "documents coach lecture" on storage.objects;
drop policy if exists "coach ajoute documents" on storage.objects;
drop policy if exists "coach supprime documents orphelins" on storage.objects;

-- Le Coach peut lire uniquement la photo et le certificat actuellement lies aux adherents.
create policy "documents coach lecture" on storage.objects for select to authenticated
using (
  bucket_id = 'member-files'
  and public.coach_can_read_member_document(name)
);

-- Le Coach peut uniquement ajouter un nouveau fichier photo/certificat dans le dossier de l'adherent.
create policy "coach ajoute documents" on storage.objects for insert to authenticated
with check (
  bucket_id = 'member-files'
  and public.coach_can_upload_member_document(name)
);

-- Le Coach peut supprimer uniquement un ancien fichier devenu orphelin apres remplacement.
create policy "coach supprime documents orphelins" on storage.objects for delete to authenticated
using (
  bucket_id = 'member-files'
  and public.coach_can_delete_orphan_document(name)
);
