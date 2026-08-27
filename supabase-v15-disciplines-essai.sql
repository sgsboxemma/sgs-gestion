-- SGS Gestion V15 - Disciplines des cours d'essai
-- A executer UNE SEULE FOIS dans Supabase > SQL Editor avec le role postgres.

alter table public.trial_members
  add column if not exists disciplines text[] not null default '{}'::text[];

-- Les trois profils peuvent deja modifier trial_members via les politiques V13.
-- On re-applique le droit UPDATE pour securiser une installation existante.
grant select, insert, update, delete on public.trial_members to authenticated;

-- Verification facultative : cette requete doit afficher la colonne disciplines.
select column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name = 'trial_members'
  and column_name = 'disciplines';
