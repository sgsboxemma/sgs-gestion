-- SGS Gestion V15.3.7 - Correction du statut de paiement dans la vue Coach.
-- IMPORTANT : ce script ne modifie, ne supprime et ne cree AUCUN adherent.
-- Il ne modifie ni table, ni colonne, ni fichier Storage.
-- Il remplace uniquement une fonction de lecture/calcul utilisee par la vue Coach.

create or replace function public.coach_member_payment_ok(p_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_due numeric := 0;
  v_paid numeric := 0;
begin
  select greatest(coalesce(m.due, 0), 0)
    into v_due
    from public.members m
   where m.id = p_id;

  if not found then
    return false;
  end if;

  select coalesce(sum(
    case
      when jsonb_typeof(p->'amount') = 'number' then (p->>'amount')::numeric
      when coalesce(p->>'amount','') ~ '^[0-9]+([.][0-9]+)?$' then (p->>'amount')::numeric
      else 0
    end
  ), 0)
    into v_paid
    from public.members m
    cross join lateral jsonb_array_elements(coalesce(m.payments, '[]'::jsonb)) p
   where m.id = p_id;

  return v_paid + 0.001 >= v_due;
end;
$$;

revoke all on function public.coach_member_payment_ok(uuid) from public;
