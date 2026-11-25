-- Compte joueur : avatar, « Mes jeux », suppression du compte en un bouton.

-- Avatar pixel choisi parmi une liste fixe.
alter table public.profiles
  add column if not exists avatar text not null default 'slime-lime';
alter table public.profiles drop constraint if exists profiles_avatar_check;
alter table public.profiles add constraint profiles_avatar_check check (avatar in (
  'slime-lime','slime-violet','fantome-blanc','fantome-cyan','crane-jaune','crane-rose','chat-orange','chat-violet'));
grant update (avatar) on public.profiles to authenticated;

-- À la suppression d'un compte, ses événements restent dans les statistiques mais deviennent anonymes.
alter table public.events drop constraint if exists events_user_id_fkey;
alter table public.events add constraint events_user_id_fkey
  foreign key (user_id) references auth.users(id) on delete set null;

-- « Mes jeux » : parties, temps de jeu et dernière partie du joueur connecté, par jeu.
create or replace function public.my_games()
returns table (game_id text, launches bigint, play_s bigint, last_at timestamptz)
language sql
stable
security invoker
set search_path = ''
as $$
  select e.game_id,
         count(*) filter (where e.type = 'launch'),
         coalesce(sum(e.duration_s) filter (where e.type = 'session_end'), 0),
         max(e.created_at) filter (where e.type = 'launch')
  from public.events e
  where e.user_id = (select auth.uid()) and e.game_id is not null
  group by e.game_id;
$$;
revoke execute on function public.my_games() from public, anon;
grant execute on function public.my_games() to authenticated;

-- Suppression du compte : la fonction privée a les droits sur auth.users,
-- la fonction publique ne fait que l'appeler pour l'utilisateur connecté.
create or replace function private.delete_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare me uuid := auth.uid();
begin
  if me is null then
    raise exception 'non connecté' using errcode = '42501';
  end if;
  delete from auth.users where id = me;
end;
$$;
revoke execute on function private.delete_account() from public, anon;
grant execute on function private.delete_account() to authenticated;

create or replace function public.delete_my_account()
returns void
language sql
security invoker
set search_path = ''
as $$ select private.delete_account(); $$;
revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
