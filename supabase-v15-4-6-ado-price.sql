-- SGS Gestion V15.4.6 - Tarif Ado 2 activites = 300 EUR
-- Cette requete ne modifie, ne supprime et ne cree aucun adherent.
-- Elle ne modifie aucune table ni colonne. Elle remplace uniquement la fonction
-- de lecture utilisee pour calculer le statut paiement dans la Vue coach.

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
    v_theory := case v_ado_count when 1 then 220 when 2 then 300 else 380 end;
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
      and (x.created_at < m.created_at or (x.created_at = m.created_at and x.id::text < m.id::text));
  end if;

  if v_position between 2 and 4 then v_discount := 20; end if;
  v_suggested := greatest(0,v_theory-v_discount);

  -- Le montant stocke n'est jamais modifie. Pour la lecture Coach, on ne demande
  -- jamais plus que le nouveau tarif officiel calcule.
  v_effective_due := least(coalesce(m.due,v_suggested),v_suggested);

  select coalesce(sum(
    case when coalesce(p->>'amount','') ~ '^[0-9]+([.][0-9]+)?$' then (p->>'amount')::numeric else 0 end
  ),0) into v_paid
  from jsonb_array_elements(coalesce(m.payments,'[]'::jsonb)) p;

  return v_paid >= v_effective_due;
end $$;

revoke all on function public.coach_member_payment_ok(uuid) from public;
